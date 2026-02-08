//! Flatnet CNI Plugin
//!
//! A CNI plugin that bridges containers across NAT boundaries.
//! Implements CNI Spec 1.0.0.

mod config;
mod error;
mod result;

use std::env;
use std::io::{self, Read};

use config::NetworkConfig;
use error::{CniError, CniErrorCode};
use result::{CniResult, VersionResult};

/// Maximum size of network config input (1 MB should be more than enough)
const MAX_INPUT_SIZE: u64 = 1024 * 1024;

/// CNI Spec version supported by this plugin
const CNI_VERSION: &str = "1.0.0";

/// Supported CNI versions
const SUPPORTED_VERSIONS: &[&str] = &["0.3.0", "0.3.1", "0.4.0", "1.0.0"];

fn main() {
    if let Err(e) = run() {
        // Output error in CNI format to stderr
        let error_output = serde_json::json!({
            "cniVersion": CNI_VERSION,
            "code": e.code() as u32,
            "msg": e.message(),
            "details": e.details()
        });
        // Use compact JSON for CNI spec compliance; unwrap_or for robustness
        eprintln!(
            "{}",
            serde_json::to_string(&error_output).unwrap_or_else(|_| {
                format!(
                    r#"{{"cniVersion":"{}","code":{},"msg":"{}"}}"#,
                    CNI_VERSION,
                    e.code() as u32,
                    e.message()
                )
            })
        );
        std::process::exit(1);
    }
}

fn run() -> Result<(), CniError> {
    // Get CNI command from environment
    let command = env::var("CNI_COMMAND").map_err(|_| {
        CniError::new(
            CniErrorCode::InvalidEnvironmentVariables,
            "CNI_COMMAND not set",
        )
    })?;

    // Read network config from stdin (with size limit to prevent OOM)
    let mut input = String::new();
    io::stdin()
        .take(MAX_INPUT_SIZE)
        .read_to_string(&mut input)
        .map_err(|e| {
            CniError::new(CniErrorCode::IoFailure, "failed to read stdin")
                .with_details(&e.to_string())
        })?;

    match command.as_str() {
        "ADD" => cmd_add(&input),
        "DEL" => cmd_del(&input),
        "CHECK" => cmd_check(&input),
        "VERSION" => cmd_version(&input),
        _ => {
            // Truncate command for safety in error message (avoid log injection)
            let safe_command: String = command
                .chars()
                .take(32)
                .filter(|c| c.is_ascii_alphanumeric() || *c == '_' || *c == '-')
                .collect();
            Err(CniError::new(
                CniErrorCode::InvalidEnvironmentVariables,
                &format!("unknown CNI_COMMAND: {}", safe_command),
            ))
        }
    }
}

/// Handle ADD command - create network interface
fn cmd_add(input: &str) -> Result<(), CniError> {
    let config: NetworkConfig = serde_json::from_str(input).map_err(|e| {
        CniError::new(CniErrorCode::DecodingFailure, "failed to parse network config")
            .with_details(&e.to_string())
    })?;

    // Get required environment variables
    let container_id = env::var("CNI_CONTAINERID").map_err(|_| {
        CniError::new(
            CniErrorCode::InvalidEnvironmentVariables,
            "CNI_CONTAINERID not set",
        )
    })?;

    let netns = env::var("CNI_NETNS").map_err(|_| {
        CniError::new(
            CniErrorCode::InvalidEnvironmentVariables,
            "CNI_NETNS not set",
        )
    })?;

    let ifname = env::var("CNI_IFNAME").map_err(|_| {
        CniError::new(
            CniErrorCode::InvalidEnvironmentVariables,
            "CNI_IFNAME not set",
        )
    })?;

    // TODO: Implement actual network setup in Stage 3
    // 1. Create veth pair
    // 2. Move one end to container namespace
    // 3. Assign IP address (via IPAM)
    // 4. Connect host end to bridge

    // Generate dummy IP and gateway from IPAM config if available
    // In Stage 2, we return a stub response using config values
    let (ip_address, gateway) = if let Some(ref ipam) = config.ipam {
        // Use subnet and gateway from config if available
        let subnet = ipam.subnet.as_deref().unwrap_or("10.87.1.0/24");
        let gw = ipam.gateway.as_deref().unwrap_or("10.87.1.1");

        // Parse subnet to generate a dummy container IP (use .2 in the subnet)
        // This is a stub - real IPAM will allocate properly
        let ip = generate_stub_ip(subnet);
        (ip, gw.to_string())
    } else {
        // Default fallback values
        ("10.87.1.2/24".to_string(), "10.87.1.1".to_string())
    };

    // Generate a dummy MAC address based on container ID
    let mac = generate_stub_mac(&container_id);

    // Build the result
    let result = CniResult::new(config.cni_version.clone())
        .with_interface(ifname.clone(), mac, Some(netns.clone()))
        .with_ip(ip_address.clone(), Some(gateway.clone()), 0)
        .with_route("0.0.0.0/0".to_string(), Some(gateway.clone()));

    // Log for debugging
    eprintln!(
        "flatnet ADD: container={}, netns={}, ifname={}, ip={}",
        container_id, netns, ifname, ip_address
    );

    // Output result to stdout
    println!(
        "{}",
        serde_json::to_string(&result).map_err(|e| {
            CniError::new(CniErrorCode::IoFailure, "failed to serialize result")
                .with_details(&e.to_string())
        })?
    );

    Ok(())
}

