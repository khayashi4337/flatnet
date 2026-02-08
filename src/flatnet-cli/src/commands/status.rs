//! Status command implementation
//!
//! Displays the status of all Flatnet components.

use anyhow::Result;
use colored::Colorize;
use serde::Serialize;
use std::io::{self, Write};
use tokio::time::{sleep, Duration};

use crate::cli::StatusArgs;
use crate::clients::gateway::{GatewayClient, GatewayError};
use crate::config::Config;

/// Box drawing characters for nice formatting
mod box_chars {
    pub const TOP_LEFT: &str = "\u{256D}";
    pub const TOP_RIGHT: &str = "\u{256E}";
    pub const BOTTOM_LEFT: &str = "\u{2570}";
    pub const BOTTOM_RIGHT: &str = "\u{256F}";
    pub const HORIZONTAL: &str = "\u{2500}";
    pub const VERTICAL: &str = "\u{2502}";
    pub const T_RIGHT: &str = "\u{251C}";
    pub const T_LEFT: &str = "\u{2524}";
}

/// Status indicator symbols
const STATUS_OK: &str = "\u{25CF}"; // ● (green for running/ready)
const STATUS_STOPPED: &str = "\u{25CB}"; // ○ (red for stopped/error)
const STATUS_WARN: &str = "\u{25CF}"; // ● (yellow for warning/disabled)

/// Box width for the status display
const BOX_WIDTH: usize = 55;

/// Component status for JSON output
#[derive(Debug, Clone, Serialize)]
struct ComponentStatus {
    name: String,
    status: String,
    details: String,
}

/// Full system status for JSON output
#[derive(Debug, Clone, Serialize)]
struct SystemStatus {
    components: Vec<ComponentStatus>,
    containers: u32,
    uptime: Option<String>,
    gateway_url: String,
}

/// Run the status command
pub async fn run(args: StatusArgs) -> Result<()> {
    let config = Config::load()?;

    if args.watch {
        run_watch_mode(&config, &args).await
    } else {
        run_once(&config, &args).await
    }
}

/// Run status check once
async fn run_once(config: &Config, args: &StatusArgs) -> Result<()> {
    let status = collect_status(config).await;

    if args.json {
        print_json_status(&status)?;
    } else {
        print_formatted_status(&status, config.color_enabled());
    }

    Ok(())
}

/// Run in watch mode, updating periodically
async fn run_watch_mode(config: &Config, args: &StatusArgs) -> Result<()> {
    let interval = Duration::from_secs(args.interval);

    loop {
        // Clear screen
        print!("\x1B[2J\x1B[1;1H");
        io::stdout().flush()?;

        let status = collect_status(config).await;

        if args.json {
            print_json_status(&status)?;
        } else {
            print_formatted_status(&status, config.color_enabled());
            println!();
            println!(
                "{}",
                format!("Refreshing every {}s. Press Ctrl+C to exit.", args.interval).dimmed()
            );
        }

        sleep(interval).await;
    }
}

/// Collect status from all components
async fn collect_status(config: &Config) -> SystemStatus {
    let gateway_url = config.gateway_url().to_string();

    let mut components = Vec::new();
    let mut container_count = 0;

    // Gateway status
    match GatewayClient::new(&gateway_url, config.gateway_timeout()) {
        Ok(client) => match client.status().await {
            Ok(status) => {
                components.push(ComponentStatus {
                    name: "Gateway".to_string(),
                    status: "Running".to_string(),
                    details: extract_gateway_address(&gateway_url),
                });

                // CNI Plugin status from registry
                if let Some(ref registry) = status.registry {
                    container_count = registry.total_count;
                    let ip_range = format!("10.100.x.0/24 ({} IPs)", registry.total_count);
                    components.push(ComponentStatus {
                        name: "CNI Plugin".to_string(),
                        status: "Ready".to_string(),
                        details: ip_range,
                    });
                } else {
                    components.push(ComponentStatus {
                        name: "CNI Plugin".to_string(),
                        status: "Ready".to_string(),
                        details: "10.100.x.0/24".to_string(),
                    });
                }

                // Add healthcheck status
                if let Some(ref healthcheck) = status.healthcheck {
                    let hc_status = if healthcheck.enabled {
                        "Running"
                    } else {
                        "Disabled"
                    };
                    let hc_details = format!(
                        "{} healthy, {} unhealthy",
                        healthcheck.healthy_count, healthcheck.unhealthy_count
                    );
                    components.push(ComponentStatus {
                        name: "Healthcheck".to_string(),
                        status: hc_status.to_string(),
                        details: hc_details,
                    });
                }
            }
            Err(e) => {
                components.push(gateway_error_status(&e, &gateway_url));
                components.push(ComponentStatus {
                    name: "CNI Plugin".to_string(),
                    status: "Unknown".to_string(),
                    details: "Gateway unavailable".to_string(),
                });
            }
        },
        Err(e) => {
            components.push(ComponentStatus {
                name: "Gateway".to_string(),
                status: "Error".to_string(),
                details: format!("Failed to create client: {}", e),
            });
            components.push(ComponentStatus {
                name: "CNI Plugin".to_string(),
                status: "Unknown".to_string(),
                details: "Gateway unavailable".to_string(),
            });
        }
    }

    // Monitoring services status (check via HTTP in parallel)
    let (prometheus, grafana, loki) = tokio::join!(
        check_monitoring_service("Prometheus", &config.monitoring.prometheus_url, ":9090"),
        check_monitoring_service("Grafana", &config.monitoring.grafana_url, ":3000"),
        check_monitoring_service("Loki", &config.monitoring.loki_url, ":3100"),
    );
    components.push(prometheus);
    components.push(grafana);
    components.push(loki);

    SystemStatus {
        components,
        containers: container_count,
        uptime: None, // Would need uptime tracking in Gateway
        gateway_url,
    }
}

