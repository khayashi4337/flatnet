//! Health check implementations
//!
//! This module contains health checks for various Flatnet components.

pub mod cni;
pub mod disk;
pub mod gateway;
pub mod monitoring;
pub mod network;

use serde::Serialize;

/// Result of a single health check
#[derive(Debug, Clone, Serialize)]
pub struct CheckResult {
    /// Category of the check (e.g., "Gateway", "Network")
    pub category: String,
    /// Name of the check
    pub name: String,
    /// Status of the check
    pub status: CheckStatus,
    /// Human-readable message describing the result
    pub message: String,
    /// Optional suggestion for fixing issues
    #[serde(skip_serializing_if = "Option::is_none")]
    pub suggestion: Option<String>,
}

/// Status of a health check
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum CheckStatus {
    /// Check passed successfully
    Pass,
    /// Check passed with warnings
    Warning,
    /// Check failed
    Fail,
}

impl CheckResult {
    /// Create a new passing check result
    pub fn pass(category: &str, name: &str, message: impl Into<String>) -> Self {
        Self {
            category: category.to_string(),
            name: name.to_string(),
            status: CheckStatus::Pass,
            message: message.into(),
            suggestion: None,
        }
    }

    /// Create a new warning check result
    pub fn warning(
        category: &str,
        name: &str,
        message: impl Into<String>,
        suggestion: impl Into<String>,
    ) -> Self {
        Self {
            category: category.to_string(),
            name: name.to_string(),
            status: CheckStatus::Warning,
            message: message.into(),
            suggestion: Some(suggestion.into()),
        }
    }

    /// Create a new failing check result
    pub fn fail(
        category: &str,
        name: &str,
        message: impl Into<String>,
        suggestion: impl Into<String>,
    ) -> Self {
        Self {
            category: category.to_string(),
            name: name.to_string(),
            status: CheckStatus::Fail,
            message: message.into(),
            suggestion: Some(suggestion.into()),
        }
    }
}

/// Run all health checks
pub async fn run_all_checks(config: &crate::config::Config) -> Vec<CheckResult> {
    // Run all check categories in parallel
    let (gateway_results, cni_results, network_results, monitoring_results, disk_results) =
        tokio::join!(
            gateway::run_checks(config),
            cni::run_checks(config),
            network::run_checks(config),
            monitoring::run_checks(config),
            disk::run_checks(config),
        );

    // Combine all results
    let mut results = Vec::new();
    results.extend(gateway_results);
    results.extend(cni_results);
    results.extend(network_results);
    results.extend(monitoring_results);
    results.extend(disk_results);

    results
}

/// Calculate summary statistics from check results
pub fn calculate_summary(results: &[CheckResult]) -> (usize, usize, usize) {
    let passed = results
        .iter()
        .filter(|r| r.status == CheckStatus::Pass)
        .count();
    let warnings = results
        .iter()
        .filter(|r| r.status == CheckStatus::Warning)
        .count();
    let failed = results
        .iter()
        .filter(|r| r.status == CheckStatus::Fail)
        .count();

    (passed, warnings, failed)
}

/// Determine the exit code based on check results
pub fn determine_exit_code(results: &[CheckResult]) -> i32 {
    if results.iter().any(|r| r.status == CheckStatus::Fail) {
        2
    } else if results.iter().any(|r| r.status == CheckStatus::Warning) {
        1
    } else {
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_check_result_pass() {
        let result = CheckResult::pass("Gateway", "HTTP", "Service is running");
        assert_eq!(result.status, CheckStatus::Pass);
        assert!(result.suggestion.is_none());
    }

    #[test]
    fn test_check_result_warning() {
        let result = CheckResult::warning(
            "Disk",
            "Usage",
            "Disk usage at 85%",
            "Consider cleaning up",
        );
        assert_eq!(result.status, CheckStatus::Warning);
        assert!(result.suggestion.is_some());
    }

    #[test]
    fn test_check_result_fail() {
        let result = CheckResult::fail(
            "Gateway",
            "HTTP",
            "Connection refused",
            "Start the Gateway service",
        );
        assert_eq!(result.status, CheckStatus::Fail);
        assert!(result.suggestion.is_some());
    }

    #[test]
    fn test_determine_exit_code() {
        // All pass
        let results = vec![CheckResult::pass("Test", "Test1", "OK")];
        assert_eq!(determine_exit_code(&results), 0);

        // One warning
        let results = vec![
            CheckResult::pass("Test", "Test1", "OK"),
            CheckResult::warning("Test", "Test2", "Warn", "Fix it"),
        ];
        assert_eq!(determine_exit_code(&results), 1);

        // One fail
        let results = vec![
            CheckResult::pass("Test", "Test1", "OK"),
            CheckResult::fail("Test", "Test2", "Failed", "Fix it"),
        ];
        assert_eq!(determine_exit_code(&results), 2);
    }

    #[test]
    fn test_calculate_summary() {
        let results = vec![
            CheckResult::pass("Test", "Test1", "OK"),
            CheckResult::pass("Test", "Test2", "OK"),
            CheckResult::warning("Test", "Test3", "Warn", "Fix"),
            CheckResult::fail("Test", "Test4", "Fail", "Fix"),
        ];
        let (passed, warnings, failed) = calculate_summary(&results);
        assert_eq!(passed, 2);
        assert_eq!(warnings, 1);
        assert_eq!(failed, 1);
    }
}
