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
