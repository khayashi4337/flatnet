//! CNI Error types
//!
//! Error codes and types as defined in CNI Spec 1.0.0

use thiserror::Error;

/// CNI error codes as defined in the specification
///
/// See: https://github.com/containernetworking/cni/blob/spec-v1.0.0/SPEC.md#error
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
#[allow(dead_code)] // Some variants reserved for future use
pub enum CniErrorCode {
    /// 1: Incompatible CNI version
    IncompatibleVersion = 1,

    /// 2: Unsupported field in network configuration
    UnsupportedField = 2,

    /// 3: Container unknown or does not exist
    UnknownContainer = 3,

    /// 4: Invalid necessary environment variables
    InvalidEnvironmentVariables = 4,

    /// 5: I/O failure
    IoFailure = 5,

    /// 6: Failed to decode content
    DecodingFailure = 6,

    /// 7: Invalid network config
    InvalidNetworkConfig = 7,

    /// 11: Try again later
    TryAgainLater = 11,

    // Plugin-specific errors (100+)

    /// 100: Bridge creation failed
    BridgeCreationFailed = 100,

    /// 101: Veth creation failed
    VethCreationFailed = 101,

    /// 102: IPAM failure
    IpamFailure = 102,

    /// 103: Namespace operation failed
    NamespaceFailure = 103,

    /// 104: Route configuration failed
    RouteFailure = 104,
}

/// CNI error with code, message, and optional details
#[derive(Debug, Error)]
#[error("{msg}")]
pub struct CniError {
    code: CniErrorCode,
    msg: String,
    details: Option<String>,
}

impl CniError {
    /// Create a new CNI error
    pub fn new(code: CniErrorCode, msg: &str) -> Self {
        Self {
            code,
            msg: msg.to_string(),
            details: None,
        }
    }

    /// Add details to the error
    pub fn with_details(mut self, details: &str) -> Self {
        self.details = Some(details.to_string());
        self
    }

    /// Get the error code
    pub fn code(&self) -> CniErrorCode {
        self.code
    }

    /// Get the error message
    pub fn message(&self) -> &str {
        &self.msg
    }

    /// Get the error details
    pub fn details(&self) -> Option<&str> {
        self.details.as_deref()
    }
}

// Convenience constructors for common errors

impl CniError {
    /// Create an IO error
    pub fn io_error(msg: &str) -> Self {
        Self::new(CniErrorCode::IoFailure, msg)
    }

    /// Create a decoding error
    pub fn decode_error(msg: &str) -> Self {
        Self::new(CniErrorCode::DecodingFailure, msg)
    }

    /// Create an invalid config error
    pub fn config_error(msg: &str) -> Self {
        Self::new(CniErrorCode::InvalidNetworkConfig, msg)
    }

    /// Create a bridge error
    pub fn bridge_error(msg: &str) -> Self {
        Self::new(CniErrorCode::BridgeCreationFailed, msg)
    }

    /// Create a veth error
    pub fn veth_error(msg: &str) -> Self {
        Self::new(CniErrorCode::VethCreationFailed, msg)
    }

    /// Create an IPAM error
    pub fn ipam_error(msg: &str) -> Self {
        Self::new(CniErrorCode::IpamFailure, msg)
    }

    /// Create a namespace error
    pub fn namespace_error(msg: &str) -> Self {
        Self::new(CniErrorCode::NamespaceFailure, msg)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_code_values() {
        assert_eq!(CniErrorCode::IncompatibleVersion as u32, 1);
        assert_eq!(CniErrorCode::IoFailure as u32, 5);
        assert_eq!(CniErrorCode::BridgeCreationFailed as u32, 100);
    }

    #[test]
    fn test_error_with_details() {
        let err = CniError::new(CniErrorCode::IoFailure, "read failed")
            .with_details("permission denied");

        assert_eq!(err.code(), CniErrorCode::IoFailure);
        assert_eq!(err.message(), "read failed");
        assert_eq!(err.details(), Some("permission denied"));
    }

    #[test]
    fn test_convenience_constructors() {
        let err = CniError::io_error("failed");
        assert_eq!(err.code(), CniErrorCode::IoFailure);

        let err = CniError::bridge_error("bridge exists");
        assert_eq!(err.code(), CniErrorCode::BridgeCreationFailed);
    }
}
