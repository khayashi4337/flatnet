//! Veth pair management
//!
//! Handles creation, configuration, and deletion of veth pairs.

use std::fs::File;
use std::net::Ipv4Addr;
use std::os::unix::io::AsRawFd;

use futures::TryStreamExt;
use rtnetlink::{new_connection, Handle};
use tokio::runtime::Runtime;

use crate::bridge;
use crate::error::{CniError, CniErrorCode};

/// Maximum length for interface names (Linux limit is 15 + null terminator)
const MAX_IFNAME_LEN: usize = 15;

/// Prefix for host-side veth names
const HOST_VETH_PREFIX: &str = "fn-";

/// Result of veth pair creation
pub struct VethPair {
    /// Host-side interface name
    pub host_ifname: String,
    /// Host-side interface index
    pub host_index: u32,
    /// Container-side interface name
    pub container_ifname: String,
    /// MAC address of container interface
    pub mac_address: String,
}

/// Create a veth pair and move one end to the container namespace
///
/// # Arguments
/// * `container_id` - Container ID (used to generate host veth name)
/// * `netns_path` - Path to the container network namespace
/// * `container_ifname` - Interface name inside the container (usually "eth0")
/// * `mtu` - MTU for the interfaces
///
/// # Returns
/// Information about the created veth pair
pub fn create_veth_pair(
    container_id: &str,
    netns_path: &str,
    container_ifname: &str,
    mtu: u32,
) -> Result<VethPair, CniError> {
    let rt = Runtime::new().map_err(|e| {
        CniError::new(CniErrorCode::IoFailure, "failed to create tokio runtime")
            .with_details(&e.to_string())
    })?;

    rt.block_on(async {
        create_veth_pair_async(container_id, netns_path, container_ifname, mtu).await
    })
}

async fn create_veth_pair_async(
    container_id: &str,
    netns_path: &str,
    container_ifname: &str,
    mtu: u32,
) -> Result<VethPair, CniError> {
    let (connection, handle, _) = new_connection().map_err(|e| {
        CniError::new(CniErrorCode::IoFailure, "failed to create netlink connection")
            .with_details(&e.to_string())
    })?;

    tokio::spawn(connection);

    // Generate host-side interface name: fn-<first 8 chars of container id>
    let host_ifname = generate_host_ifname(container_id);

    eprintln!(
        "flatnet: creating veth pair {} <-> {}",
        host_ifname, container_ifname
    );

    // Check if host veth already exists (idempotent ADD)
    if let Some(existing_index) = get_link_index(&handle, &host_ifname).await? {
        eprintln!(
            "flatnet: veth {} already exists (index {}), reusing",
            host_ifname, existing_index
        );
        let mac_address = generate_mac_address(container_id);
        return Ok(VethPair {
            host_ifname,
            host_index: existing_index,
            container_ifname: container_ifname.to_string(),
            mac_address,
        });
    }

    // Create veth pair (ignore EEXIST for race condition handling)
    match handle
        .link()
        .add()
        .veth(host_ifname.clone(), container_ifname.to_string())
        .execute()
        .await
    {
        Ok(()) => {}
        Err(rtnetlink::Error::NetlinkError(e)) if e.raw_code() == -libc::EEXIST => {
            eprintln!(
                "flatnet: veth {} created by another process, reusing",
                host_ifname
            );
        }
        Err(e) => {
            return Err(
                CniError::new(CniErrorCode::VethCreationFailed, "failed to create veth pair")
                    .with_details(&e.to_string()),
            );
        }
    }

    // Get host veth index
    let host_index = get_link_index(&handle, &host_ifname).await?.ok_or_else(|| {
        CniError::new(
            CniErrorCode::VethCreationFailed,
            "veth was created but host side not found",
        )
    })?;

    // Get container veth index (still in host namespace)
    let container_index =
        get_link_index(&handle, container_ifname)
            .await?
            .ok_or_else(|| {
                CniError::new(
                    CniErrorCode::VethCreationFailed,
                    "veth was created but container side not found",
                )
            })?;

    // Set MTU on both interfaces
    set_mtu(&handle, host_index, mtu).await?;
    set_mtu(&handle, container_index, mtu).await?;

    // Open the target namespace
    let netns_file = File::open(netns_path).map_err(|e| {
        CniError::new(
            CniErrorCode::NamespaceFailure,
            &format!("failed to open network namespace: {}", netns_path),
        )
        .with_details(&e.to_string())
    })?;

    // Move container-side veth to container namespace
    handle
        .link()
        .set(container_index)
        .setns_by_fd(netns_file.as_raw_fd())
        .execute()
        .await
        .map_err(|e| {
            CniError::new(
                CniErrorCode::VethCreationFailed,
                "failed to move veth to container namespace",
            )
            .with_details(&e.to_string())
        })?;

    // Bring host veth up
    handle
        .link()
        .set(host_index)
        .up()
        .execute()
        .await
        .map_err(|e| {
            CniError::new(CniErrorCode::VethCreationFailed, "failed to bring host veth up")
                .with_details(&e.to_string())
        })?;

    // Generate MAC address for container interface
    let mac_address = generate_mac_address(container_id);

    eprintln!(
        "flatnet: veth pair created, host {} (index {})",
        host_ifname, host_index
    );

    Ok(VethPair {
        host_ifname,
        host_index,
        container_ifname: container_ifname.to_string(),
        mac_address,
    })
}

