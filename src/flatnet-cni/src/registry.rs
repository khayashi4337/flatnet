//! Container Registry Client
//!
//! Handles registration and deregistration of container information
//! with the Gateway API for multihost container discovery.

use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::error::{CniError, CniErrorCode};

/// Default timeout for registry operations (5 seconds)
const REGISTRY_TIMEOUT_SECS: u64 = 5;

/// Container information to register with the Gateway
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContainerInfo {
    /// Container ID (from CNI)
    pub id: String,

    /// Allocated IP address
    pub ip: String,

    /// Container hostname (if available)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hostname: Option<String>,

    /// Exposed ports
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ports: Option<Vec<u16>>,

    /// Host ID where this container runs
    pub host_id: u8,

    /// Creation timestamp (ISO 8601)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub created_at: Option<String>,
}

impl ContainerInfo {
    /// Create new container info
    pub fn new(id: String, ip: String, host_id: u8) -> Self {
        Self {
            id,
            ip,
            hostname: None,
            ports: None,
            host_id,
            created_at: Some(chrono_now()),
        }
    }

    /// Set hostname
    pub fn with_hostname(mut self, hostname: String) -> Self {
        self.hostname = Some(hostname);
        self
    }

    /// Set ports
    pub fn with_ports(mut self, ports: Vec<u16>) -> Self {
        self.ports = Some(ports);
        self
    }
}

/// Simple ISO 8601 timestamp without external crate
fn chrono_now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};

    let duration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();

    // Simple Unix timestamp in seconds (not full ISO 8601, but parseable)
    format!("{}", duration.as_secs())
}

/// Registry client for communicating with Gateway API
pub struct RegistryClient {
    endpoints: Vec<String>,
    timeout: Duration,
}

impl RegistryClient {
    /// Create a new registry client with the given endpoints
    pub fn new(endpoints: Vec<String>) -> Self {
        Self {
            endpoints,
            timeout: Duration::from_secs(REGISTRY_TIMEOUT_SECS),
        }
    }

    /// Set custom timeout
    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = timeout;
        self
    }

    /// Register a container with all endpoints
    ///
    /// Returns Ok(()) if at least one endpoint succeeds.
    /// This allows graceful degradation when some Gateways are down.
    pub fn register(&self, info: &ContainerInfo) -> Result<(), CniError> {
        if self.endpoints.is_empty() {
            eprintln!("flatnet registry: no endpoints configured, skipping registration");
            return Ok(());
        }

        let body = serde_json::to_string(info).map_err(|e| {
            CniError::new(CniErrorCode::IoFailure, "failed to serialize container info")
                .with_details(&e.to_string())
        })?;

        let mut success_count = 0;
        let mut last_error = None;

        for endpoint in &self.endpoints {
            match self.post_to_endpoint(endpoint, &body) {
                Ok(()) => {
                    eprintln!(
                        "flatnet registry: registered container {} at {}",
                        info.id, endpoint
                    );
                    success_count += 1;
                }
                Err(e) => {
                    eprintln!(
                        "flatnet registry: failed to register at {}: {}",
                        endpoint,
                        e.message()
                    );
                    last_error = Some(e);
                }
            }
        }

        if success_count > 0 {
            Ok(())
        } else {
            Err(last_error.unwrap_or_else(|| {
                CniError::new(CniErrorCode::IoFailure, "no registry endpoints available")
            }))
        }
    }

    /// Deregister a container from all endpoints
    ///
    /// Returns Ok(()) if at least one endpoint succeeds.
    pub fn deregister(&self, container_id: &str) -> Result<(), CniError> {
        if self.endpoints.is_empty() {
            eprintln!("flatnet registry: no endpoints configured, skipping deregistration");
            return Ok(());
        }

        let mut success_count = 0;
        let mut last_error = None;

        for endpoint in &self.endpoints {
            match self.delete_from_endpoint(endpoint, container_id) {
                Ok(()) => {
                    eprintln!(
                        "flatnet registry: deregistered container {} from {}",
                        container_id, endpoint
                    );
                    success_count += 1;
                }
                Err(e) => {
                    eprintln!(
                        "flatnet registry: failed to deregister from {}: {}",
                        endpoint,
                        e.message()
                    );
                    last_error = Some(e);
                }
            }
        }

        if success_count > 0 {
            Ok(())
        } else {
            // For DEL operations, we're more lenient - log warning but don't fail
            if let Some(e) = last_error {
                eprintln!(
                    "flatnet registry: WARNING - could not deregister {}: {}",
                    container_id,
                    e.message()
                );
            }
            Ok(())
        }
    }

    /// POST container info to an endpoint
    fn post_to_endpoint(&self, endpoint: &str, body: &str) -> Result<(), CniError> {
        let (host, port, path) = parse_endpoint(endpoint)?;

        let request = format!(
            "POST {} HTTP/1.1\r\n\
             Host: {}\r\n\
             Content-Type: application/json\r\n\
             Content-Length: {}\r\n\
             Connection: close\r\n\
             \r\n\
             {}",
            path,
            host,
            body.len(),
            body
        );

        self.send_request(&host, port, &request)
    }

    /// DELETE container from an endpoint
    fn delete_from_endpoint(&self, endpoint: &str, container_id: &str) -> Result<(), CniError> {
        let (host, port, path) = parse_endpoint(endpoint)?;

        // Append container ID to path
        let delete_path = format!("{}/{}", path.trim_end_matches('/'), container_id);

        let request = format!(
            "DELETE {} HTTP/1.1\r\n\
             Host: {}\r\n\
             Connection: close\r\n\
             \r\n",
            delete_path,
            host
        );

        self.send_request(&host, port, &request)
    }

    /// Send HTTP request and check response
    fn send_request(&self, host: &str, port: u16, request: &str) -> Result<(), CniError> {
        let addr = format!("{}:{}", host, port);

        let mut stream = TcpStream::connect_timeout(
            &addr.parse().map_err(|e: std::net::AddrParseError| {
                CniError::new(CniErrorCode::IoFailure, "invalid endpoint address")
                    .with_details(&e.to_string())
            })?,
            self.timeout,
        )
        .map_err(|e| {
            CniError::new(CniErrorCode::IoFailure, "failed to connect to registry")
                .with_details(&e.to_string())
        })?;

        stream.set_read_timeout(Some(self.timeout)).ok();
        stream.set_write_timeout(Some(self.timeout)).ok();

        stream.write_all(request.as_bytes()).map_err(|e| {
            CniError::new(CniErrorCode::IoFailure, "failed to send request")
                .with_details(&e.to_string())
        })?;

        // Read response
        let mut response = Vec::new();
        stream.read_to_end(&mut response).map_err(|e| {
            CniError::new(CniErrorCode::IoFailure, "failed to read response")
                .with_details(&e.to_string())
        })?;

        // Check for success status (2xx)
        let response_str = String::from_utf8_lossy(&response);
        if let Some(status_line) = response_str.lines().next() {
            // Match HTTP/1.x 2XX status codes
            if status_line.contains(" 200 ")
                || status_line.contains(" 201 ")
                || status_line.contains(" 202 ")
                || status_line.contains(" 204 ")
            {
                return Ok(());
            }
            return Err(CniError::new(
                CniErrorCode::IoFailure,
                &format!("registry request failed: {}", status_line),
            ));
        }

        Err(CniError::new(
            CniErrorCode::IoFailure,
            "invalid response from registry",
        ))
    }
}

