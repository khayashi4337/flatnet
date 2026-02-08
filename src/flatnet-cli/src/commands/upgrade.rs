//! Upgrade command implementation
//!
//! Handles self-upgrading the CLI to newer versions.

use anyhow::{bail, Context, Result};
use colored::Colorize;
use serde::Deserialize;
use std::env;
use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::time::Duration;

use crate::cli::UpgradeArgs;
use crate::config::Config;

/// GitHub repository for releases
const GITHUB_REPO: &str = "khayashi4337/flatnet";

/// GitHub API base URL
const GITHUB_API: &str = "https://api.github.com";

/// GitHub release information
#[derive(Debug, Deserialize)]
struct GitHubRelease {
    tag_name: String,
    assets: Vec<GitHubAsset>,
}

/// GitHub release asset
#[derive(Debug, Deserialize)]
struct GitHubAsset {
    name: String,
    browser_download_url: String,
}

/// Run the upgrade command
pub async fn run(args: UpgradeArgs) -> Result<()> {
    let config = Config::load()?;
    let use_color = config.color_enabled();

    // Get current version
    let current_version = env!("CARGO_PKG_VERSION");

    // Determine target version
    let target_version = if let Some(ref version) = args.version {
        version.trim_start_matches('v').to_string()
    } else {
        get_latest_version().await?
    };

    // Display version information
    if use_color {
        println!();
        println!("Current version: {}", current_version.cyan());
        println!("Latest version:  {}", target_version.cyan());
    } else {
        println!();
        println!("Current version: {}", current_version);
        println!("Latest version:  {}", target_version);
    }

    // Compare versions
    if current_version == target_version {
        println!();
        if use_color {
            println!("{}", "Already up to date!".green());
        } else {
            println!("Already up to date!");
        }
        return Ok(());
    }

    // Check-only mode
    if args.check {
        println!();
        if use_color {
            println!(
                "{}",
                format!("Update available: v{} -> v{}", current_version, target_version).yellow()
            );
            println!();
            println!("Run '{}' to upgrade.", "flatnet upgrade".bold());
        } else {
            println!(
                "Update available: v{} -> v{}",
                current_version, target_version
            );
            println!();
            println!("Run 'flatnet upgrade' to upgrade.");
        }
        return Ok(());
    }

    // Perform upgrade
    println!();
    if use_color {
        println!(
            "{}",
            format!("Downloading flatnet v{}...", target_version).bold()
        );
    } else {
        println!("Downloading flatnet v{}...", target_version);
    }

    let binary = download_binary(&target_version, use_color).await?;

    // Get current executable path
    let current_exe = env::current_exe().context("Failed to get current executable path")?;

    // Replace binary atomically
    replace_binary(&current_exe, &binary)?;

    println!();
    if use_color {
        println!(
            "{}",
            format!("Upgraded successfully to v{}!", target_version).green()
        );
        println!();
        println!(
            "Run '{}' to confirm.",
            "flatnet --version".bold()
        );
    } else {
        println!("Upgraded successfully to v{}!", target_version);
        println!();
        println!("Run 'flatnet --version' to confirm.");
    }

    Ok(())
}

/// Get the latest version from GitHub releases
async fn get_latest_version() -> Result<String> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .user_agent("flatnet-cli")
        .build()
        .context("Failed to create HTTP client")?;

    let url = format!("{}/repos/{}/releases/latest", GITHUB_API, GITHUB_REPO);

    let response = client
        .get(&url)
        .send()
        .await
        .context("Failed to fetch latest release from GitHub")?;

    if !response.status().is_success() {
        let status = response.status();
        if status.as_u16() == 404 {
            bail!("No releases found. Check https://github.com/{}/releases", GITHUB_REPO);
        }
        bail!("GitHub API returned error: {}", status);
    }

    let release: GitHubRelease = response
        .json()
        .await
        .context("Failed to parse GitHub release response")?;

    // Extract version from tag name (supports both "cli-v1.0.0" and "v1.0.0" formats)
    let version = release
        .tag_name
        .trim_start_matches("cli-")
        .trim_start_matches('v')
        .to_string();

    Ok(version)
}

