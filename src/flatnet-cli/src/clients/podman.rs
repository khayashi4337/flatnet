//! Podman client
//!
//! Client for interacting with Podman via CLI.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::process::Command;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command as TokioCommand;
use tokio::process::Stdio;

/// Container information from Podman
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PodmanContainer {
    /// Container ID (full)
    #[serde(rename = "Id")]
    pub id: String,

    /// Container names
    #[serde(rename = "Names", default)]
    pub names: Vec<String>,

    /// Image name
    #[serde(rename = "Image")]
    pub image: String,

    /// Container state
    #[serde(rename = "State")]
    pub state: String,

    /// Container status (human readable)
    #[serde(rename = "Status", default)]
    pub status: String,

    /// Creation timestamp
    #[serde(rename = "Created", default)]
    pub created: Option<i64>,

    /// Network settings
    #[serde(rename = "Networks", default)]
    pub networks: Option<Vec<String>>,
}

impl PodmanContainer {
    /// Get the short ID (first 12 characters)
    pub fn short_id(&self) -> &str {
        if self.id.len() >= 12 {
            &self.id[..12]
        } else {
            &self.id
        }
    }

    /// Get the primary name
    pub fn name(&self) -> &str {
        self.names.first().map(|s| s.as_str()).unwrap_or("")
    }

    /// Check if the container is running
    pub fn is_running(&self) -> bool {
        self.state.to_lowercase() == "running"
    }
}

/// Podman client for executing podman commands
#[derive(Debug, Clone, Default)]
pub struct PodmanClient;

impl PodmanClient {
    /// Create a new Podman client
    pub fn new() -> Self {
        Self
    }

    /// List containers
    ///
    /// If `all` is true, includes stopped containers.
    pub fn list_containers(&self, all: bool) -> Result<Vec<PodmanContainer>> {
        let mut cmd = Command::new("podman");
        cmd.arg("ps").arg("--format").arg("json");

        if all {
            cmd.arg("--all");
        }

        let output = cmd
            .output()
            .context("Failed to execute podman ps command")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            anyhow::bail!("podman ps failed: {}", stderr);
        }

        let stdout = String::from_utf8_lossy(&output.stdout);

        // Handle empty output
        if stdout.trim().is_empty() || stdout.trim() == "[]" {
            return Ok(Vec::new());
        }

        let containers: Vec<PodmanContainer> = serde_json::from_str(&stdout)
            .context("Failed to parse podman ps JSON output")?;

        Ok(containers)
    }

    /// Get logs from a container (synchronous, limited lines)
    pub fn get_logs(&self, container: &str, tail: Option<u32>, since: Option<&str>) -> Result<String> {
        let mut cmd = Command::new("podman");
        cmd.arg("logs");

        if let Some(n) = tail {
            cmd.arg("--tail").arg(n.to_string());
        }

        if let Some(s) = since {
            cmd.arg("--since").arg(s);
        }

        cmd.arg(container);

        let output = cmd
            .output()
            .context("Failed to execute podman logs command")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            anyhow::bail!("podman logs failed: {}", stderr);
        }

        // Podman logs outputs to both stdout and stderr
        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);

        // Combine both (stderr often has the actual logs for some containers)
        let combined = if stdout.is_empty() {
            stderr.to_string()
        } else if stderr.is_empty() {
            stdout.to_string()
        } else {
            format!("{}{}", stdout, stderr)
        };

        Ok(combined)
    }

    /// Follow container logs (streaming)
    pub async fn follow_logs<F>(&self, container: &str, mut callback: F) -> Result<()>
    where
        F: FnMut(&str),
    {
        let mut child = TokioCommand::new("podman")
            .args(["logs", "--follow", container])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .context("Failed to spawn podman logs --follow")?;

        // Read from both stdout and stderr
        if let Some(stdout) = child.stdout.take() {
            let reader = BufReader::new(stdout);
            let mut lines = reader.lines();

            while let Some(line) = lines.next_line().await? {
                callback(&line);
            }
        }

        child.wait().await?;
        Ok(())
    }

    /// Check if a container exists
    pub fn container_exists(&self, name_or_id: &str) -> bool {
        let output = Command::new("podman")
            .args(["inspect", name_or_id])
            .output();

        matches!(output, Ok(o) if o.status.success())
    }

    /// Check if Podman is available
    pub fn is_available() -> bool {
        Command::new("podman")
            .arg("--version")
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
    }

    /// Get Podman version
    pub fn version() -> Option<String> {
        Command::new("podman")
            .arg("--version")
            .output()
            .ok()
            .filter(|o| o.status.success())
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_podman_container() {
        let json = r#"{
            "Id": "abc123def456789012345678901234567890123456789012345678901234",
            "Names": ["my-container"],
            "Image": "nginx:latest",
            "State": "running",
            "Status": "Up 5 hours"
        }"#;

        let container: PodmanContainer = serde_json::from_str(json).unwrap();
        assert_eq!(container.short_id(), "abc123def456");
        assert_eq!(container.name(), "my-container");
        assert!(container.is_running());
    }

    #[test]
    fn test_parse_podman_container_array() {
        let json = r#"[
            {
                "Id": "abc123def456789",
                "Names": ["web"],
                "Image": "nginx:alpine",
                "State": "running",
                "Status": "Up 2 hours"
            },
            {
                "Id": "def456abc789012",
                "Names": ["db"],
                "Image": "postgres:16",
                "State": "exited",
                "Status": "Exited (0) 1 hour ago"
            }
        ]"#;

        let containers: Vec<PodmanContainer> = serde_json::from_str(json).unwrap();
        assert_eq!(containers.len(), 2);
        assert!(containers[0].is_running());
        assert!(!containers[1].is_running());
    }

    #[test]
    fn test_short_id() {
        let container = PodmanContainer {
            id: "abc123def456789012345678901234567890".to_string(),
            names: vec!["test".to_string()],
            image: "nginx".to_string(),
            state: "running".to_string(),
            status: "Up".to_string(),
            created: None,
            networks: None,
        };

        assert_eq!(container.short_id(), "abc123def456");
    }
}