/// Parse endpoint URL into (host, port, path)
fn parse_endpoint(endpoint: &str) -> Result<(String, u16, String), CniError> {
    // Simple URL parsing without external crate
    let url = endpoint
        .strip_prefix("http://")
        .ok_or_else(|| CniError::new(CniErrorCode::InvalidNetworkConfig, "endpoint must use http://"))?;

    let (host_port, path) = match url.find('/') {
        Some(idx) => (&url[..idx], &url[idx..]),
        None => (url, "/"),
    };

    let (host, port) = match host_port.find(':') {
        Some(idx) => {
            let h = &host_port[..idx];
            let p = host_port[idx + 1..]
                .parse()
                .map_err(|_| CniError::new(CniErrorCode::InvalidNetworkConfig, "invalid port in endpoint"))?;
            (h.to_string(), p)
        }
        None => (host_port.to_string(), 80),
    };

    Ok((host, port, path.to_string()))
}

/// Try to register a container, but don't fail the CNI operation if it fails
///
/// This is used for graceful degradation - local networking should work
/// even if the registry is unavailable.
pub fn try_register(endpoints: &[String], info: &ContainerInfo) {
    if endpoints.is_empty() {
        return;
    }

    let client = RegistryClient::new(endpoints.to_vec());
    if let Err(e) = client.register(info) {
        eprintln!(
            "flatnet registry: WARNING - registration failed (container will work locally): {}",
            e.message()
        );
    }
}

/// Try to deregister a container, but don't fail the CNI operation if it fails
pub fn try_deregister(endpoints: &[String], container_id: &str) {
    if endpoints.is_empty() {
        return;
    }

    let client = RegistryClient::new(endpoints.to_vec());
    if let Err(e) = client.deregister(container_id) {
        eprintln!(
            "flatnet registry: WARNING - deregistration failed: {}",
            e.message()
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_endpoint() {
        let (host, port, path) = parse_endpoint("http://10.100.1.1:8080/api/containers").unwrap();
        assert_eq!(host, "10.100.1.1");
        assert_eq!(port, 8080);
        assert_eq!(path, "/api/containers");
    }

    #[test]
    fn test_parse_endpoint_default_port() {
        let (host, port, path) = parse_endpoint("http://gateway.local/api").unwrap();
        assert_eq!(host, "gateway.local");
        assert_eq!(port, 80);
        assert_eq!(path, "/api");
    }

    #[test]
    fn test_parse_endpoint_no_path() {
        let (host, port, path) = parse_endpoint("http://10.100.1.1:8080").unwrap();
        assert_eq!(host, "10.100.1.1");
        assert_eq!(port, 8080);
        assert_eq!(path, "/");
    }

    #[test]
    fn test_parse_endpoint_invalid() {
        assert!(parse_endpoint("https://secure.example.com").is_err());
        assert!(parse_endpoint("not-a-url").is_err());
    }

    #[test]
    fn test_container_info_new() {
        let info = ContainerInfo::new(
            "abc123".to_string(),
            "10.100.1.10".to_string(),
            1,
        );
        assert_eq!(info.id, "abc123");
        assert_eq!(info.ip, "10.100.1.10");
        assert_eq!(info.host_id, 1);
        assert!(info.created_at.is_some());
    }

    #[test]
    fn test_container_info_with_extras() {
        let info = ContainerInfo::new("abc123".to_string(), "10.100.1.10".to_string(), 1)
            .with_hostname("my-service".to_string())
            .with_ports(vec![80, 443]);

        assert_eq!(info.hostname, Some("my-service".to_string()));
        assert_eq!(info.ports, Some(vec![80, 443]));
    }

    #[test]
    fn test_registry_client_empty_endpoints() {
        let client = RegistryClient::new(vec![]);
        let info = ContainerInfo::new("test".to_string(), "10.100.1.10".to_string(), 1);

        // Should succeed (no-op) with empty endpoints
        assert!(client.register(&info).is_ok());
        assert!(client.deregister("test").is_ok());
    }
}
