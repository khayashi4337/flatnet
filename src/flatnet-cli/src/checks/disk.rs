//! Disk space checks
//!
//! Checks for available disk space on relevant filesystems.

use super::CheckResult;
use crate::config::Config;
use std::process::Stdio;

const CATEGORY: &str = "Disk";

/// Warning threshold for disk usage (percentage)
const DISK_WARNING_THRESHOLD: u8 = 80;

/// Critical threshold for disk usage (percentage)
const DISK_CRITICAL_THRESHOLD: u8 = 95;

/// Run all disk checks
pub async fn run_checks(_config: &Config) -> Vec<CheckResult> {
    let disk_check = check_disk_usage().await;
    vec![disk_check]
}

/// Check disk usage on the root filesystem
async fn check_disk_usage() -> CheckResult {
    // Use df command to check disk usage
    let output = tokio::process::Command::new("df")
        .args(["--output=pcent", "/"])
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .await;

    match output {
        Ok(output) if output.status.success() => {
            let stdout = String::from_utf8_lossy(&output.stdout);

            // Parse the output - format is "Use%\n XX%"
            if let Some(usage) = parse_disk_usage(&stdout) {
                if usage >= DISK_CRITICAL_THRESHOLD {
                    CheckResult::fail(
                        CATEGORY,
                        "Disk usage",
                        format!("Disk usage at {}% (critical)", usage),
                        "Free up disk space immediately: podman system prune -a",
                    )
                } else if usage >= DISK_WARNING_THRESHOLD {
                    CheckResult::warning(
                        CATEGORY,
                        "Disk usage",
                        format!("Disk usage at {}%", usage),
                        "Consider cleaning up: podman system prune",
                    )
                } else {
                    CheckResult::pass(
                        CATEGORY,
                        "Disk usage",
                        format!("Disk usage at {}%", usage),
                    )
                }
            } else {
                CheckResult::warning(
                    CATEGORY,
                    "Disk usage",
                    "Could not parse disk usage",
                    "Run 'df -h' manually to check disk space",
                )
            }
        }
        Ok(_) => CheckResult::warning(
            CATEGORY,
            "Disk usage",
            "df command failed",
            "Run 'df -h' manually to check disk space",
        ),
        Err(e) => CheckResult::warning(
            CATEGORY,
            "Disk usage",
            format!("Could not check disk usage: {}", e),
            "Ensure 'df' command is available",
        ),
    }
}

/// Parse disk usage percentage from df output
fn parse_disk_usage(output: &str) -> Option<u8> {
    // Output format is typically:
    // Use%
    //  XX%
    for line in output.lines().skip(1) {
        let trimmed = line.trim();
        if let Some(percent_str) = trimmed.strip_suffix('%') {
            if let Ok(percent) = percent_str.trim().parse::<u8>() {
                return Some(percent);
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_disk_usage() {
        let output = "Use%\n 45%\n";
        assert_eq!(parse_disk_usage(output), Some(45));

        let output = "Use%\n  5%\n";
        assert_eq!(parse_disk_usage(output), Some(5));

        let output = "Use%\n 100%\n";
        assert_eq!(parse_disk_usage(output), Some(100));

        let output = "invalid";
        assert_eq!(parse_disk_usage(output), None);
    }

    #[test]
    fn test_thresholds() {
        assert!(DISK_WARNING_THRESHOLD < DISK_CRITICAL_THRESHOLD);
        assert!(DISK_WARNING_THRESHOLD > 0);
        assert!(DISK_CRITICAL_THRESHOLD <= 100);
    }
}
