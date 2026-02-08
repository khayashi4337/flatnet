//! Monitoring service checks
//!
//! Checks for Prometheus, Grafana, and Loki services.

use super::CheckResult;
use crate::config::Config;
use reqwest::Client;
use std::time::Duration;

const CATEGORY: &str = "Monitoring";
const CHECK_TIMEOUT: Duration = Duration::from_secs(5);

/// Run all monitoring checks
pub async fn run_checks(config: &Config) -> Vec<CheckResult> {
    // Run all monitoring service checks in parallel
    let (prometheus_check, grafana_check, loki_check) = tokio::join!(
        check_prometheus(&config.monitoring.prometheus_url),
        check_grafana(&config.monitoring.grafana_url),
        check_loki(&config.monitoring.loki_url),
    );

    vec![prometheus_check, grafana_check, loki_check]
}

/// Check if Prometheus is running
async fn check_prometheus(url: &str) -> CheckResult {
    check_service("Prometheus", url, "/-/healthy", ":9090").await
}

/// Check if Grafana is running
async fn check_grafana(url: &str) -> CheckResult {
    check_service("Grafana", url, "/api/health", ":3000").await
}

/// Check if Loki is running
async fn check_loki(url: &str) -> CheckResult {
    check_service("Loki", url, "/ready", ":3100").await
}

/// Generic service health check
async fn check_service(name: &str, base_url: &str, health_path: &str, port: &str) -> CheckResult {
    let client = match Client::builder().timeout(CHECK_TIMEOUT).build() {
        Ok(c) => c,
        Err(e) => {
            return CheckResult::fail(
                CATEGORY,
                &format!("{} running", name),
                format!("Failed to create HTTP client: {}", e),
                "Check system configuration",
            );
        }
    };

    let health_url = format!("{}{}", base_url.trim_end_matches('/'), health_path);

    match client.get(&health_url).send().await {
        Ok(resp) if resp.status().is_success() => CheckResult::pass(
            CATEGORY,
            &format!("{} running", name),
            format!("{} running ({})", name, port),
        ),
        Ok(resp) => CheckResult::warning(
            CATEGORY,
            &format!("{} running", name),
            format!("{} returned status {} ({})", name, resp.status(), port),
            format!("Check {} logs and configuration", name),
        ),
        Err(_) => CheckResult::warning(
            CATEGORY,
            &format!("{} running", name),
            format!("{} not responding ({})", name, port),
            "Start monitoring stack: podman-compose up -d",
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_check_result_category() {
        // Just ensure the category constant is correct
        assert_eq!(CATEGORY, "Monitoring");
    }
}