/// Configure the container-side network interface
///
/// This must be called from within the container's network namespace.
///
/// # Arguments
/// * `ifname` - Interface name (e.g., "eth0")
/// * `ip` - IP address to assign
/// * `prefix_len` - Subnet prefix length
/// * `gateway` - Gateway IP address
pub fn configure_container_interface(
    ifname: &str,
    ip: Ipv4Addr,
    prefix_len: u8,
    gateway: Ipv4Addr,
) -> Result<(), CniError> {
    let rt = Runtime::new().map_err(|e| {
        CniError::new(CniErrorCode::IoFailure, "failed to create tokio runtime")
            .with_details(&e.to_string())
    })?;

    rt.block_on(async {
        configure_container_interface_async(ifname, ip, prefix_len, gateway).await
    })
}

async fn configure_container_interface_async(
    ifname: &str,
    ip: Ipv4Addr,
    prefix_len: u8,
    gateway: Ipv4Addr,
) -> Result<(), CniError> {
    let (connection, handle, _) = new_connection().map_err(|e| {
        CniError::new(CniErrorCode::IoFailure, "failed to create netlink connection")
            .with_details(&e.to_string())
    })?;

    tokio::spawn(connection);

    // Get interface index
    let index = get_link_index(&handle, ifname).await?.ok_or_else(|| {
        CniError::new(
            CniErrorCode::VethCreationFailed,
            &format!("interface {} not found in container", ifname),
        )
    })?;

    // Bring loopback up (best-effort, log warning on failure)
    if let Some(lo_index) = get_link_index(&handle, "lo").await? {
        if let Err(e) = handle.link().set(lo_index).up().execute().await {
            eprintln!("flatnet: warning: failed to bring loopback up: {}", e);
        }
    }

    // Add IP address (ignore EEXIST for idempotency)
    match handle
        .address()
        .add(index, std::net::IpAddr::V4(ip), prefix_len)
        .execute()
        .await
    {
        Ok(()) => {}
        Err(rtnetlink::Error::NetlinkError(e)) if e.raw_code() == -libc::EEXIST => {
            eprintln!(
                "flatnet: IP address {}/{} already exists on interface",
                ip, prefix_len
            );
        }
        Err(e) => {
            return Err(CniError::new(
                CniErrorCode::IpamFailure,
                &format!("failed to add IP address {}/{}", ip, prefix_len),
            )
            .with_details(&e.to_string()));
        }
    }

    // Bring interface up
    handle.link().set(index).up().execute().await.map_err(|e| {
        CniError::new(CniErrorCode::VethCreationFailed, "failed to bring interface up")
            .with_details(&e.to_string())
    })?;

    // Add default route via gateway (ignore EEXIST for idempotency)
    match handle
        .route()
        .add()
        .v4()
        .destination_prefix(Ipv4Addr::new(0, 0, 0, 0), 0)
        .gateway(gateway)
        .execute()
        .await
    {
        Ok(()) => {}
        Err(rtnetlink::Error::NetlinkError(e)) if e.raw_code() == -libc::EEXIST => {
            eprintln!("flatnet: default route already exists");
        }
        Err(e) => {
            return Err(CniError::new(
                CniErrorCode::RouteFailure,
                &format!("failed to add default route via {}", gateway),
            )
            .with_details(&e.to_string()));
        }
    }

    eprintln!(
        "flatnet: container interface {} configured with {}/{}",
        ifname, ip, prefix_len
    );

    Ok(())
}

