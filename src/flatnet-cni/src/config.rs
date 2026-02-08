//! CNI Network Configuration parsing
//!
//! Handles parsing of the network configuration JSON passed via stdin.
//! Supports multihost configuration with host ID and registry endpoints.

use serde::{Deserialize, Serialize};

/// Network configuration passed to the CNI plugin
///
/// See: https://github.com/containernetworking/cni/blob/spec-v1.0.0/SPEC.md#network-configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NetworkConfig {
    /// CNI specification version
    pub cni_version: String,

    /// Network name (must be unique on the host)
    pub name: String,

    /// CNI plugin type (matches binary name)
    #[serde(rename = "type")]
    pub plugin_type: String,

    /// Previous result from chain (for CHECK/DEL)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub prev_result: Option<serde_json::Value>,

    // Flatnet-specific configuration

    /// Bridge name (default: "flatnet-br0")
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bridge: Option<String>,

    /// MTU for the interface
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mtu: Option<u32>,

    /// Enable IP masquerading
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ip_masq: Option<bool>,

    /// IPAM configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ipam: Option<IpamConfig>,

    /// DNS configuration
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dns: Option<DnsConfig>,

    /// Additional arguments
    #[serde(skip_serializing_if = "Option::is_none")]
    pub args: Option<serde_json::Value>,

    // Multihost-specific configuration

    /// Host ID for multihost IP allocation (1-254)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub host_id: Option<u8>,

    /// Registry endpoints for container info sharing
    #[serde(skip_serializing_if = "Option::is_none")]
    pub registry_endpoints: Option<Vec<String>>,

    /// Enable registry synchronization (default: true if endpoints provided)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub registry_enabled: Option<bool>,
}

impl NetworkConfig {
    /// Get the bridge name, defaulting to "flatnet-br0"
    pub fn bridge_name(&self) -> &str {
        self.bridge.as_deref().unwrap_or(crate::bridge::DEFAULT_BRIDGE_NAME)
    }

    /// Get the MTU value for network interfaces
    ///
    /// Returns the configured MTU or the default value of 1500 bytes.
    pub fn mtu_value(&self) -> u32 {
        self.mtu.unwrap_or(1500)
    }

    /// Get the host ID for multihost IP allocation
    ///
    /// Returns the configured host ID or the default value of 1.
    pub fn host_id_value(&self) -> u8 {
        self.host_id.unwrap_or(1)
    }

    /// Check if registry synchronization is enabled
    pub fn is_registry_enabled(&self) -> bool {
        self.registry_enabled.unwrap_or_else(|| self.registry_endpoints.is_some())
    }

    /// Get registry endpoints
    pub fn registry_endpoints(&self) -> &[String] {
        self.registry_endpoints.as_deref().unwrap_or(&[])
    }
}

/// IPAM (IP Address Management) configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IpamConfig {
    /// IPAM plugin type (e.g., "host-local", "flatnet-ipam")
    #[serde(rename = "type")]
    pub plugin_type: String,

    /// Subnet in CIDR notation
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subnet: Option<String>,

    /// Gateway IP address
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gateway: Option<String>,

    /// Routes to configure
    #[serde(skip_serializing_if = "Option::is_none")]
    pub routes: Option<Vec<Route>>,

    /// IP address ranges to allocate from
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ranges: Option<Vec<Vec<IpRange>>>,

    /// Host ID for multihost IP allocation (overrides network-level setting)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub host_id: Option<u8>,
}

/// Route configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Route {
    /// Destination network in CIDR notation
    pub dst: String,

    /// Gateway IP (optional, uses subnet gateway if not specified)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gw: Option<String>,
}

/// IP address range for IPAM
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct IpRange {
    /// Subnet in CIDR notation
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subnet: Option<String>,

    /// Start of IP range
    #[serde(skip_serializing_if = "Option::is_none")]
    pub range_start: Option<String>,

    /// End of IP range
    #[serde(skip_serializing_if = "Option::is_none")]
    pub range_end: Option<String>,

    /// Gateway IP
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gateway: Option<String>,
}

/// DNS configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DnsConfig {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_minimal_config() {
        let json = r#"{
            "cniVersion": "1.0.0",
            "name": "test-network",
            "type": "flatnet"
        }"#;

        let config: NetworkConfig = serde_json::from_str(json).unwrap();
        assert_eq!(config.cni_version, "1.0.0");
        assert_eq!(config.name, "test-network");
        assert_eq!(config.plugin_type, "flatnet");
        assert_eq!(config.bridge_name(), "flatnet-br0");
        assert_eq!(config.mtu_value(), 1500);
        assert_eq!(config.host_id_value(), 1);
        assert!(!config.is_registry_enabled());
    }

    #[test]
    fn test_parse_full_config() {
        let json = r#"{
            "cniVersion": "1.0.0",
            "name": "flatnet",
            "type": "flatnet",
            "bridge": "flatnet0",
            "mtu": 9000,
            "ipMasq": true,
            "ipam": {
                "type": "host-local",
                "subnet": "10.42.0.0/16",
                "gateway": "10.42.0.1",
                "routes": [
                    {"dst": "0.0.0.0/0"}
                ]
            },
            "dns": {
                "nameservers": ["8.8.8.8", "8.8.4.4"],
                "domain": "example.com",
                "search": ["example.com", "local"]
            }
        }"#;

        let config: NetworkConfig = serde_json::from_str(json).unwrap();
        assert_eq!(config.bridge_name(), "flatnet0");
        assert_eq!(config.mtu_value(), 9000);
        assert!(config.ip_masq.unwrap());

        let ipam = config.ipam.unwrap();
        assert_eq!(ipam.plugin_type, "host-local");
        assert_eq!(ipam.subnet.unwrap(), "10.42.0.0/16");

        let dns = config.dns.unwrap();
        assert_eq!(dns.nameservers.unwrap().len(), 2);
    }

    #[test]
    fn test_parse_multihost_config() {
        let json = r#"{
            "cniVersion": "1.0.0",
            "name": "flatnet",
            "type": "flatnet",
            "hostId": 2,
            "registryEndpoints": ["http://10.100.0.1:8080/api/containers"],
            "registryEnabled": true,
            "ipam": {
                "type": "flatnet-ipam",
                "subnet": "10.100.2.0/24",
                "gateway": "10.100.2.1",
                "hostId": 2
            }
        }"#;

        let config: NetworkConfig = serde_json::from_str(json).unwrap();
        assert_eq!(config.host_id_value(), 2);
        assert!(config.is_registry_enabled());
        assert_eq!(config.registry_endpoints().len(), 1);

        let ipam = config.ipam.unwrap();
        assert_eq!(ipam.plugin_type, "flatnet-ipam");
        assert_eq!(ipam.host_id.unwrap(), 2);
    }

    #[test]
    fn test_registry_enabled_with_endpoints() {
        let json = r#"{
            "cniVersion": "1.0.0",
            "name": "flatnet",
            "type": "flatnet",
            "registryEndpoints": ["http://10.100.1.1:8080/api/containers"]
        }"#;

        let config: NetworkConfig = serde_json::from_str(json).unwrap();
        // Registry should be enabled when endpoints are provided
        assert!(config.is_registry_enabled());
    }
}
