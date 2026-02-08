//! Gateway API client
//!
//! HTTP client for communicating with the Flatnet Gateway API.

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use thiserror::Error;

/// Errors that can occur when communicating with the Gateway
#[derive(Error, Debug)]
pub enum GatewayError {
    #[error("Gateway connection failed: {0}")]
    ConnectionFailed(String),

    #[error("Gateway request failed: {0}")]
    RequestFailed(String),

    #[error("Gateway returned unexpected response: {0}")]
    InvalidResponse(String),

    #[error("Gateway timeout")]
    Timeout,
}

impl GatewayError {
    /// Convert a reqwest error to a GatewayError
    fn from_reqwest(e: reqwest::Error) -> Self {
        if e.is_timeout() {
            GatewayError::Timeout
        } else if e.is_connect() {
            GatewayError::ConnectionFailed(e.to_string())
        } else {
            GatewayError::RequestFailed(e.to_string())
        }
    }
}

/// Gateway API client
#[derive(Debug, Clone)]
pub struct GatewayClient {
    client: Client,
    base_url: String,
}

impl GatewayClient {
    /// Create a new Gateway client
    pub fn new(base_url: &str, timeout: Duration) -> Result<Self> {
        let client = Client::builder()
            .timeout(timeout)
            .build()
            .context("Failed to create HTTP client")?;

        Ok(Self {
            client,
            base_url: base_url.trim_end_matches('/').to_string(),
        })
    }

    /// Check if the Gateway is healthy
    pub async fn health(&self) -> Result<bool, GatewayError> {
        let url = format!("{}/api/health", self.base_url);

        match self.client.get(&url).send().await {
            Ok(response) => Ok(response.status().is_success()),
            Err(e) => Err(GatewayError::from_reqwest(e)),
        }
    }

    /// Get the Gateway status
    pub async fn status(&self) -> Result<GatewayStatus, GatewayError> {
        let url = format!("{}/api/status", self.base_url);

        let response = self
            .client
            .get(&url)
            .send()
            .await
            .map_err(GatewayError::from_reqwest)?;

        if !response.status().is_success() {
            return Err(GatewayError::RequestFailed(format!(
                "HTTP {}",
                response.status()
            )));
        }

        response
            .json::<GatewayStatus>()
            .await
            .map_err(|e| GatewayError::InvalidResponse(e.to_string()))
    }

    /// Get the list of containers
    pub async fn containers(&self) -> Result<Vec<ContainerInfo>, GatewayError> {
        let url = format!("{}/api/containers", self.base_url);

        let response = self
            .client
            .get(&url)
            .send()
            .await
            .map_err(GatewayError::from_reqwest)?;

        if !response.status().is_success() {
            return Err(GatewayError::RequestFailed(format!(
                "HTTP {}",
                response.status()
            )));
        }

        // The API might return containers in different formats
        // Try to parse as array first, then as object with containers field
        let body = response
            .text()
            .await
            .map_err(|e| GatewayError::InvalidResponse(e.to_string()))?;

        // Try direct array
        if let Ok(containers) = serde_json::from_str::<Vec<ContainerInfo>>(&body) {
            return Ok(containers);
        }

        // Try object with containers field
        if let Ok(wrapper) = serde_json::from_str::<ContainersResponse>(&body) {
            return Ok(wrapper.containers.unwrap_or_default());
        }

        // Empty or invalid response
        Ok(Vec::new())
    }
}

/// Gateway status response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GatewayStatus {
    /// Service status (e.g., "running")
    pub status: String,

    /// Service name
    #[serde(default)]
    pub service: String,

    /// API stage version
    #[serde(default)]
    pub stage: String,

    /// Registry statistics
    #[serde(default)]
    pub registry: Option<RegistryStats>,

    /// Sync status
    #[serde(default)]
    pub sync: Option<SyncStatus>,

    /// Escalation statistics
    #[serde(default)]
    pub escalation: Option<EscalationStats>,

    /// Routing statistics
    #[serde(default)]
    pub routing: Option<RoutingStats>,

    /// Healthcheck status
    #[serde(default)]
    pub healthcheck: Option<HealthcheckStatus>,
}

/// Registry statistics
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct RegistryStats {
    /// Total container count
    #[serde(default)]
    pub total_count: u32,

    /// Local container count
    #[serde(default)]
    pub local_count: u32,

    /// Remote container count
    #[serde(default)]
    pub remote_count: u32,
}

/// Sync status
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SyncStatus {
    /// Whether sync is enabled
    #[serde(default)]
    pub enabled: bool,

    /// Last sync time
    #[serde(default)]
    pub last_sync: Option<String>,

    /// Peer count
    #[serde(default)]
    pub peer_count: u32,
}

/// Escalation statistics
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct EscalationStats {
    /// Total escalations
    #[serde(default)]
    pub total: u32,

    /// Successful P2P connections
    #[serde(default)]
    pub p2p_success: u32,

    /// Failed P2P attempts (fallback to gateway)
    #[serde(default)]
    pub gateway_fallback: u32,
}

/// Routing statistics
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct RoutingStats {
    /// Routes via direct P2P
    #[serde(default)]
    pub direct_routes: u32,

    /// Routes via gateway
    #[serde(default)]
    pub gateway_routes: u32,
}

/// Healthcheck status
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct HealthcheckStatus {
    /// Whether healthcheck is enabled
    #[serde(default)]
    pub enabled: bool,

    /// Healthy targets count
    #[serde(default)]
    pub healthy_count: u32,

    /// Unhealthy targets count
    #[serde(default)]
    pub unhealthy_count: u32,
}

/// Container information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContainerInfo {
    /// Container ID
    pub id: String,

    /// Container IP address
    pub ip: String,

    /// Host ID
    #[serde(default)]
    pub host_id: u8,

    /// Container name (optional)
    #[serde(default)]
    pub name: Option<String>,

    /// Registration timestamp
    #[serde(default)]
    pub registered_at: Option<String>,
}

/// Containers response wrapper
#[derive(Debug, Clone, Serialize, Deserialize)]
struct ContainersResponse {
    containers: Option<Vec<ContainerInfo>>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_gateway_status() {
        let json = r#"{
            "status": "running",
            "service": "flatnet-gateway-api",
            "stage": "4",
            "registry": {
                "total_count": 3,
                "local_count": 2,
                "remote_count": 1
            }
        }"#;

        let status: GatewayStatus = serde_json::from_str(json).unwrap();
        assert_eq!(status.status, "running");
        assert_eq!(status.service, "flatnet-gateway-api");
        assert_eq!(status.registry.unwrap().total_count, 3);
    }

    #[test]
    fn test_parse_container_info() {
        let json = r#"{
            "id": "abc123",
            "ip": "10.100.1.10",
            "host_id": 1,
            "name": "web-server"
        }"#;

        let container: ContainerInfo = serde_json::from_str(json).unwrap();
        assert_eq!(container.id, "abc123");
        assert_eq!(container.ip, "10.100.1.10");
        assert_eq!(container.host_id, 1);
    }
}
