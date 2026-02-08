//! CLI definition using clap
//!
//! Defines the command-line interface structure for the Flatnet CLI tool.

use clap::{Parser, Subcommand};

/// Flatnet CLI - System management tool for Flatnet
#[derive(Parser, Debug)]
#[command(name = "flatnet")]
#[command(author = "Flatnet Team")]
#[command(version)]
#[command(about = "Flatnet system management CLI", long_about = None)]
#[command(propagate_version = true)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

/// Available commands
#[derive(Subcommand, Debug)]
pub enum Commands {
    /// Display system status
    #[command(about = "Display Flatnet system status")]
    Status(StatusArgs),

    /// Run system diagnostics
    #[command(about = "Run system diagnostics and check for issues")]
    Doctor(DoctorArgs),

    /// List containers with Flatnet IPs
    #[command(about = "List containers with Flatnet IPs")]
    Ps(PsArgs),

    /// Show logs from components or containers
    #[command(about = "Show logs from Flatnet components or containers")]
    Logs(LogsArgs),

    /// Upgrade CLI to latest version
    #[command(about = "Upgrade flatnet CLI to latest version")]
    Upgrade(UpgradeArgs),
}

/// Arguments for the status command
#[derive(Parser, Debug)]
pub struct StatusArgs {
    /// Output in JSON format
    #[arg(long, help = "Output status in JSON format")]
    pub json: bool,

    /// Watch mode - continuously update status
    #[arg(long, short, help = "Continuously update status display")]
    pub watch: bool,

    /// Watch interval in seconds (default: 2)
    #[arg(long, default_value = "2", value_name = "SECS", help = "Interval between updates in watch mode")]
    pub interval: u64,
}

/// Arguments for the doctor command
#[derive(Parser, Debug)]
pub struct DoctorArgs {
    /// Output in JSON format
    #[arg(long, help = "Output results in JSON format")]
    pub json: bool,

    /// Quiet mode - only show issues (for CI)
    #[arg(long, short, help = "Only show warnings and errors")]
    pub quiet: bool,

    /// Verbose mode - show detailed information
    #[arg(long, short, help = "Show detailed diagnostic information")]
    pub verbose: bool,
}

/// Arguments for the ps command
#[derive(Parser, Debug)]
pub struct PsArgs {
    /// Show all containers (including stopped)
    #[arg(long, short, help = "Show all containers including stopped ones")]
    pub all: bool,

    /// Filter containers (e.g., name=foo, id=abc, image=nginx)
    #[arg(long, short, help = "Filter containers by name, id, or image")]
    pub filter: Option<String>,

    /// Output in JSON format
    #[arg(long, help = "Output in JSON format")]
    pub json: bool,

    /// Only show container IDs
    #[arg(long, short, help = "Only display container IDs")]
    pub quiet: bool,
}

/// Arguments for the logs command
#[derive(Parser, Debug)]
pub struct LogsArgs {
    /// Component or container name
    #[arg(help = "Component (gateway, cni, prometheus, grafana, loki) or container name")]
    pub target: String,

    /// Number of lines to show from the end
    #[arg(long, short = 'n', help = "Number of lines to show from the end")]
    pub tail: Option<u32>,

    /// Follow log output
    #[arg(long, short, help = "Follow log output in real-time")]
    pub follow: bool,

    /// Show logs since duration (e.g., 1h, 30m, 2d)
    #[arg(long, help = "Show logs since duration (e.g., 1h, 30m, 2d)")]
    pub since: Option<String>,

    /// Filter logs by pattern
    #[arg(long, help = "Filter logs by pattern (grep)")]
    pub grep: Option<String>,

    /// Output in JSON format
    #[arg(long, help = "Output in JSON format")]
    pub json: bool,
}

/// Arguments for the upgrade command
#[derive(Parser, Debug)]
pub struct UpgradeArgs {
    /// Check for updates without installing
    #[arg(long, help = "Check for updates without installing")]
    pub check: bool,

    /// Upgrade to a specific version
    #[arg(long, value_name = "VERSION", help = "Upgrade to a specific version (e.g., 0.2.0)")]
    pub version: Option<String>,
}
