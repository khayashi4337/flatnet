//! CNI Plugin health checks
//!
//! Checks for CNI bridge and IPAM state.

use super::CheckResult;
use crate::clients::gateway::GatewayClient;
use crate::config::Config;
use std::process::Stdio;

const CATEGORY: &str = "CNI Plugin";

/// Run all CNI checks
pub async fn run_checks(config: &Config) -> Vec<CheckResult> {
    // Run CNI checks in parallel
    let (bridge_check, ipam_check) = tokio::join!(check_cni_bridge(), check_ipam_state(config));

    vec![bridge_check, ipam_check]
}

/// Check if the CNI bridge exists
async fn check_cni_bridge() -> CheckResult {
    // Check if flatnet bridge exists using ip command
    let output = tokio::process::Command::new("ip")
        .args(["link", "show", "flatnet-br0"])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .await;

    match output {
        Ok(output) if output.status.success() => {
            // Bridge exists, try to get more info
            let stdout = String::from_utf8_lossy(&output.stdout);
            if stdout.contains("state UP") {
                CheckResult::pass(CATEGORY, "Bridge exists", "Bridge exists (flatnet-br0)")
            } else if stdout.contains("state DOWN") {
                CheckResult::warning(
                    CATEGORY,
                    "Bridge exists",
                    "Bridge exists but is DOWN (flatnet-br0)",
                    "Run: sudo ip link set flatnet-br0 up",
                )
            } else {
                CheckResult::pass(CATEGORY, "Bridge exists", "Bridge exists (flatnet-br0)")
            }
        }
        Ok(_) => {
            // Bridge doesn't exist - this is OK if no containers are running
            CheckResult::warning(
                CATEGORY,
                "Bridge exists",
                "Bridge not found (flatnet-br0)",
                "Bridge will be created when first container starts",
            )
        }
        Err(e) => CheckResult::warning(
            CATEGORY,
            "Bridge exists",
            format!("Could not check bridge: {}", e),
            "Ensure 'ip' command is available (iproute2 package)",
        ),
    }
}

/// Check IPAM state by querying the Gateway API
async fn check_ipam_state(config: &Config) -> CheckResult {
    match GatewayClient::new(config.gateway_url(), config.gateway_timeout()) {
        Ok(client) => match client.status().await {
            Ok(status) => {
                if let Some(ref registry) = status.registry {
                    let ip_count = registry.total_count;
                    CheckResult::pass(
                        CATEGORY,
                        "IPAM state valid",
                        format!("IPAM state valid ({} IPs allocated)", ip_count),
                    )
                } else {
                    CheckResult::pass(
                        CATEGORY,
                        "IPAM state valid",
                        "IPAM state valid (no allocations)",
                    )
                }
            }
            Err(_) => CheckResult::warning(
                CATEGORY,
                "IPAM state valid",
                "Could not verify IPAM state",
                "Gateway API unavailable. Start Gateway to check IPAM state.",
            ),
        },
        Err(_) => CheckResult::warning(
            CATEGORY,
            "IPAM state valid",
            "Could not check IPAM state",
            "Failed to connect to Gateway API",
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_category_name() {
        assert_eq!(CATEGORY, "CNI Plugin");
    }
}
