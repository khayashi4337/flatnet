//! Network connectivity checks
//!
//! Checks for network connectivity between WSL2 and Windows host.

use super::CheckResult;
use crate::config::Config;
use reqwest::Client;
use std::time::Duration;

const CATEGORY: &str = "Network";
const CHECK_TIMEOUT: Duration = Duration::from_secs(5);

/// Run all network checks
pub async fn run_checks(config: &Config) -> Vec<CheckResult> {
    let gateway_url = config.gateway_url();

    let wsl_windows_check = check_wsl_to_windows(gateway_url).await;

    vec![wsl_windows_check]
}

/// Check connectivity from WSL2 to Windows host
async fn check_wsl_to_windows(gateway_url: &str) -> CheckResult {
    let client = match Client::builder().timeout(CHECK_TIMEOUT).build() {
        Ok(c) => c,
        Err(e) => {
            return CheckResult::fail(
                CATEGORY,
                "WSL2 to Windows",
                format!("Failed to create HTTP client: {}", e),
                "Check system configuration",
            );
        }
    };

    // Try to connect to the Gateway on Windows
    match client.get(gateway_url).send().await {
        Ok(_) => CheckResult::pass(
            CATEGORY,
            "WSL2 to Windows",
            "WSL2 -> Windows connectivity OK",
        ),
        Err(e) => {
            if e.is_timeout() {
                CheckResult::fail(
                    CATEGORY,
                    "WSL2 to Windows",
                    "Connection timed out",
                    "Check Windows Firewall settings and ensure Gateway is running",
                )
            } else if e.is_connect() {
                CheckResult::fail(
                    CATEGORY,
                    "WSL2 to Windows",
                    "Connection refused",
                    "Check Windows Firewall settings: netsh advfirewall firewall show rule name=all | findstr flatnet",
                )
            } else {
                CheckResult::fail(
                    CATEGORY,
                    "WSL2 to Windows",
                    format!("Connection failed: {}", e),
                    "Check network configuration and Windows Firewall",
                )
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_category_name() {
        assert_eq!(CATEGORY, "Network");
    }
}
