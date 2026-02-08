//! Flatnet CNI Plugin
//!
//! A CNI plugin that bridges containers across NAT boundaries.
//! Implements CNI Spec 1.0.0.
//! Supports multihost deployments with Gateway-based container discovery.

mod bridge;
mod config;
mod error;
mod ipam;
mod netns;
mod registry;
mod result;
mod veth;

use std::env;
use std::io::{self, Read};
use std::net::Ipv4Addr;

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
        // Output error in CNI format to stdout (per CNI spec)
        let error_output = serde_json::json!({
            "cniVersion": CNI_VERSION,
            "code": e.code() as u32,
            "msg": e.message(),
            "details": e.details()
        });
        // Use compact JSON for CNI spec compliance; unwrap_or for robustness
        println!(
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

    // Get multihost configuration
    let host_id = config.host_id.or_else(|| {
        config.ipam.as_ref().and_then(|ipam| ipam.host_id)
    });

    let is_multihost = host_id.is_some();

    eprintln!(
        "flatnet ADD: container={}, netns={}, ifname={}, multihost={}, host_id={:?}",
        container_id, netns, ifname, is_multihost, host_id
    );

    // Get configuration values
    let bridge_name = config.bridge_name();
    let mtu = config.mtu_value();

    // Determine gateway IP based on mode
    let gateway_ip: Ipv4Addr = if is_multihost {
        // Multihost mode: gateway is 10.100.<host-id>.1
        let hid = host_id.unwrap_or(1);
        format!("10.100.{}.1", hid)
            .parse()
            .expect("multihost gateway IP is invalid")
    } else if let Some(ref ipam_config) = config.ipam {
        ipam_config
            .gateway
            .as_deref()
            .unwrap_or(bridge::DEFAULT_GATEWAY)
            .parse()
            .map_err(|e: std::net::AddrParseError| {
                CniError::new(CniErrorCode::InvalidNetworkConfig, "invalid gateway IP")
                    .with_details(&e.to_string())
            })?
    } else {
        bridge::DEFAULT_GATEWAY
            .parse()
            .expect("DEFAULT_GATEWAY constant is invalid")
    };

    // Step 1: Ensure bridge exists
    let _bridge_index = bridge::ensure_bridge(bridge_name, gateway_ip, bridge::DEFAULT_PREFIX_LEN)?;

    // Step 2: Allocate IP address (with host ID for multihost)
    let allocation = ipam::allocate_with_host_id(&container_id, host_id)?;

    // Step 3: Create veth pair
    let veth_pair = veth::create_veth_pair(&container_id, &netns, &ifname, mtu)?;

    // Step 4: Attach host veth to bridge
    veth::setup_host_veth(veth_pair.host_index, bridge_name)?;

    // Step 5: Configure container interface (in container namespace)
    netns::with_netns(&netns, || {
        veth::configure_container_interface(
            &ifname,
            allocation.ip,
            allocation.prefix_len,
            allocation.gateway,
        )
    })?;

    // Step 6: Register container with Gateway (if registry enabled)
    if config.is_registry_enabled() {
        let container_info = registry::ContainerInfo::new(
            container_id.clone(),
            allocation.ip.to_string(),
            allocation.host_id,
        );
        registry::try_register(config.registry_endpoints(), &container_info);
    }

    // Build the result
    let ip_with_prefix = format!("{}/{}", allocation.ip, allocation.prefix_len);
    let gateway_str = allocation.gateway.to_string();

    // Build result with two interfaces:
    // 0: host-side veth (attached to bridge)
    // 1: container-side veth (inside container namespace)
    let result = CniResult::new(config.cni_version.clone())
        .with_interface(veth_pair.host_ifname.clone(), String::new(), None)
        .with_interface(ifname.clone(), veth_pair.mac_address, Some(netns.clone()))
        .with_ip(ip_with_prefix.clone(), Some(gateway_str.clone()), 1) // interface index 1 = container side
        .with_route("0.0.0.0/0".to_string(), Some(gateway_str.clone()));

    eprintln!(
        "flatnet ADD: success, ip={}, gateway={}, host_id={}",
        ip_with_prefix, gateway_str, allocation.host_id
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

/// Handle DEL command - remove network interface
fn cmd_del(input: &str) -> Result<(), CniError> {
    let config: NetworkConfig = serde_json::from_str(input).map_err(|e| {
        CniError::new(CniErrorCode::DecodingFailure, "failed to parse network config")
            .with_details(&e.to_string())
    })?;

    // Get environment variables (some may be optional for DEL)
    let container_id = env::var("CNI_CONTAINERID").unwrap_or_default();
    let ifname = env::var("CNI_IFNAME").unwrap_or_default();

    eprintln!(
        "flatnet DEL: container={}, ifname={}",
        container_id, ifname
    );

    if container_id.is_empty() {
        // Nothing to do without container ID
        eprintln!("flatnet DEL: no container ID, nothing to clean up");
        return Ok(());
    }

    // Step 1: Deregister container from Gateway (if registry enabled)
    // Do this first while we still have network access
    if config.is_registry_enabled() {
        registry::try_deregister(config.registry_endpoints(), &container_id);
    }

    // Step 2: Delete veth pair (if exists)
    // Deleting the host side automatically deletes the container side
    let host_ifname = veth::generate_host_ifname(&container_id);
    veth::delete_veth(&host_ifname)?;

    // Step 3: Release IP address
    ipam::release(&container_id)?;

    eprintln!("flatnet DEL: cleanup complete");

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

    eprintln!(
        "flatnet CHECK: container={}, netns={}, ifname={}",
        container_id, netns, ifname
    );

    let bridge_name = config.bridge_name();

    // Check 1: Bridge exists
    let _bridge_index = bridge::get_bridge_index(bridge_name).map_err(|_| {
        CniError::new(
            CniErrorCode::IoFailure,
            &format!("bridge {} does not exist", bridge_name),
        )
    })?;

    // Check 2: Host-side veth exists
    let host_ifname = veth::generate_host_ifname(&container_id);
    if !veth::veth_exists(&host_ifname)? {
        return Err(CniError::new(
            CniErrorCode::IoFailure,
            &format!("host veth {} does not exist", host_ifname),
        ));
    }

    // Check 3: IPAM allocation exists
    if !ipam::has_allocation(&container_id)? {
        return Err(CniError::new(
            CniErrorCode::IpamFailure,
            &format!("no IP allocation for container {}", container_id),
        ));
    }

    // Check 4: Verify prevResult if present
    if let Some(ref prev_result) = config.prev_result {
        eprintln!(
            "flatnet CHECK: prevResult present, verifying..."
        );
        // In a full implementation, we would verify the prevResult matches actual state
        // For now, just log that we have it
        let _ = prev_result;
    }

    eprintln!("flatnet CHECK: all checks passed");

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
