//! IP Address Management (IPAM)
//!
//! Simple file-based IPAM for allocating and tracking IP addresses.
//! Supports multihost configuration with host-ID based IP ranges.
//!
//! IP allocation scheme for multihost:
//!   10.100.<host-id>.<container-id>
//!   - host-id: 1-254 (unique per host)
//!   - container-id: 10-254 (first 10 reserved for infrastructure)

use std::collections::HashMap;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::net::Ipv4Addr;
use std::path::Path;

use fs2::FileExt;
use serde::{Deserialize, Serialize};

use crate::error::{CniError, CniErrorCode};

/// Default IPAM data directory
pub const IPAM_DIR: &str = "/var/lib/flatnet/ipam";

/// IPAM allocations file
pub const ALLOCATIONS_FILE: &str = "allocations.json";

/// Lock file for concurrent access
pub const LOCK_FILE: &str = ".lock";

/// Default host ID (for single-host deployments)
pub const DEFAULT_HOST_ID: u8 = 1;

/// Multihost subnet base (10.100.0.0/16)
pub const MULTIHOST_SUBNET_BASE: &str = "10.100";

/// Default subnet configuration (legacy single-host)
pub const DEFAULT_SUBNET: &str = "10.87.1.0/24";
pub const DEFAULT_RANGE_START: &str = "10.87.1.2";
pub const DEFAULT_RANGE_END: &str = "10.87.1.254";

/// Container ID start for multihost (first 10 reserved for infrastructure)
pub const MULTIHOST_CONTAINER_START: u8 = 10;
/// Container ID end for multihost
pub const MULTIHOST_CONTAINER_END: u8 = 254;

/// IPAM state stored in file
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IpamState {
    /// Subnet in CIDR notation
    pub subnet: String,

    /// Gateway IP (first usable IP)
    pub gateway: String,

    /// Start of allocation range
    pub range_start: String,

    /// End of allocation range
    pub range_end: String,

    /// Host ID for multihost deployments
    #[serde(default = "default_host_id")]
    pub host_id: u8,

    /// Multihost mode enabled
    #[serde(default)]
    pub multihost: bool,

    /// Map of container ID to allocated IP
    pub allocations: HashMap<String, String>,
}

fn default_host_id() -> u8 {
    DEFAULT_HOST_ID
}

impl Default for IpamState {
    fn default() -> Self {
        Self {
            subnet: DEFAULT_SUBNET.to_string(),
            gateway: crate::bridge::DEFAULT_GATEWAY.to_string(),
            range_start: DEFAULT_RANGE_START.to_string(),
            range_end: DEFAULT_RANGE_END.to_string(),
            host_id: DEFAULT_HOST_ID,
            multihost: false,
            allocations: HashMap::new(),
        }
    }
}

impl IpamState {
    /// Create a new multihost IPAM state for the given host ID
    pub fn new_multihost(host_id: u8) -> Self {
        let subnet = format!("{}.{}.0/24", MULTIHOST_SUBNET_BASE, host_id);
        let gateway = format!("{}.{}.1", MULTIHOST_SUBNET_BASE, host_id);
        let range_start = format!("{}.{}.{}", MULTIHOST_SUBNET_BASE, host_id, MULTIHOST_CONTAINER_START);
        let range_end = format!("{}.{}.{}", MULTIHOST_SUBNET_BASE, host_id, MULTIHOST_CONTAINER_END);

        Self {
            subnet,
            gateway,
            range_start,
            range_end,
            host_id,
            multihost: true,
            allocations: HashMap::new(),
        }
    }

    /// Check if this state uses multihost IP scheme
    pub fn is_multihost(&self) -> bool {
        self.multihost
    }
}

/// Result of IP allocation
pub struct IpAllocation {
    /// Allocated IP address
    pub ip: Ipv4Addr,

    /// Subnet prefix length
    pub prefix_len: u8,

    /// Gateway IP
    pub gateway: Ipv4Addr,

    /// Host ID (for multihost deployments)
    pub host_id: u8,
}