/// Check a monitoring service's health
async fn check_monitoring_service(name: &str, url: &str, port: &str) -> ComponentStatus {
    let client = match reqwest::Client::builder()
        .timeout(Duration::from_secs(2))
        .build()
    {
        Ok(c) => c,
        Err(_) => {
            return ComponentStatus {
                name: name.to_string(),
                status: "Unknown".to_string(),
                details: port.to_string(),
            };
        }
    };

    // Different services have different health endpoints
    let health_url = if name == "Prometheus" {
        format!("{}/-/healthy", url)
    } else if name == "Grafana" {
        format!("{}/api/health", url)
    } else if name == "Loki" {
        format!("{}/ready", url)
    } else {
        format!("{}/health", url)
    };

    match client.get(&health_url).send().await {
        Ok(resp) if resp.status().is_success() => ComponentStatus {
            name: name.to_string(),
            status: "Running".to_string(),
            details: port.to_string(),
        },
        Ok(_) => ComponentStatus {
            name: name.to_string(),
            status: "Warning".to_string(),
            details: port.to_string(),
        },
        Err(_) => ComponentStatus {
            name: name.to_string(),
            status: "Stopped".to_string(),
            details: port.to_string(),
        },
    }
}

/// Create a gateway error status component
fn gateway_error_status(error: &GatewayError, url: &str) -> ComponentStatus {
    let (status, details) = match error {
        GatewayError::ConnectionFailed(_) => ("Stopped", format!("{} (connection refused)", extract_gateway_address(url))),
        GatewayError::Timeout => ("Timeout", format!("{} (timeout)", extract_gateway_address(url))),
        GatewayError::RequestFailed(e) => ("Error", format!("{} ({})", extract_gateway_address(url), e)),
        GatewayError::InvalidResponse(e) => ("Error", format!("{} ({})", extract_gateway_address(url), e)),
    };

    ComponentStatus {
        name: "Gateway".to_string(),
        status: status.to_string(),
        details,
    }
}

/// Extract address from URL for display
fn extract_gateway_address(url: &str) -> String {
    url.trim_start_matches("http://")
        .trim_start_matches("https://")
        .to_string()
}

/// Print status in JSON format
fn print_json_status(status: &SystemStatus) -> Result<()> {
    let json = serde_json::to_string_pretty(status)?;
    println!("{}", json);
    Ok(())
}

/// Print formatted status with box drawing
fn print_formatted_status(status: &SystemStatus, use_color: bool) {
    // Top border
    print_box_top(use_color);

    // Title
    print_box_title("Flatnet System Status", use_color);

    // Separator
    print_box_separator(use_color);

    // Component statuses
    for component in &status.components {
        print_component_status(component, use_color);
    }

    // Bottom border
    print_box_bottom(use_color);

    // Footer info
    println!();
    if status.containers > 0 {
        let containers_str = format!("Containers: {} running", status.containers);
        if use_color {
            println!("{}", containers_str.dimmed());
        } else {
            println!("{}", containers_str);
        }
    }
}

