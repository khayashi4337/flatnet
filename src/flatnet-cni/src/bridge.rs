//! Bridge management
//!
//! Handles creation and management of the flatnet bridge interface.

use std::net::Ipv4Addr;

use futures::TryStreamExt;
use rtnetlink::{new_connection, Handle};
use tokio::runtime::Runtime;

use crate::error::{CniError, CniErrorCode};

/// Default bridge name
pub const DEFAULT_BRIDGE_NAME: &str = "flatnet-br0";

/// Default gateway IP address
pub const DEFAULT_GATEWAY: &str = "10.87.1.1";

/// Default subnet prefix length
pub const DEFAULT_PREFIX_LEN: u8 = 24;

/// Create the flatnet bridge if it doesn't exist
///
/// # Arguments
/// * `bridge_name` - Name of the bridge to create
/// * `gateway_ip` - IP address to assign to the bridge (gateway)
/// * `prefix_len` - Subnet prefix length (e.g., 24 for /24)
///
/// # Returns
/// The bridge interface index
pub fn ensure_bridge(
    bridge_name: &str,
    gateway_ip: Ipv4Addr,
    prefix_len: u8,
) -> Result<u32, CniError> {
    let rt = Runtime::new().map_err(|e| {
        CniError::new(CniErrorCode::IoFailure, "failed to create tokio runtime")
            .with_details(&e.to_string())
    })?;

    rt.block_on(async { ensure_bridge_async(bridge_name, gateway_ip, prefix_len).await })
}

async fn ensure_bridge_async(
    bridge_name: &str,
    gateway_ip: Ipv4Addr,
    prefix_len: u8,
) -> Result<u32, CniError> {
    let (connection, handle, _) = new_connection().map_err(|e| {
        CniError::new(CniErrorCode::IoFailure, "failed to create netlink connection")
            .with_details(&e.to_string())
    })?;

    tokio::spawn(connection);

    // Check if bridge already exists
    if let Some(index) = get_link_index(&handle, bridge_name).await? {
        eprintln!("flatnet: bridge {} already exists (index {})", bridge_name, index);
        // Ensure IP address is configured (idempotent)
        add_address(&handle, index, gateway_ip, prefix_len).await?;
        // Ensure bridge is UP (idempotent)
        set_link_up(&handle, index).await?;
        return Ok(index);
    }

    // Create the bridge
    eprintln!("flatnet: creating bridge {}", bridge_name);
    create_bridge(&handle, bridge_name).await?;

    // Get the bridge index
    let index = get_link_index(&handle, bridge_name)
        .await?
        .ok_or_else(|| {
            CniError::new(
                CniErrorCode::BridgeCreationFailed,
                "bridge was created but not found",
            )
        })?;

    // Add IP address to bridge
    add_address(&handle, index, gateway_ip, prefix_len).await?;

    // Bring the bridge up
    set_link_up(&handle, index).await?;

    eprintln!(
        "flatnet: bridge {} created with IP {}/{}",
        bridge_name, gateway_ip, prefix_len
    );

    Ok(index)
}

/// Get the index of a network link by name
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

/// Create a bridge interface
async fn create_bridge(handle: &Handle, name: &str) -> Result<(), CniError> {
    handle
        .link()
        .add()
        .bridge(name.to_string())
        .execute()
        .await
        .map_err(|e| {
            CniError::new(
                CniErrorCode::BridgeCreationFailed,
                &format!("failed to create bridge {}", name),
            )
            .with_details(&e.to_string())
        })
}

/// Add an IP address to an interface
async fn add_address(
    handle: &Handle,
    index: u32,
    ip: Ipv4Addr,
    prefix_len: u8,
) -> Result<(), CniError> {
    // Check if address already exists
    let mut addresses = handle.address().get().set_link_index_filter(index).execute();
    while let Some(addr) = addresses.try_next().await.map_err(|e| {
        CniError::new(CniErrorCode::IoFailure, "failed to get addresses")
            .with_details(&e.to_string())
    })? {
        for nla in addr.attributes {
            if let netlink_packet_route::address::AddressAttribute::Address(existing) = nla {
                if existing == std::net::IpAddr::V4(ip) {
                    eprintln!("flatnet: address {}/{} already exists on bridge", ip, prefix_len);
                    return Ok(());
                }
            }
        }
    }

    handle
        .address()
        .add(index, std::net::IpAddr::V4(ip), prefix_len)
        .execute()
        .await
        .map_err(|e| {
            CniError::new(
                CniErrorCode::BridgeCreationFailed,
                &format!("failed to add address {}/{} to bridge", ip, prefix_len),
            )
            .with_details(&e.to_string())
        })
}

/// Bring a network interface up
async fn set_link_up(handle: &Handle, index: u32) -> Result<(), CniError> {
    handle.link().set(index).up().execute().await.map_err(|e| {
        CniError::new(CniErrorCode::BridgeCreationFailed, "failed to bring bridge up")
            .with_details(&e.to_string())
    })
}

/// Get the index of the bridge, returning an error if it doesn't exist
pub fn get_bridge_index(bridge_name: &str) -> Result<u32, CniError> {
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

        get_link_index(&handle, bridge_name).await?.ok_or_else(|| {
            CniError::new(
                CniErrorCode::BridgeCreationFailed,
                &format!("bridge {} does not exist", bridge_name),
            )
        })
    })
}

/// Attach a veth interface to the bridge
pub fn attach_to_bridge(bridge_index: u32, veth_index: u32) -> Result<(), CniError> {
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

        handle
            .link()
            .set(veth_index)
            .controller(bridge_index)
            .execute()
            .await
            .map_err(|e| {
                CniError::new(
                    CniErrorCode::VethCreationFailed,
                    "failed to attach veth to bridge",
                )
                .with_details(&e.to_string())
            })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_values() {
        assert_eq!(DEFAULT_BRIDGE_NAME, "flatnet-br0");
        assert_eq!(DEFAULT_GATEWAY, "10.87.1.1");
        assert_eq!(DEFAULT_PREFIX_LEN, 24);
    }
}