/// Generate a stub IP address from a subnet (for Stage 2 testing)
/// Takes "10.87.1.0/24" and returns "10.87.1.2/24"
fn generate_stub_ip(subnet: &str) -> String {
    // Split into network and prefix
    let parts: Vec<&str> = subnet.split('/').collect();
    if parts.len() != 2 {
        return "10.87.1.2/24".to_string();
    }

    let network = parts[0];
    let prefix = parts[1];

    // Split network into octets
    let octets: Vec<&str> = network.split('.').collect();
    if octets.len() != 4 {
        return "10.87.1.2/24".to_string();
    }

    // Replace the last octet with "2" (stub container IP)
    format!(
        "{}.{}.{}.2/{}",
        octets[0], octets[1], octets[2], prefix
    )
}

/// Generate a stub MAC address from container ID
fn generate_stub_mac(container_id: &str) -> String {
    // Use first 10 hex chars of container ID to generate MAC
    // Format: 02:xx:xx:xx:xx:xx (locally administered unicast)
    let hex_chars: String = container_id
        .chars()
        .filter(|c| c.is_ascii_hexdigit())
        .take(10)
        .collect();

    let padded = format!("{:0<10}", hex_chars);
    format!(
        "02:{}:{}:{}:{}:{}",
        &padded[0..2],
        &padded[2..4],
        &padded[4..6],
        &padded[6..8],
        &padded[8..10]
    )
}

/// Handle DEL command - remove network interface
fn cmd_del(input: &str) -> Result<(), CniError> {
    let _config: NetworkConfig = serde_json::from_str(input).map_err(|e| {
        CniError::new(CniErrorCode::DecodingFailure, "failed to parse network config")
            .with_details(&e.to_string())
    })?;

    // Get environment variables (some may be optional for DEL)
    let container_id = env::var("CNI_CONTAINERID").unwrap_or_default();
    let ifname = env::var("CNI_IFNAME").unwrap_or_default();

    // TODO: Implement actual network teardown
    // 1. Delete veth pair (or it may already be gone with the namespace)
    // 2. Release IP address (via IPAM)

    // DEL must be idempotent - if already deleted, succeed silently
    eprintln!(
        "flatnet DEL: container={}, ifname={}",
        container_id, ifname
    );

    // DEL outputs nothing on success
    Ok(())
}

