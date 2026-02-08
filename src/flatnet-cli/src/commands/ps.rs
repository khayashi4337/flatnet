//! PS command implementation
//!
//! Lists containers with their Flatnet IPs.

use anyhow::Result;
use colored::Colorize;
use serde::Serialize;
use std::collections::HashMap;
use tabled::{settings::Style, Table, Tabled};

use crate::cli::PsArgs;
use crate::clients::gateway::GatewayClient;
use crate::clients::podman::{PodmanClient, PodmanContainer};
use crate::config::Config;

/// Container display information
#[derive(Debug, Clone, Serialize, Tabled)]
struct ContainerDisplay {
    #[tabled(rename = "CONTAINER ID")]
    id: String,

    #[tabled(rename = "NAME")]
    name: String,

    #[tabled(rename = "IMAGE")]
    image: String,

    #[tabled(rename = "FLATNET IP")]
    flatnet_ip: String,

    #[tabled(rename = "STATUS")]
    status: String,
}

/// JSON output structure
#[derive(Debug, Clone, Serialize)]
struct PsOutput {
    containers: Vec<ContainerDisplay>,
    total_containers: usize,
    flatnet_ips_allocated: usize,
}

/// Run the ps command
pub async fn run(args: PsArgs) -> Result<()> {
    let config = Config::load()?;

    // Get containers from Podman
    let podman = PodmanClient::new();
    let podman_containers = match podman.list_containers(args.all) {
        Ok(c) => c,
        Err(e) => {
            if !args.quiet && !args.json {
                eprintln!("{}: {}", "Error".red(), e);
                eprintln!(
                    "{}",
                    "Make sure Podman is installed and running.".dimmed()
                );
            }
            return Err(e);
        }
    };

    // Get Flatnet IPs from Gateway
    let flatnet_ips = get_flatnet_ips(&config).await;

    // Apply filters
    let filtered_containers = apply_filters(&podman_containers, &args.filter);

    // Build display list
    let display_containers = build_display_list(&filtered_containers, &flatnet_ips);

    // Count containers with Flatnet IPs
    let flatnet_count = display_containers
        .iter()
        .filter(|c| c.flatnet_ip != "-")
        .count();

    // Output
    if args.json {
        print_json(&display_containers, flatnet_count)?;
    } else if args.quiet {
        print_quiet(&display_containers);
    } else {
        print_table(&display_containers, flatnet_count, config.color_enabled());
    }

    Ok(())
}

/// Get Flatnet IPs from Gateway registry
async fn get_flatnet_ips(config: &Config) -> HashMap<String, String> {
    let mut ip_map = HashMap::new();

    match GatewayClient::new(config.gateway_url(), config.gateway_timeout()) {
        Ok(client) => match client.containers().await {
            Ok(containers) => {
                for container in containers {
                    // Map by both ID and name if available
                    ip_map.insert(container.id.clone(), container.ip.clone());
                    if let Some(ref name) = container.name {
                        ip_map.insert(name.clone(), container.ip.clone());
                    }
                }
            }
            Err(_) => {
                // Gateway not available, continue without Flatnet IPs
            }
        },
        Err(_) => {
            // Failed to create client
        }
    }

    ip_map
}

/// Apply filter to containers
fn apply_filters(containers: &[PodmanContainer], filter: &Option<String>) -> Vec<&PodmanContainer> {
    containers
        .iter()
        .filter(|c| {
            if let Some(ref f) = filter {
                // Parse filter: "name=value" or "id=value"
                if let Some((key, value)) = f.split_once('=') {
                    match key.to_lowercase().as_str() {
                        "name" => c.name().contains(value),
                        "id" => c.id.contains(value),
                        "image" => c.image.contains(value),
                        "status" | "state" => {
                            c.state.to_lowercase().contains(&value.to_lowercase())
                        }
                        _ => true,
                    }
                } else {
                    // If no key, search in name, id, and image
                    c.name().contains(f) || c.id.contains(f) || c.image.contains(f)
                }
            } else {
                true
            }
        })
        .collect()
}