/// Ensure IPAM directory and files exist
pub fn ensure_ipam_dir() -> Result<(), CniError> {
    let dir = Path::new(IPAM_DIR);

    if !dir.exists() {
        fs::create_dir_all(dir).map_err(|e| {
            CniError::new(CniErrorCode::IpamFailure, "failed to create IPAM directory")
                .with_details(&e.to_string())
        })?;
    }

    let allocations_path = dir.join(ALLOCATIONS_FILE);
    if !allocations_path.exists() {
        let state = IpamState::default();
        let json = serde_json::to_string_pretty(&state).map_err(|e| {
            CniError::new(CniErrorCode::IpamFailure, "failed to serialize IPAM state")
                .with_details(&e.to_string())
        })?;

        fs::write(&allocations_path, json).map_err(|e| {
            CniError::new(CniErrorCode::IpamFailure, "failed to write IPAM allocations file")
                .with_details(&e.to_string())
        })?;
    }

    Ok(())
}

/// Execute a function while holding the IPAM lock
fn with_ipam_lock<T, F>(f: F) -> Result<T, CniError>
where
    F: FnOnce() -> Result<T, CniError>,
{
    ensure_ipam_dir()?;

    let lock_path = Path::new(IPAM_DIR).join(LOCK_FILE);
    let lock_file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(false)
        .open(&lock_path)
        .map_err(|e| {
            CniError::new(CniErrorCode::IpamFailure, "failed to open IPAM lock file")
                .with_details(&e.to_string())
        })?;

    lock_file.lock_exclusive().map_err(|e| {
        CniError::new(CniErrorCode::IpamFailure, "failed to acquire IPAM lock")
            .with_details(&e.to_string())
    })?;

    let result = f();

    lock_file.unlock().map_err(|e| {
        CniError::new(CniErrorCode::IpamFailure, "failed to release IPAM lock")
            .with_details(&e.to_string())
    })?;

    result
}

/// Load IPAM state from file
fn load_state() -> Result<IpamState, CniError> {
    let path = Path::new(IPAM_DIR).join(ALLOCATIONS_FILE);

    let mut file = File::open(&path).map_err(|e| {
        CniError::new(CniErrorCode::IpamFailure, "failed to open IPAM allocations file")
            .with_details(&e.to_string())
    })?;

    let mut contents = String::new();
    file.read_to_string(&mut contents).map_err(|e| {
        CniError::new(CniErrorCode::IpamFailure, "failed to read IPAM allocations file")
            .with_details(&e.to_string())
    })?;

    serde_json::from_str(&contents).map_err(|e| {
        CniError::new(CniErrorCode::IpamFailure, "failed to parse IPAM allocations file")
            .with_details(&e.to_string())
    })
}

/// Save IPAM state to file (atomic write using rename)
fn save_state(state: &IpamState) -> Result<(), CniError> {
    let path = Path::new(IPAM_DIR).join(ALLOCATIONS_FILE);
    let tmp_path = Path::new(IPAM_DIR).join(".allocations.json.tmp");

    let json = serde_json::to_string_pretty(state).map_err(|e| {
        CniError::new(CniErrorCode::IpamFailure, "failed to serialize IPAM state")
            .with_details(&e.to_string())
    })?;

    // Write to temporary file first
    let mut file = File::create(&tmp_path).map_err(|e| {
        CniError::new(CniErrorCode::IpamFailure, "failed to create IPAM temp file")
            .with_details(&e.to_string())
    })?;

    file.write_all(json.as_bytes()).map_err(|e| {
        CniError::new(CniErrorCode::IpamFailure, "failed to write IPAM temp file")
            .with_details(&e.to_string())
    })?;

    // Ensure data is flushed to disk
    file.sync_all().map_err(|e| {
        CniError::new(CniErrorCode::IpamFailure, "failed to sync IPAM temp file")
            .with_details(&e.to_string())
    })?;

    // Atomic rename
    fs::rename(&tmp_path, &path).map_err(|e| {
        CniError::new(CniErrorCode::IpamFailure, "failed to rename IPAM allocations file")
            .with_details(&e.to_string())
    })?;

    Ok(())
}

/// Parse an IP address
fn parse_ip(s: &str) -> Result<Ipv4Addr, CniError> {
    s.parse().map_err(|e: std::net::AddrParseError| {
        CniError::new(CniErrorCode::IpamFailure, &format!("invalid IP address: {}", s))
            .with_details(&e.to_string())
    })
}

