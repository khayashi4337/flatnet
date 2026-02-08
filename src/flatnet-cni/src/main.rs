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
    let _config: NetworkConfig = serde_json::from_str(input).map_err(|e| {
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

    // TODO: Implement actual network setup
    // 1. Create veth pair
    // 2. Move one end to container namespace
    // 3. Assign IP address (via IPAM)
    // 4. Connect host end to bridge

    // For now, return a placeholder result
    let result = CniResult::new(CNI_VERSION.to_string())
        .with_interface(
            ifname.clone(),
            "00:00:00:00:00:00".to_string(),
            Some(netns.clone()),
        )
        .with_ip(
            "10.42.0.2/16".to_string(),
            Some("10.42.0.1".to_string()),
            0,
        );

    // Log for debugging (will be removed in production)
    eprintln!(
        "flatnet ADD: container={}, netns={}, ifname={}",
        container_id, netns, ifname
    );

    // Output result to stdout
    println!("{}", serde_json::to_string(&result).map_err(|e| {
        CniError::new(CniErrorCode::IoFailure, "failed to serialize result")
            .with_details(&e.to_string())
    })?);

    Ok(())
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
    let _config: NetworkConfig = serde_json::from_str(input).map_err(|e| {
        CniError::new(CniErrorCode::DecodingFailure, "failed to parse network config")
            .with_details(&e.to_string())
    })?;

    // TODO: These should be required for CHECK per CNI spec
    // Currently using unwrap_or_default for placeholder implementation
    let container_id = env::var("CNI_CONTAINERID").unwrap_or_default();
    let ifname = env::var("CNI_IFNAME").unwrap_or_default();

    // TODO: Implement actual network verification
    // 1. Check interface exists in container namespace
    // 2. Verify IP configuration matches prevResult

    eprintln!(
        "flatnet CHECK: container={}, ifname={}",
        container_id, ifname
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

    println!("{}", serde_json::to_string(&result).map_err(|e| {
        CniError::new(CniErrorCode::IoFailure, "failed to serialize version")
            .with_details(&e.to_string())
    })?);

    Ok(())
}
