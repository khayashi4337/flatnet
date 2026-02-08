//! Flatnet CLI Tool
//!
//! A command-line interface for managing and monitoring the Flatnet system.

mod checks;
mod cli;
mod clients;
mod commands;
mod config;

use anyhow::Result;
use clap::Parser;
use cli::{Cli, Commands};
use std::process::ExitCode;

#[tokio::main]
async fn main() -> Result<ExitCode> {
    let cli = Cli::parse();

    let exit_code = match cli.command {
        Commands::Status(args) => {
            commands::status::run(args).await?;
            ExitCode::SUCCESS
        }
        Commands::Doctor(args) => commands::doctor::run(args).await?,
    };

    Ok(exit_code)
}