/// Print box top border
fn print_box_top(use_color: bool) {
    let line = format!(
        "{}{}{}",
        box_chars::TOP_LEFT,
        box_chars::HORIZONTAL.repeat(BOX_WIDTH - 2),
        box_chars::TOP_RIGHT
    );
    if use_color {
        println!("{}", line.bright_black());
    } else {
        println!("{}", line);
    }
}

/// Print box title
fn print_box_title(title: &str, use_color: bool) {
    let padding = BOX_WIDTH - 4 - title.len();
    if use_color {
        println!(
            "{} {}{} {}",
            box_chars::VERTICAL.bright_black(),
            title.bold(),
            " ".repeat(padding),
            box_chars::VERTICAL.bright_black()
        );
    } else {
        println!(
            "{} {}{} {}",
            box_chars::VERTICAL,
            title,
            " ".repeat(padding),
            box_chars::VERTICAL
        );
    }
}

/// Print box separator
fn print_box_separator(use_color: bool) {
    let line = format!(
        "{}{}{}",
        box_chars::T_RIGHT,
        box_chars::HORIZONTAL.repeat(BOX_WIDTH - 2),
        box_chars::T_LEFT
    );
    if use_color {
        println!("{}", line.bright_black());
    } else {
        println!("{}", line);
    }
}

/// Print box bottom border
fn print_box_bottom(use_color: bool) {
    let line = format!(
        "{}{}{}",
        box_chars::BOTTOM_LEFT,
        box_chars::HORIZONTAL.repeat(BOX_WIDTH - 2),
        box_chars::BOTTOM_RIGHT
    );
    if use_color {
        println!("{}", line.bright_black());
    } else {
        println!("{}", line);
    }
}

/// Print a component status line
fn print_component_status(component: &ComponentStatus, use_color: bool) {
    let (indicator, status_text) = if use_color {
        match component.status.as_str() {
            "Running" | "Ready" => (
                STATUS_OK.green().to_string(),
                component.status.green().to_string(),
            ),
            "Warning" | "Disabled" => (
                STATUS_WARN.yellow().to_string(),
                component.status.yellow().to_string(),
            ),
            "Stopped" | "Error" | "Unknown" | "Timeout" => (
                STATUS_STOPPED.red().to_string(),
                component.status.red().to_string(),
            ),
            _ => (
                STATUS_STOPPED.to_string(),
                component.status.clone(),
            ),
        }
    } else {
        let indicator = match component.status.as_str() {
            "Running" | "Ready" => STATUS_OK,
            "Warning" | "Disabled" => STATUS_WARN,
            _ => STATUS_STOPPED,
        };
        (indicator.to_string(), component.status.clone())
    };

    // Format: "│ Name         ● Status     details                   │"
    let name_width = 12;
    let status_width = 10;
    let details_max = BOX_WIDTH - 6 - name_width - 3 - status_width - 2;

    // Truncate details safely (handle multi-byte UTF-8 characters)
    let details_char_count = component.details.chars().count();
    let details = if details_char_count > details_max {
        let truncated: String = component.details.chars().take(details_max - 3).collect();
        format!("{}...", truncated)
    } else {
        component.details.clone()
    };

    // Calculate padding based on character count for proper alignment
    let display_chars = details.chars().count();
    let details_padding = if display_chars < details_max {
        details_max - display_chars
    } else {
        0
    };

    if use_color {
        println!(
            "{} {:<name_width$} {} {:<status_width$} {}{} {}",
            box_chars::VERTICAL.bright_black(),
            component.name,
            indicator,
            status_text,
            details.dimmed(),
            " ".repeat(details_padding),
            box_chars::VERTICAL.bright_black(),
            name_width = name_width,
            status_width = status_width,
        );
    } else {
        println!(
            "{} {:<name_width$} {} {:<status_width$} {}{} {}",
            box_chars::VERTICAL,
            component.name,
            indicator,
            status_text,
            details,
            " ".repeat(details_padding),
            box_chars::VERTICAL,
            name_width = name_width,
            status_width = status_width,
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_gateway_address() {
        assert_eq!(
            extract_gateway_address("http://10.100.1.1:8080"),
            "10.100.1.1:8080"
        );
        assert_eq!(
            extract_gateway_address("https://example.com:443"),
            "example.com:443"
        );
    }

    #[test]
    fn test_component_status_serialize() {
        let status = ComponentStatus {
            name: "Gateway".to_string(),
            status: "Running".to_string(),
            details: "10.100.1.1:8080".to_string(),
        };

        let json = serde_json::to_string(&status).unwrap();
        assert!(json.contains("Gateway"));
        assert!(json.contains("Running"));
    }
}
