//! Network Namespace operations
//!
//! Handles entering and exiting container network namespaces.

use std::fs::File;
use std::os::unix::io::{AsRawFd, RawFd};

use nix::sched::{setns, CloneFlags};

use crate::error::{CniError, CniErrorCode};

/// Guard that saves the current network namespace and restores it on drop
pub struct NetnsGuard {
    /// File descriptor of the original network namespace
    original_ns: File,
}

impl NetnsGuard {
    /// Enter a network namespace, saving the current namespace for later restoration
    ///
    /// # Arguments
    /// * `netns_path` - Path to the target network namespace (e.g., "/proc/12345/ns/net")
    ///
    /// # Returns
    /// A guard that will restore the original namespace when dropped
    pub fn enter(netns_path: &str) -> Result<Self, CniError> {
        // Save current namespace
        let original_ns = File::open("/proc/self/ns/net").map_err(|e| {
            CniError::new(
                CniErrorCode::NamespaceFailure,
                "failed to open current network namespace",
            )
            .with_details(&e.to_string())
        })?;

        // Open target namespace
        let target_ns = File::open(netns_path).map_err(|e| {
            CniError::new(
                CniErrorCode::NamespaceFailure,
                &format!("failed to open target network namespace: {}", netns_path),
            )
            .with_details(&e.to_string())
        })?;

        // Enter target namespace
        setns(target_ns.as_raw_fd(), CloneFlags::CLONE_NEWNET).map_err(|e| {
            CniError::new(
                CniErrorCode::NamespaceFailure,
                "failed to enter network namespace",
            )
            .with_details(&e.to_string())
        })?;

        Ok(Self { original_ns })
    }

    /// Get the raw file descriptor of the original namespace
    pub fn original_fd(&self) -> RawFd {
        self.original_ns.as_raw_fd()
    }

    /// Manually restore the original namespace
    ///
    /// This is called automatically on drop, but can be called explicitly
    /// if you need to handle errors.
    pub fn restore(self) -> Result<(), CniError> {
        setns(self.original_ns.as_raw_fd(), CloneFlags::CLONE_NEWNET).map_err(|e| {
            CniError::new(
                CniErrorCode::NamespaceFailure,
                "failed to restore original network namespace",
            )
            .with_details(&e.to_string())
        })?;
        // Don't run Drop since we've already restored
        std::mem::forget(self);
        Ok(())
    }
}

impl Drop for NetnsGuard {
    fn drop(&mut self) {
        // Best effort restore - if this fails, we can't do much about it
        // The process will terminate anyway in CNI context
        let _ = setns(self.original_ns.as_raw_fd(), CloneFlags::CLONE_NEWNET);
    }
}

/// Execute a closure within a different network namespace
///
/// # Arguments
/// * `netns_path` - Path to the target network namespace
/// * `f` - Closure to execute in the namespace
///
/// # Returns
/// The result of the closure, or an error if namespace operations failed
pub fn with_netns<T, F>(netns_path: &str, f: F) -> Result<T, CniError>
where
    F: FnOnce() -> Result<T, CniError>,
{
    let guard = NetnsGuard::enter(netns_path)?;
    let result = f();
    guard.restore()?;
    result
}

/// Get the network namespace file descriptor for a given path
///
/// # Arguments
/// * `netns_path` - Path to the network namespace file
///
/// # Returns
/// The file handle to the network namespace
pub fn open_netns(netns_path: &str) -> Result<File, CniError> {
    File::open(netns_path).map_err(|e| {
        CniError::new(
            CniErrorCode::NamespaceFailure,
            &format!("failed to open network namespace: {}", netns_path),
        )
        .with_details(&e.to_string())
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_current_netns_readable() {
        // Just verify we can open our own network namespace
        let result = File::open("/proc/self/ns/net");
        assert!(result.is_ok(), "Should be able to open own network namespace");
    }

    #[test]
    fn test_invalid_netns_path() {
        let result = open_netns("/nonexistent/path/ns/net");
        assert!(result.is_err());
    }
}
