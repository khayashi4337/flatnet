//! CNI Result types
//!
//! Output formats for CNI operations as defined in CNI Spec 1.0.0

use serde::{Deserialize, Serialize};

/// Result returned by ADD operation
///
/// See: https://github.com/containernetworking/cni/blob/spec-v1.0.0/SPEC.md#success
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CniResult {
    /// CNI specification version
    pub cni_version: String,

    /// Interfaces created
    #[serde(skip_serializing_if = "Option::is_none")]
    pub interfaces: Option<Vec<Interface>>,

    /// IP addresses assigned
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ips: Option<Vec<IpConfig>>,

    /// Routes configured
    #[serde(skip_serializing_if = "Option::is_none")]
    pub routes: Option<Vec<RouteConfig>>,

    /// DNS configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dns: Option<DnsResult>,
}

impl CniResult {
    /// Create a new CNI result
    pub fn new(cni_version: String) -> Self {
        Self {
            cni_version,
            interfaces: None,
            ips: None,
            routes: None,
            dns: None,
        }
    }

    /// Add an interface to the result
    pub fn with_interface(mut self, name: String, mac: String, sandbox: Option<String>) -> Self {
        let iface = Interface { name, mac, sandbox };
        match &mut self.interfaces {
            Some(interfaces) => interfaces.push(iface),
            None => self.interfaces = Some(vec![iface]),
        }
        self
    }

    /// Add an IP configuration to the result
    pub fn with_ip(mut self, address: String, gateway: Option<String>, interface: usize) -> Self {
        let ip = IpConfig {
            address,
            gateway,
            interface: Some(interface),
        };
        match &mut self.ips {
            Some(ips) => ips.push(ip),
            None => self.ips = Some(vec![ip]),
        }
        self
    }

    /// Add a route to the result
    ///
    /// # Arguments
    /// * `dst` - Destination network in CIDR notation (e.g., "0.0.0.0/0")
    /// * `gw` - Optional gateway IP address
    pub fn with_route(mut self, dst: String, gw: Option<String>) -> Self {
        let route = RouteConfig { dst, gw };
        match &mut self.routes {
            Some(routes) => routes.push(route),
            None => self.routes = Some(vec![route]),
        }
        self
    }

    /// Set DNS configuration
    pub fn with_dns(mut self, dns: DnsResult) -> Self {
        self.dns = Some(dns);
        self
    }
}

/// Network interface information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Interface {
    /// Interface name
    pub name: String,

    /// MAC address
    pub mac: String,

    /// Network namespace path (for container-side interfaces)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sandbox: Option<String>,
}

/// IP address configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IpConfig {
    /// IP address in CIDR notation
    pub address: String,

    /// Gateway IP address
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gateway: Option<String>,

    /// Index into interfaces array
    #[serde(skip_serializing_if = "Option::is_none")]
    pub interface: Option<usize>,
}

/// Route configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RouteConfig {
    /// Destination network in CIDR notation
    pub dst: String,

    /// Gateway IP address
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gw: Option<String>,
}

/// DNS configuration result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DnsResult {
    /// DNS nameserver IPs
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nameservers: Option<Vec<String>>,

    /// DNS domain
    #[serde(skip_serializing_if = "Option::is_none")]
    pub domain: Option<String>,

    /// DNS search domains
    #[serde(skip_serializing_if = "Option::is_none")]
    pub search: Option<Vec<String>>,

    /// DNS options
    #[serde(skip_serializing_if = "Option::is_none")]
    pub options: Option<Vec<String>>,
}

/// Result returned by VERSION operation
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VersionResult {
    /// Current CNI version
    pub cni_version: String,

    /// List of supported CNI versions
    pub supported_versions: Vec<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cni_result_builder() {
        let result = CniResult::new("1.0.0".to_string())
            .with_interface(
                "eth0".to_string(),
                "02:42:ac:11:00:02".to_string(),
                Some("/var/run/netns/ctr".to_string()),
            )
            .with_ip(
                "172.17.0.2/16".to_string(),
                Some("172.17.0.1".to_string()),
                0,
            )
            .with_route("0.0.0.0/0".to_string(), Some("172.17.0.1".to_string()));

        assert_eq!(result.cni_version, "1.0.0");
        assert_eq!(result.interfaces.as_ref().unwrap().len(), 1);
        assert_eq!(result.ips.as_ref().unwrap().len(), 1);
        assert_eq!(result.routes.as_ref().unwrap().len(), 1);
    }

    #[test]
    fn test_result_serialization() {
        let result = CniResult::new("1.0.0".to_string())
            .with_interface(
                "eth0".to_string(),
                "02:42:ac:11:00:02".to_string(),
                Some("/var/run/netns/ctr".to_string()),
            )
            .with_ip(
                "172.17.0.2/16".to_string(),
                Some("172.17.0.1".to_string()),
                0,
            );

        let json = serde_json::to_string(&result).unwrap();
        assert!(json.contains("\"cniVersion\":\"1.0.0\""));
        assert!(json.contains("\"interfaces\""));
        assert!(json.contains("\"ips\""));
    }

    #[test]
    fn test_version_result() {
        let result = VersionResult {
            cni_version: "1.0.0".to_string(),
            supported_versions: vec!["0.4.0".to_string(), "1.0.0".to_string()],
        };

        let json = serde_json::to_string(&result).unwrap();
        assert!(json.contains("\"cniVersion\":\"1.0.0\""));
        assert!(json.contains("\"supportedVersions\""));
    }
}
