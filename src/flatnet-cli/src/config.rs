//! Configuration management
//!
//! Handles loading configuration from files and environment variables.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::env;
use std::fs;
use std::path::PathBuf;

/// Default Gateway URL for WSL2 environment
const DEFAULT_GATEWAY_PORT: u16 = 8080;

/// Configuration for the Flatnet CLI
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Gateway configuration
    #[serde(default)]
    pub gateway: GatewayConfig,

    /// Monitoring services configuration
    #[serde(default)]
    pub monitoring: MonitoringConfig,

    /// Display settings
    #[serde(default)]
    pub display: DisplayConfig,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            gateway: GatewayConfig::default(),
            monitoring: MonitoringConfig::default(),
            display: DisplayConfig::default(),
        }
    }
}

/// Gateway configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GatewayConfig {
    /// Gateway API URL
    pub url: Option<String>,

    /// Request timeout in seconds
    #[serde(default = "default_timeout")]
    pub timeout_secs: u64,
}

fn default_timeout() -> u64 {
    5
}

impl Default for GatewayConfig {
    fn default() -> Self {
        Self {
            url: None,
            timeout_secs: default_timeout(),
        }
    }
}

/// Monitoring services configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MonitoringConfig {
    /// Prometheus URL
    #[serde(default = "default_prometheus_url")]
    pub prometheus_url: String,

    /// Grafana URL
    #[serde(default = "default_grafana_url")]
    pub grafana_url: String,

    /// Loki URL
    #[serde(default = "default_loki_url")]
    pub loki_url: String,
}

fn default_prometheus_url() -> String {
    "http://localhost:9090".to_string()
}

fn default_grafana_url() -> String {
    "http://localhost:3000".to_string()
}

fn default_loki_url() -> String {
    "http://localhost:3100".to_string()
}

impl Default for MonitoringConfig {
    fn default() -> Self {
        Self {
            prometheus_url: default_prometheus_url(),
            grafana_url: default_grafana_url(),
            loki_url: default_loki_url(),
        }
    }
}

/// Display configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DisplayConfig {
    /// Enable colored output
    #[serde(default = "default_color")]
    pub color: bool,
}

fn default_color() -> bool {
    true
}

impl Default for DisplayConfig {
    fn default() -> Self {
        Self {
            color: default_color(),
        }
    }
}

impl Config {
    /// Load configuration from file and environment variables
    ///
    /// Priority (highest to lowest):
    /// 1. Environment variables (FLATNET_GATEWAY_URL)
    /// 2. Configuration file (~/.config/flatnet/config.toml)
    /// 3. Default values (auto-detect Windows host IP)
    pub fn load() -> Result<Self> {
        let mut config = Self::load_from_file().unwrap_or_default();

        // Override with environment variables
        config.apply_env_overrides();

        // Apply default Gateway URL if not set
        if config.gateway.url.is_none() {
            config.gateway.url = Some(Self::detect_gateway_url());
        }

        Ok(config)
    }

    /// Load configuration from the config file
    fn load_from_file() -> Result<Self> {
        let config_path = Self::config_path()?;

        if !config_path.exists() {
            return Ok(Self::default());
        }

        let content = fs::read_to_string(&config_path)
            .with_context(|| format!("Failed to read config file: {}", config_path.display()))?;

        let config: Config = toml::from_str(&content)
            .with_context(|| format!("Failed to parse config file: {}", config_path.display()))?;

        Ok(config)
    }

    /// Apply environment variable overrides
    fn apply_env_overrides(&mut self) {
        if let Ok(url) = env::var("FLATNET_GATEWAY_URL") {
            self.gateway.url = Some(url);
        }

        if let Ok(timeout) = env::var("FLATNET_GATEWAY_TIMEOUT") {
            if let Ok(secs) = timeout.parse() {
                self.gateway.timeout_secs = secs;
            }
        }

        if let Ok(url) = env::var("FLATNET_PROMETHEUS_URL") {
            self.monitoring.prometheus_url = url;
        }

        if let Ok(url) = env::var("FLATNET_GRAFANA_URL") {
            self.monitoring.grafana_url = url;
        }

        if let Ok(url) = env::var("FLATNET_LOKI_URL") {
            self.monitoring.loki_url = url;
        }

        // NO_COLOR standard takes precedence (https://no-color.org/)
        if env::var("NO_COLOR").is_ok() {
            self.display.color = false;
        } else if let Ok(color) = env::var("FLATNET_COLOR") {
            self.display.color = color != "0" && color.to_lowercase() != "false";
        }
    }

    /// Get the configuration file path
    fn config_path() -> Result<PathBuf> {
        let config_dir = dirs::config_dir()
            .context("Could not determine config directory")?
            .join("flatnet");

        Ok(config_dir.join("config.toml"))
    }

    /// Detect the Gateway URL from WSL2 environment
    ///
    /// In WSL2, the Windows host IP can be found in /etc/resolv.conf
    fn detect_gateway_url() -> String {
        if let Some(windows_ip) = get_windows_ip() {
            format!("http://{}:{}", windows_ip, DEFAULT_GATEWAY_PORT)
        } else {
            // Fallback to localhost
            format!("http://localhost:{}", DEFAULT_GATEWAY_PORT)
        }
    }

    /// Get the Gateway URL
    pub fn gateway_url(&self) -> &str {
        self.gateway.url.as_deref().unwrap_or("http://localhost:8080")
    }

    /// Get the Gateway timeout duration
    pub fn gateway_timeout(&self) -> std::time::Duration {
        std::time::Duration::from_secs(self.gateway.timeout_secs)
    }

    /// Check if color output is enabled
    pub fn color_enabled(&self) -> bool {
        self.display.color
    }
}

/// Get the Windows host IP from WSL2 /etc/resolv.conf
///
/// In WSL2, the nameserver in /etc/resolv.conf points to the Windows host.
fn get_windows_ip() -> Option<String> {
    let content = fs::read_to_string("/etc/resolv.conf").ok()?;

    for line in content.lines() {
        let line = line.trim();
        if line.starts_with("nameserver") {
            // Parse: "nameserver 172.x.x.x"
            if let Some(ip) = line.split_whitespace().nth(1) {
                // Validate it looks like an IP address
                if ip.parse::<std::net::Ipv4Addr>().is_ok() {
                    return Some(ip.to_string());
                }
            }
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert!(config.gateway.url.is_none());
        assert_eq!(config.gateway.timeout_secs, 5);
        assert!(config.display.color);
    }

    #[test]
    fn test_parse_config() {
        let toml_content = r#"
[gateway]
url = "http://10.100.1.1:8080"
timeout_secs = 10

[monitoring]
prometheus_url = "http://localhost:9090"
grafana_url = "http://localhost:3000"

[display]
color = false
"#;

        let config: Config = toml::from_str(toml_content).unwrap();
        assert_eq!(
            config.gateway.url,
            Some("http://10.100.1.1:8080".to_string())
        );
        assert_eq!(config.gateway.timeout_secs, 10);
        assert!(!config.display.color);
    }
}