/// Build display list combining Podman containers with Flatnet IPs
fn build_display_list(
    containers: &[&PodmanContainer],
    flatnet_ips: &HashMap<String, String>,
) -> Vec<ContainerDisplay> {
    containers
        .iter()
        .map(|c| {
            // Look up Flatnet IP by ID or name
            let flatnet_ip = flatnet_ips
                .get(&c.id)
                .or_else(|| flatnet_ips.get(c.name()))
                .or_else(|| {
                    // Try short ID
                    flatnet_ips.get(c.short_id())
                })
                .cloned()
                .unwrap_or_else(|| "-".to_string());

            ContainerDisplay {
                id: c.short_id().to_string(),
                name: c.name().to_string(),
                image: truncate_image(&c.image),
                flatnet_ip,
                status: c.status.clone(),
            }
        })
        .collect()
}

/// Truncate image name for display
fn truncate_image(image: &str) -> String {
    // Remove registry prefix if present
    let image = image
        .split('/')
        .last()
        .unwrap_or(image);

    // Truncate if too long (handle UTF-8 safely)
    let char_count = image.chars().count();
    if char_count > 25 {
        let truncated: String = image.chars().take(22).collect();
        format!("{}...", truncated)
    } else {
        image.to_string()
    }
}

/// Print output as JSON
fn print_json(containers: &[ContainerDisplay], flatnet_count: usize) -> Result<()> {
    let output = PsOutput {
        total_containers: containers.len(),
        flatnet_ips_allocated: flatnet_count,
        containers: containers.to_vec(),
    };

    let json = serde_json::to_string_pretty(&output)?;
    println!("{}", json);
    Ok(())
}

/// Print only container IDs (quiet mode)
fn print_quiet(containers: &[ContainerDisplay]) {
    for c in containers {
        println!("{}", c.id);
    }
}

/// Print formatted table
fn print_table(containers: &[ContainerDisplay], flatnet_count: usize, use_color: bool) {
    if containers.is_empty() {
        if use_color {
            println!("{}", "No containers found.".dimmed());
        } else {
            println!("No containers found.");
        }
        return;
    }

    // Build and print table
    let table = Table::new(containers)
        .with(Style::blank())
        .to_string();

    println!("{}", table);

    // Print summary
    println!();
    let summary = format!(
        "Total: {} containers, {} Flatnet IPs allocated",
        containers.len(),
        flatnet_count
    );

    if use_color {
        println!("{}", summary.dimmed());
    } else {
        println!("{}", summary);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_truncate_image() {
        assert_eq!(truncate_image("nginx:latest"), "nginx:latest");
        assert_eq!(
            truncate_image("docker.io/library/nginx:latest"),
            "nginx:latest"
        );
        assert_eq!(
            truncate_image("very-long-image-name-that-should-be-truncated:tag"),
            "very-long-image-name-t..."
        );
    }

    #[test]
    fn test_apply_filters() {
        let containers = vec![
            PodmanContainer {
                id: "abc123".to_string(),
                names: vec!["web".to_string()],
                image: "nginx".to_string(),
                state: "running".to_string(),
                status: "Up 1 hour".to_string(),
                created: None,
                networks: None,
            },
            PodmanContainer {
                id: "def456".to_string(),
                names: vec!["db".to_string()],
                image: "postgres".to_string(),
                state: "exited".to_string(),
                status: "Exited (0)".to_string(),
                created: None,
                networks: None,
            },
        ];

        // Filter by name
        let filter = Some("name=web".to_string());
        let filtered = apply_filters(&containers, &filter);
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].name(), "web");

        // Filter by state
        let filter = Some("state=running".to_string());
        let filtered = apply_filters(&containers, &filter);
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].name(), "web");

        // No filter
        let filtered = apply_filters(&containers, &None);
        assert_eq!(filtered.len(), 2);
    }
}