/// Get prefix length from subnet CIDR notation
fn parse_prefix_len(subnet: &str) -> Result<u8, CniError> {
    let parts: Vec<&str> = subnet.split('/').collect();
    if parts.len() != 2 {
        return Err(CniError::new(
            CniErrorCode::IpamFailure,
            &format!("invalid subnet format: {}", subnet),
        ));
    }

    parts[1].parse().map_err(|e: std::num::ParseIntError| {
        CniError::new(
            CniErrorCode::IpamFailure,
            &format!("invalid prefix length in subnet: {}", subnet),
        )
        .with_details(&e.to_string())
    })
}

/// Allocate an IP address for a container (legacy single-host mode)
pub fn allocate(container_id: &str) -> Result<IpAllocation, CniError> {
    allocate_with_host_id(container_id, None)
}

/// Allocate an IP address for a container with optional host ID
///
/// If host_id is provided, uses multihost IP scheme: 10.100.<host-id>.<container-id>
/// Otherwise, uses legacy single-host scheme.
pub fn allocate_with_host_id(container_id: &str, host_id: Option<u8>) -> Result<IpAllocation, CniError> {
    with_ipam_lock(|| {
        let mut state = load_or_init_state(host_id)?;

        // Check if container already has an allocation
        if let Some(ip_str) = state.allocations.get(container_id) {
            let ip = parse_ip(ip_str)?;
            let prefix_len = parse_prefix_len(&state.subnet)?;
            let gateway = parse_ip(&state.gateway)?;

            eprintln!(
                "flatnet IPAM: container {} already has IP {}",
                container_id, ip
            );

            return Ok(IpAllocation {
                ip,
                prefix_len,
                gateway,
                host_id: state.host_id,
            });
        }

        // Parse range
        let range_start = parse_ip(&state.range_start)?;
        let range_end = parse_ip(&state.range_end)?;
        let prefix_len = parse_prefix_len(&state.subnet)?;
        let gateway = parse_ip(&state.gateway)?;

        // Collect used IPs
        let used_ips: std::collections::HashSet<Ipv4Addr> = state
            .allocations
            .values()
            .filter_map(|ip_str| ip_str.parse().ok())
            .collect();

        // Find first available IP in range
        let start: u32 = range_start.into();
        let end: u32 = range_end.into();

        for ip_int in start..=end {
            let ip = Ipv4Addr::from(ip_int);
            if !used_ips.contains(&ip) {
                // Found an available IP
                state
                    .allocations
                    .insert(container_id.to_string(), ip.to_string());
                save_state(&state)?;

                let mode = if state.multihost { "multihost" } else { "single-host" };
                eprintln!(
                    "flatnet IPAM ({}): allocated {} to container {} (host_id={})",
                    mode, ip, container_id, state.host_id
                );

                return Ok(IpAllocation {
                    ip,
                    prefix_len,
                    gateway,
                    host_id: state.host_id,
                });
            }
        }

        Err(CniError::new(
            CniErrorCode::IpamFailure,
            "no available IP addresses in range",
        ))
    })
}

/// Load existing state or initialize for the given host ID
fn load_or_init_state(host_id: Option<u8>) -> Result<IpamState, CniError> {
    let path = Path::new(IPAM_DIR).join(ALLOCATIONS_FILE);

    if path.exists() {
        let state = load_state()?;
        // If host_id is provided and differs from stored state, warn but continue
        if let Some(new_id) = host_id {
            if state.host_id != new_id && !state.allocations.is_empty() {
                eprintln!(
                    "flatnet IPAM: WARNING - host_id changed from {} to {}, existing allocations preserved",
                    state.host_id, new_id
                );
            }
        }
        Ok(state)
    } else {
        // Initialize new state
        let state = match host_id {
            Some(id) => IpamState::new_multihost(id),
            None => IpamState::default(),
        };
        save_state(&state)?;
        eprintln!(
            "flatnet IPAM: initialized {} mode (host_id={}, subnet={})",
            if state.multihost { "multihost" } else { "single-host" },
            state.host_id,
            state.subnet
        );
        Ok(state)
    }
}