/// Handle CHECK command - verify network interface exists
fn cmd_check(input: &str) -> Result<(), CniError> {
    let config: NetworkConfig = serde_json::from_str(input).map_err(|e| {
        CniError::new(CniErrorCode::DecodingFailure, "failed to parse network config")
            .with_details(&e.to_string())
    })?;

    // Required environment variables for CHECK per CNI spec
    let container_id = env::var("CNI_CONTAINERID").map_err(|_| {
        CniError::new(
            CniErrorCode::InvalidEnvironmentVariables,
            "CNI_CONTAINERID not set",
        )
    })?;

    let netns = env::var("CNI_NETNS").map_err(|_| {
        CniError::new(
            CniErrorCode::InvalidEnvironmentVariables,
            "CNI_NETNS not set",
        )
    })?;

    let ifname = env::var("CNI_IFNAME").map_err(|_| {
        CniError::new(
            CniErrorCode::InvalidEnvironmentVariables,
            "CNI_IFNAME not set",
        )
    })?;

    // CHECK requires prevResult in the config for chained plugins
    // For Stage 2, we just validate that we got the right input
    if config.prev_result.is_none() {
        eprintln!(
            "flatnet CHECK: warning - no prevResult in config (container={}, ifname={})",
            container_id, ifname
        );
    }

    // TODO: Implement actual network verification in Stage 3
    // 1. Check interface exists in container namespace
    // 2. Verify IP configuration matches prevResult

    eprintln!(
        "flatnet CHECK: container={}, netns={}, ifname={}",
        container_id, netns, ifname
    );

    // CHECK outputs nothing on success
    Ok(())
}

/// Handle VERSION command - report supported CNI versions
fn cmd_version(_input: &str) -> Result<(), CniError> {
    let result = VersionResult {
        cni_version: CNI_VERSION.to_string(),
        supported_versions: SUPPORTED_VERSIONS.iter().map(|s| s.to_string()).collect(),
    };

    println!(
        "{}",
        serde_json::to_string(&result).map_err(|e| {
            CniError::new(CniErrorCode::IoFailure, "failed to serialize version")
                .with_details(&e.to_string())
        })?
    );

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_stub_ip() {
        // Normal case
        assert_eq!(generate_stub_ip("10.87.1.0/24"), "10.87.1.2/24");
        assert_eq!(generate_stub_ip("192.168.0.0/16"), "192.168.0.2/16");
        assert_eq!(generate_stub_ip("172.16.0.0/12"), "172.16.0.2/12");

        // Edge cases - should return default
        assert_eq!(generate_stub_ip("invalid"), "10.87.1.2/24");
        assert_eq!(generate_stub_ip("10.0.0.0"), "10.87.1.2/24"); // No prefix
        assert_eq!(generate_stub_ip("10.0.0/24"), "10.87.1.2/24"); // Missing octet
    }

    #[test]
    fn test_generate_stub_mac() {
        // Normal container ID (hex characters)
        let mac = generate_stub_mac("abc123def456");
        assert!(mac.starts_with("02:"));
        assert_eq!(mac, "02:ab:c1:23:de:f4");

        // Short container ID (should be padded)
        let mac = generate_stub_mac("abc");
        assert_eq!(mac, "02:ab:c0:00:00:00");

        // Container ID with non-hex chars
        let mac = generate_stub_mac("container-xyz-123");
        // Only extracts hex chars: c, a, e (from "container"), 1, 2, 3 (from "123")
        // Result: "02:ca:e1:23:00:00"
        assert_eq!(mac, "02:ca:e1:23:00:00");
    }

    #[test]
    fn test_generate_stub_mac_format() {
        // Verify MAC format is valid (locally administered unicast)
        let mac = generate_stub_mac("0123456789abcdef");
        let parts: Vec<&str> = mac.split(':').collect();
        assert_eq!(parts.len(), 6);

        // First byte should be 02 (locally administered, unicast)
        assert_eq!(parts[0], "02");

        // All parts should be 2 hex chars
        for part in &parts {
            assert_eq!(part.len(), 2);
            assert!(part.chars().all(|c| c.is_ascii_hexdigit()));
        }
    }

    #[test]
    fn test_supported_versions() {
        assert!(SUPPORTED_VERSIONS.contains(&"1.0.0"));
        assert!(SUPPORTED_VERSIONS.contains(&"0.4.0"));
        assert!(SUPPORTED_VERSIONS.contains(&"0.3.1"));
        assert!(SUPPORTED_VERSIONS.contains(&"0.3.0"));
    }

    #[test]
    fn test_cni_version_constant() {
        assert_eq!(CNI_VERSION, "1.0.0");
    }
}
