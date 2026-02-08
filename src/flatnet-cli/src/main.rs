//! Flatnet CLI Tool
//!
//! A command-line interface for managing and monitoring the Flatnet system.

mod cli;
mod clients;
mod commands;
mod config;

use anyhow::Result;
use clap::Parser;
use cli::{Cli, Commands};

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Status(args) => commands::status::run(args).await?,
    }

    Ok(())
}