/// Release an IP address for a container
pub fn release(container_id: &str) -> Result<(), CniError> {
    with_ipam_lock(|| {
        let mut state = load_state()?;

        if let Some(ip) = state.allocations.remove(container_id) {
            save_state(&state)?;
            eprintln!(
                "flatnet IPAM: released {} from container {}",
                ip, container_id
            );
        } else {
            eprintln!(
                "flatnet IPAM: container {} had no allocation (idempotent)",
                container_id
            );
        }

        Ok(())
    })
}

/// Get the current allocation for a container
pub fn get_allocation(container_id: &str) -> Result<Option<IpAllocation>, CniError> {
    with_ipam_lock(|| {
        let state = load_state()?;

        match state.allocations.get(container_id) {
            Some(ip_str) => {
                let ip = parse_ip(ip_str)?;
                let prefix_len = parse_prefix_len(&state.subnet)?;
                let gateway = parse_ip(&state.gateway)?;

                Ok(Some(IpAllocation {
                    ip,
                    prefix_len,
                    gateway,
                    host_id: state.host_id,
                }))
            }
            None => Ok(None),
        }
    })
}

/// Get all current allocations
pub fn get_all_allocations() -> Result<Vec<(String, IpAllocation)>, CniError> {
    with_ipam_lock(|| {
        let state = load_state()?;
        let prefix_len = parse_prefix_len(&state.subnet)?;
        let gateway = parse_ip(&state.gateway)?;

        let mut allocations = Vec::new();
        for (container_id, ip_str) in &state.allocations {
            let ip = parse_ip(ip_str)?;
            allocations.push((
                container_id.clone(),
                IpAllocation {
                    ip,
                    prefix_len,
                    gateway,
                    host_id: state.host_id,
                },
            ));
        }
        Ok(allocations)
    })
}

/// Get current host ID from IPAM state
pub fn get_host_id() -> Result<u8, CniError> {
    with_ipam_lock(|| {
        let state = load_state()?;
        Ok(state.host_id)
    })
}

/// Check if a container has an IP allocation
pub fn has_allocation(container_id: &str) -> Result<bool, CniError> {
    with_ipam_lock(|| {
        let state = load_state()?;
        Ok(state.allocations.contains_key(container_id))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_state() {
        let state = IpamState::default();
        assert_eq!(state.subnet, DEFAULT_SUBNET);
        assert_eq!(state.range_start, DEFAULT_RANGE_START);
        assert_eq!(state.range_end, DEFAULT_RANGE_END);
        assert_eq!(state.host_id, DEFAULT_HOST_ID);
        assert!(!state.multihost);
        assert!(state.allocations.is_empty());
    }

    #[test]
    fn test_multihost_state() {
        let state = IpamState::new_multihost(5);
        assert_eq!(state.subnet, "10.100.5.0/24");
        assert_eq!(state.gateway, "10.100.5.1");
        assert_eq!(state.range_start, "10.100.5.10");
        assert_eq!(state.range_end, "10.100.5.254");
        assert_eq!(state.host_id, 5);
        assert!(state.multihost);
        assert!(state.allocations.is_empty());
    }

    #[test]
    fn test_multihost_state_host_boundaries() {
        // Test host ID 1 (minimum)
        let state1 = IpamState::new_multihost(1);
        assert_eq!(state1.subnet, "10.100.1.0/24");
        assert_eq!(state1.gateway, "10.100.1.1");

        // Test host ID 254 (maximum)
        let state254 = IpamState::new_multihost(254);
        assert_eq!(state254.subnet, "10.100.254.0/24");
        assert_eq!(state254.gateway, "10.100.254.1");
    }

    #[test]
    fn test_parse_ip() {
        assert!(parse_ip("10.87.1.2").is_ok());
        assert!(parse_ip("10.100.1.10").is_ok());
        assert!(parse_ip("invalid").is_err());
    }

    #[test]
    fn test_parse_prefix_len() {
        assert_eq!(parse_prefix_len("10.87.1.0/24").unwrap(), 24);
        assert_eq!(parse_prefix_len("10.0.0.0/8").unwrap(), 8);
        assert_eq!(parse_prefix_len("10.100.1.0/24").unwrap(), 24);
        assert!(parse_prefix_len("invalid").is_err());
    }
}
