//! Gateway health checks
//!
//! Checks for Gateway HTTP, API, and metrics endpoints.

use super::CheckResult;
use crate::clients::gateway::GatewayClient;
use crate::config::Config;
use reqwest::Client;
use std::time::Duration;

const CATEGORY: &str = "Gateway";
const CHECK_TIMEOUT: Duration = Duration::from_secs(5);

/// Run all gateway checks
pub async fn run_checks(config: &Config) -> Vec<CheckResult> {
    let gateway_url = config.gateway_url();

    // Run gateway checks in parallel
    let (http_check, api_check, metrics_check) = tokio::join!(
        check_http(gateway_url),
        check_api(gateway_url, config.gateway_timeout()),
        check_metrics(gateway_url),
    );

    vec![http_check, api_check, metrics_check]
}

/// Check if the Gateway HTTP server is responding
async fn check_http(gateway_url: &str) -> CheckResult {
    let client = match Client::builder().timeout(CHECK_TIMEOUT).build() {
        Ok(c) => c,
        Err(e) => {
            return CheckResult::fail(
                CATEGORY,
                "HTTP responding",
                format!("Failed to create HTTP client: {}", e),
                "Check system configuration",
            );
        }
    };

    // Extract host:port for display
    let address = extract_address(gateway_url);

    match client.get(gateway_url).send().await {
        Ok(resp) if resp.status().is_success() || resp.status().as_u16() == 404 => {
            // 404 is OK - it means the server is responding
            CheckResult::pass(
                CATEGORY,
                "HTTP responding",
                format!("Gateway is responding ({})", address),
            )
        }
        Ok(resp) => CheckResult::warning(
            CATEGORY,
            "HTTP responding",
            format!("Unexpected status {} ({})", resp.status(), address),
            "Check Gateway logs for errors",
        ),
        Err(e) => {
            let suggestion = if e.is_timeout() {
                "Gateway is not responding. Check if it is running and accessible."
            } else if e.is_connect() {
                "Start Gateway: cd F:\\flatnet\\openresty && nginx.exe"
            } else {
                "Check network connectivity and Gateway configuration"
            };
            CheckResult::fail(
                CATEGORY,
                "HTTP responding",
                format!("Connection failed ({})", address),
                suggestion,
            )
        }
    }
}

/// Check if the Gateway API is available
async fn check_api(gateway_url: &str, timeout: Duration) -> CheckResult {
    let address = extract_address(gateway_url);

    match GatewayClient::new(gateway_url, timeout) {
        Ok(client) => match client.status().await {
            Ok(status) => {
                if status.status == "running" {
                    CheckResult::pass(
                        CATEGORY,
                        "API available",
                        format!("API endpoint responding ({})", address),
                    )
                } else {
                    CheckResult::warning(
                        CATEGORY,
                        "API available",
                        format!("API status: {} ({})", status.status, address),
                        "Check Gateway status and logs",
                    )
                }
            }
            Err(e) => CheckResult::fail(
                CATEGORY,
                "API available",
                format!("API request failed: {}", e),
                "Ensure Gateway API is enabled and check nginx.conf",
            ),
        },
        Err(e) => CheckResult::fail(
            CATEGORY,
            "API available",
            format!("Failed to create client: {}", e),
            "Check Gateway URL configuration",
        ),
    }
}

/// Check if the Gateway metrics endpoint is responding
async fn check_metrics(gateway_url: &str) -> CheckResult {
    let client = match Client::builder().timeout(CHECK_TIMEOUT).build() {
        Ok(c) => c,
        Err(e) => {
            return CheckResult::fail(
                CATEGORY,
                "Metrics endpoint",
                format!("Failed to create HTTP client: {}", e),
                "Check system configuration",
            );
        }
    };

    // Metrics are typically on port 9145
    // Parse the gateway URL to construct the metrics URL
    let metrics_url = if let Some(host) = extract_host(gateway_url) {
        format!("http://{}:9145/metrics", host)
    } else {
        // Fallback: simple replacement
        let base = gateway_url
            .replace(":8080", ":9145")
            .replace(":80", ":9145");
        format!("{}/metrics", base.trim_end_matches('/'))
    };

    match client.get(&metrics_url).send().await {
        Ok(resp) if resp.status().is_success() => CheckResult::pass(
            CATEGORY,
            "Metrics endpoint",
            "Metrics endpoint responding (:9145)",
        ),
        Ok(resp) => CheckResult::warning(
            CATEGORY,
            "Metrics endpoint",
            format!("Unexpected status {} (:9145)", resp.status()),
            "Check if metrics server is enabled in nginx.conf",
        ),
        Err(_) => CheckResult::warning(
            CATEGORY,
            "Metrics endpoint",
            "Metrics endpoint not responding (:9145)",
            "Check if metrics server is enabled in nginx.conf",
        ),
    }
}

/// Extract address from URL for display
fn extract_address(url: &str) -> String {
    url.trim_start_matches("http://")
        .trim_start_matches("https://")
        .to_string()
}

/// Extract host (without port) from URL
fn extract_host(url: &str) -> Option<String> {
    let without_scheme = url
        .trim_start_matches("http://")
        .trim_start_matches("https://");

    // Get the host part (before any path or port)
    let host_port = without_scheme.split('/').next()?;

    // Remove port if present
    let host = if let Some(colon_pos) = host_port.rfind(':') {
        // Check if this is an IPv6 address in brackets
        if host_port.starts_with('[') {
            // IPv6: [::1]:8080 -> [::1]
            if let Some(bracket_pos) = host_port.find(']') {
                if colon_pos > bracket_pos {
                    &host_port[..colon_pos]
                } else {
                    host_port
                }
            } else {
                host_port
            }
        } else {
            &host_port[..colon_pos]
        }
    } else {
        host_port
    };

    if host.is_empty() {
        None
    } else {
        Some(host.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_address() {
        assert_eq!(extract_address("http://10.100.1.1:8080"), "10.100.1.1:8080");
        assert_eq!(
            extract_address("https://example.com:443"),
            "example.com:443"
        );
    }

    #[test]
    fn test_extract_host() {
        assert_eq!(
            extract_host("http://10.100.1.1:8080"),
            Some("10.100.1.1".to_string())
        );
        assert_eq!(
            extract_host("http://localhost:8080/api"),
            Some("localhost".to_string())
        );
        assert_eq!(
            extract_host("http://example.com"),
            Some("example.com".to_string())
        );
        assert_eq!(
            extract_host("https://[::1]:8080"),
            Some("[::1]".to_string())
        );
    }
}
