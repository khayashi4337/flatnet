//! Logs command implementation
//!
//! Displays logs from Flatnet components and containers.

use anyhow::{bail, Result};
use colored::Colorize;
use serde::Serialize;
use std::time::Duration;

use crate::cli::LogsArgs;
use crate::clients::loki::{component_to_job, is_known_component, LokiClient, LogEntry};
use crate::clients::podman::PodmanClient;
use crate::config::Config;

/// JSON output structure
#[derive(Debug, Clone, Serialize)]
struct LogsOutput {
    target: String,
    source: String, // "loki" or "podman"
    entries: Vec<LogEntryOutput>,
}

#[derive(Debug, Clone, Serialize)]
struct LogEntryOutput {
    timestamp: Option<String>,
    line: String,
}

/// Run the logs command
pub async fn run(args: LogsArgs) -> Result<()> {
    let config = Config::load()?;

    // Determine the target (component or container name)
    let target = &args.target;

    // Try Loki first if it's a known component
    if is_known_component(target) {
        if let Some(job) = component_to_job(target) {
            match fetch_from_loki(&config, job, &args).await {
                Ok(entries) => {
                    output_logs(&args, target, "loki", &entries, config.color_enabled())?;
                    return Ok(());
                }
                Err(e) => {
                    // Loki failed, will try podman fallback
                    if !args.json {
                        eprintln!(
                            "{}: Loki unavailable ({}), falling back to Podman logs...",
                            "Note".yellow(),
                            e
                        );
                    }
                }
            }
        }
    }

    // Fallback to Podman logs
    if args.follow {
        follow_podman_logs(target, config.color_enabled()).await
    } else {
        fetch_from_podman(target, &args, config.color_enabled())
    }
}

/// Fetch logs from Loki
async fn fetch_from_loki(
    config: &Config,
    job: &str,
    args: &LogsArgs,
) -> Result<Vec<LogEntry>> {
    let timeout = Duration::from_secs(config.gateway.timeout_secs);
    let client = LokiClient::new(&config.monitoring.loki_url, timeout)?;

    // Check if Loki is ready
    if !client.is_ready().await {
        bail!("Loki is not ready");
    }

    let limit = args.tail.unwrap_or(100);
    let since = args.since.as_deref();

    let entries = if let Some(ref grep) = args.grep {
        let query = format!("{{job=\"{}\"}}", job);
        client
            .query_logs_with_filter(&query, grep, limit, since)
            .await?
    } else {
        client.query_job_logs(job, limit, since).await?
    };

    Ok(entries)
}

/// Fetch logs from Podman
fn fetch_from_podman(target: &str, args: &LogsArgs, use_color: bool) -> Result<()> {
    let podman = PodmanClient::new();

    // Check if container exists
    if !podman.container_exists(target) {
        if use_color {
            eprintln!(
                "{}: Container or component '{}' not found.",
                "Error".red(),
                target
            );
        } else {
            eprintln!("Error: Container or component '{}' not found.", target);
        }

        // Show available options
        eprintln!();
        eprintln!("Known components: gateway, cni, prometheus, grafana, loki");
        eprintln!("Or specify a container name (use 'flatnet ps' to list containers)");

        bail!("Target not found: {}", target);
    }

    let logs = podman.get_logs(target, args.tail, args.since.as_deref())?;

    // Apply grep filter if specified
    let lines: Vec<&str> = if let Some(ref grep) = args.grep {
        logs.lines().filter(|line| line.contains(grep)).collect()
    } else {
        logs.lines().collect()
    };

    if args.json {
        let output = LogsOutput {
            target: target.to_string(),
            source: "podman".to_string(),
            entries: lines
                .iter()
                .map(|line| LogEntryOutput {
                    timestamp: None,
                    line: (*line).to_string(),
                })
                .collect(),
        };
        println!("{}", serde_json::to_string_pretty(&output)?);
    } else {
        for line in lines {
            println!("{}", line);
        }
    }

    Ok(())
}

/// Follow Podman logs in real-time
async fn follow_podman_logs(target: &str, use_color: bool) -> Result<()> {
    let podman = PodmanClient::new();

    // Check if container exists
    if !podman.container_exists(target) {
        if use_color {
            eprintln!(
                "{}: Container or component '{}' not found.",
                "Error".red(),
                target
            );
        } else {
            eprintln!("Error: Container or component '{}' not found.", target);
        }
        bail!("Target not found: {}", target);
    }

    // Follow logs
    podman
        .follow_logs(target, |line| {
            println!("{}", line);
        })
        .await
}

/// Output logs (from Loki)
fn output_logs(
    args: &LogsArgs,
    target: &str,
    source: &str,
    entries: &[LogEntry],
    use_color: bool,
) -> Result<()> {
    if args.json {
        let output = LogsOutput {
            target: target.to_string(),
            source: source.to_string(),
            entries: entries
                .iter()
                .map(|e| LogEntryOutput {
                    timestamp: Some(format_timestamp(e.timestamp)),
                    line: e.line.clone(),
                })
                .collect(),
        };
        println!("{}", serde_json::to_string_pretty(&output)?);
    } else {
        if entries.is_empty() {
            if use_color {
                println!("{}", "No logs found.".dimmed());
            } else {
                println!("No logs found.");
            }
            return Ok(());
        }

        for entry in entries {
            let timestamp = format_timestamp(entry.timestamp);
            if use_color {
                println!("{} {}", timestamp.dimmed(), entry.line);
            } else {
                println!("{} {}", timestamp, entry.line);
            }
        }
    }

    Ok(())
}

/// Format nanosecond timestamp to human-readable format
fn format_timestamp(timestamp_ns: i64) -> String {
    use chrono::{DateTime, Utc};

    let secs = timestamp_ns / 1_000_000_000;
    let nsecs = (timestamp_ns % 1_000_000_000) as u32;

    match DateTime::from_timestamp(secs, nsecs) {
        Some(dt) => dt.format("%Y-%m-%dT%H:%M:%SZ").to_string(),
        None => "-".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_timestamp() {
        // Test a known timestamp
        let ts = 1700000000_000_000_000i64; // 2023-11-14T22:13:20Z
        let formatted = format_timestamp(ts);
        assert!(formatted.starts_with("2023-11-14"));
    }

    #[test]
    fn test_format_timestamp_zero() {
        let formatted = format_timestamp(0);
        assert!(formatted.starts_with("1970-01-01"));
    }
}