/// Download binary for the current platform
async fn download_binary(version: &str, use_color: bool) -> Result<Vec<u8>> {
    let platform = detect_platform()?;
    let asset_name = format!("flatnet-{}", platform);

    // Get release info
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(120))
        .user_agent("flatnet-cli")
        .build()
        .context("Failed to create HTTP client")?;

    let url = format!(
        "{}/repos/{}/releases/tags/cli-v{}",
        GITHUB_API, GITHUB_REPO, version
    );

    let response = client
        .get(&url)
        .send()
        .await
        .context("Failed to fetch release info from GitHub")?;

    if !response.status().is_success() {
        bail!("Release v{} not found", version);
    }

    let release: GitHubRelease = response
        .json()
        .await
        .context("Failed to parse release info")?;

    // Find matching asset
    let asset = release
        .assets
        .iter()
        .find(|a| a.name == asset_name)
        .ok_or_else(|| {
            anyhow::anyhow!(
                "No binary found for platform '{}' in release v{}",
                platform,
                version
            )
        })?;

    // Download binary with progress
    download_with_progress(&asset.browser_download_url, use_color).await
}

/// Download file with progress indicator
async fn download_with_progress(url: &str, use_color: bool) -> Result<Vec<u8>> {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(300))
        .user_agent("flatnet-cli")
        .build()
        .context("Failed to create HTTP client")?;

    let response = client
        .get(url)
        .send()
        .await
        .context("Failed to start download")?;

    if !response.status().is_success() {
        bail!("Download failed: {}", response.status());
    }

    let total_size = response.content_length();
    let mut downloaded: u64 = 0;
    let mut data = Vec::new();

    let mut stream = response;

    // Progress bar width
    const BAR_WIDTH: usize = 40;

    while let Some(chunk) = stream.chunk().await.context("Error while downloading")? {
        data.extend_from_slice(&chunk);
        downloaded += chunk.len() as u64;

        // Update progress
        if let Some(total) = total_size {
            let progress = downloaded as f64 / total as f64;
            let filled = (progress * BAR_WIDTH as f64) as usize;
            let empty = BAR_WIDTH - filled;

            let bar = format!(
                "[{}{}] {:>3}%",
                "#".repeat(filled),
                "-".repeat(empty),
                (progress * 100.0) as u32
            );

            if use_color {
                print!("\r{}", bar.dimmed());
            } else {
                print!("\r{}", bar);
            }
            io::stdout().flush().ok();
        }
    }

    // Clear progress line
    print!("\r{}\r", " ".repeat(BAR_WIDTH + 10));
    io::stdout().flush().ok();

    if use_color {
        println!("{}", "Download complete.".green());
    } else {
        println!("Download complete.");
    }

    Ok(data)
}

/// Detect current platform
fn detect_platform() -> Result<String> {
    let os = if cfg!(target_os = "linux") {
        "linux"
    } else if cfg!(target_os = "macos") {
        "darwin"
    } else {
        bail!("Unsupported operating system");
    };

    let arch = if cfg!(target_arch = "x86_64") {
        "x86_64"
    } else if cfg!(target_arch = "aarch64") {
        "aarch64"
    } else {
        bail!("Unsupported architecture");
    };

    Ok(format!("{}-{}", os, arch))
}

/// Replace the current binary atomically
fn replace_binary(path: &Path, new_binary: &[u8]) -> Result<()> {
    // Create temporary file in the same directory (for atomic rename)
    let parent = path.parent().context("Invalid executable path")?;
    let tmp_path = parent.join(".flatnet.tmp");

    // Write new binary to temp file
    fs::write(&tmp_path, new_binary)
        .with_context(|| format!("Failed to write temporary file: {}", tmp_path.display()))?;

    // Set executable permissions
    let mut perms = fs::metadata(&tmp_path)
        .context("Failed to get temp file metadata")?
        .permissions();
    perms.set_mode(0o755);
    fs::set_permissions(&tmp_path, perms).context("Failed to set executable permissions")?;

    // Atomic rename
    fs::rename(&tmp_path, path).with_context(|| {
        // Clean up temp file on error
        let _ = fs::remove_file(&tmp_path);
        format!("Failed to replace binary: {}", path.display())
    })?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_platform() {
        let platform = detect_platform().unwrap();
        assert!(platform.contains('-'));
        // Should match current platform
        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        assert_eq!(platform, "linux-x86_64");
    }

    #[test]
    fn test_current_version() {
        let version = env!("CARGO_PKG_VERSION");
        assert!(!version.is_empty());
    }
}