/// Delete a veth pair by its host-side interface name
///
/// The container-side interface is automatically deleted when the host side is deleted.
pub fn delete_veth(host_ifname: &str) -> Result<(), CniError> {
    let rt = Runtime::new().map_err(|e| {
        CniError::new(CniErrorCode::IoFailure, "failed to create tokio runtime")
            .with_details(&e.to_string())
    })?;

    rt.block_on(async {
        let (connection, handle, _) = new_connection().map_err(|e| {
            CniError::new(CniErrorCode::IoFailure, "failed to create netlink connection")
                .with_details(&e.to_string())
        })?;

        tokio::spawn(connection);

        // Get interface index - if it doesn't exist, that's fine (idempotent)
        match get_link_index(&handle, host_ifname).await? {
            Some(index) => {
                handle.link().del(index).execute().await.map_err(|e| {
                    CniError::new(CniErrorCode::VethCreationFailed, "failed to delete veth")
                        .with_details(&e.to_string())
                })?;
                eprintln!("flatnet: deleted veth {}", host_ifname);
            }
            None => {
                eprintln!("flatnet: veth {} already deleted or never existed", host_ifname);
            }
        }

        Ok(())
    })
}

/// Check if a veth interface exists
pub fn veth_exists(host_ifname: &str) -> Result<bool, CniError> {
    let rt = Runtime::new().map_err(|e| {
        CniError::new(CniErrorCode::IoFailure, "failed to create tokio runtime")
            .with_details(&e.to_string())
    })?;

    rt.block_on(async {
        let (connection, handle, _) = new_connection().map_err(|e| {
            CniError::new(CniErrorCode::IoFailure, "failed to create netlink connection")
                .with_details(&e.to_string())
        })?;

        tokio::spawn(connection);

        Ok(get_link_index(&handle, host_ifname).await?.is_some())
    })
}

/// Generate the host-side veth interface name from container ID
pub fn generate_host_ifname(container_id: &str) -> String {
    let id_part: String = container_id
        .chars()
        .filter(|c| c.is_ascii_hexdigit())
        .take(MAX_IFNAME_LEN - HOST_VETH_PREFIX.len())
        .collect();

    format!("{}{}", HOST_VETH_PREFIX, id_part)
}

/// Generate a MAC address based on container ID
fn generate_mac_address(container_id: &str) -> String {
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

async fn get_link_index(handle: &Handle, name: &str) -> Result<Option<u32>, CniError> {
    let mut links = handle.link().get().match_name(name.to_string()).execute();

    match links.try_next().await {
        Ok(Some(link)) => Ok(Some(link.header.index)),
        Ok(None) => Ok(None),
        Err(rtnetlink::Error::NetlinkError(e)) if e.raw_code() == -libc::ENODEV => Ok(None),
        Err(e) => Err(CniError::new(
            CniErrorCode::IoFailure,
            &format!("failed to get link {}", name),
        )
        .with_details(&e.to_string())),
    }
}

async fn set_mtu(handle: &Handle, index: u32, mtu: u32) -> Result<(), CniError> {
    handle
        .link()
        .set(index)
        .mtu(mtu)
        .execute()
        .await
        .map_err(|e| {
            CniError::new(CniErrorCode::VethCreationFailed, "failed to set MTU")
                .with_details(&e.to_string())
        })
}

/// Attach host veth to bridge and bring up
pub fn setup_host_veth(host_index: u32, bridge_name: &str) -> Result<(), CniError> {
    // Get bridge index
    let bridge_index = bridge::get_bridge_index(bridge_name)?;

    // Attach to bridge
    bridge::attach_to_bridge(bridge_index, host_index)?;

    eprintln!("flatnet: attached veth (index {}) to bridge {}", host_index, bridge_name);

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_host_ifname() {
        // Normal container ID
        let name = generate_host_ifname("abc123def456");
        assert!(name.starts_with("fn-"));
        assert!(name.len() <= MAX_IFNAME_LEN);
        assert_eq!(name, "fn-abc123def456");

        // Long container ID (should be truncated)
        let name = generate_host_ifname("0123456789abcdef0123456789abcdef");
        assert!(name.len() <= MAX_IFNAME_LEN);
        assert_eq!(name, "fn-0123456789ab");

        // Container ID with non-hex chars
        let name = generate_host_ifname("container-xyz-123");
        // Only hex chars: c, a, e, 1, 2, 3
        assert!(name.starts_with("fn-"));
    }

    #[test]
    fn test_generate_mac_address() {
        let mac = generate_mac_address("abc123def456");
        assert!(mac.starts_with("02:"));
        assert_eq!(mac, "02:ab:c1:23:de:f4");

        // Short container ID
        let mac = generate_mac_address("abc");
        assert_eq!(mac, "02:ab:c0:00:00:00");
    }
}
