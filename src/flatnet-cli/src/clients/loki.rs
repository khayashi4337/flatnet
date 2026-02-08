//! Loki client
//!
//! HTTP client for querying logs from Loki.

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use thiserror::Error;

/// Errors that can occur when communicating with Loki
#[derive(Error, Debug)]
pub enum LokiError {
    #[error("Loki connection failed: {0}")]
    ConnectionFailed(String),

    #[error("Loki request failed: {0}")]
    RequestFailed(String),

    #[error("Loki returned unexpected response: {0}")]
    InvalidResponse(String),

    #[error("Loki timeout")]
    Timeout,
}

impl LokiError {
    /// Convert a reqwest error to a LokiError
    fn from_reqwest(e: reqwest::Error) -> Self {
        if e.is_timeout() {
            LokiError::Timeout
        } else if e.is_connect() {
            LokiError::ConnectionFailed(e.to_string())
        } else {
            LokiError::RequestFailed(e.to_string())
        }
    }
}

/// A single log entry from Loki
#[derive(Debug, Clone, Serialize)]
pub struct LogEntry {
    /// Timestamp (nanoseconds since epoch)
    pub timestamp: i64,

    /// Log line content
    pub line: String,

    /// Labels associated with the log
    pub labels: std::collections::HashMap<String, String>,
}

/// Loki API client
#[derive(Debug, Clone)]
pub struct LokiClient {
    client: Client,
    base_url: String,
}

impl LokiClient {
    /// Create a new Loki client
    pub fn new(base_url: &str, timeout: Duration) -> Result<Self> {
        let client = Client::builder()
            .timeout(timeout)
            .build()
            .context("Failed to create HTTP client")?;

        Ok(Self {
            client,
            base_url: base_url.trim_end_matches('/').to_string(),
        })
    }

    /// Check if Loki is ready
    pub async fn is_ready(&self) -> bool {
        let url = format!("{}/ready", self.base_url);
        matches!(
            self.client.get(&url).send().await,
            Ok(resp) if resp.status().is_success()
        )
    }

    /// Query logs using LogQL
    ///
    /// # Arguments
    /// * `query` - LogQL query string (e.g., `{job="gateway"}`)
    /// * `limit` - Maximum number of entries to return
    /// * `since` - Duration string (e.g., "1h", "30m")
    pub async fn query_logs(
        &self,
        query: &str,
        limit: u32,
        since: Option<&str>,
    ) -> Result<Vec<LogEntry>, LokiError> {
        let url = format!("{}/loki/api/v1/query_range", self.base_url);

        // Calculate time range
        let end = chrono::Utc::now();
        let start = if let Some(since_str) = since {
            let duration = parse_duration(since_str).unwrap_or(3600); // default 1h
            end - chrono::Duration::seconds(duration as i64)
        } else {
            end - chrono::Duration::hours(1)
        };

        let start_ns = start.timestamp_nanos_opt().unwrap_or(0);
        let end_ns = end.timestamp_nanos_opt().unwrap_or(0);

        let response = self
            .client
            .get(&url)
            .query(&[
                ("query", query),
                ("start", &start_ns.to_string()),
                ("end", &end_ns.to_string()),
                ("limit", &limit.to_string()),
                ("direction", "backward"),
            ])
            .send()
            .await
            .map_err(LokiError::from_reqwest)?;

        if !response.status().is_success() {
            return Err(LokiError::RequestFailed(format!(
                "HTTP {}",
                response.status()
            )));
        }

        let body: LokiQueryResponse = response
            .json()
            .await
            .map_err(|e| LokiError::InvalidResponse(e.to_string()))?;

        Ok(parse_loki_response(body))
    }

    /// Query logs for a specific job
    pub async fn query_job_logs(
        &self,
        job: &str,
        limit: u32,
        since: Option<&str>,
    ) -> Result<Vec<LogEntry>, LokiError> {
        let query = format!("{{job=\"{}\"}}", job);
        self.query_logs(&query, limit, since).await
    }

    /// Query logs for a specific container
    pub async fn query_container_logs(
        &self,
        container: &str,
        limit: u32,
        since: Option<&str>,
    ) -> Result<Vec<LogEntry>, LokiError> {
        let query = format!("{{container=\"{}\"}}", container);
        self.query_logs(&query, limit, since).await
    }

    /// Query logs with a grep filter
    pub async fn query_logs_with_filter(
        &self,
        query: &str,
        filter: &str,
        limit: u32,
        since: Option<&str>,
    ) -> Result<Vec<LogEntry>, LokiError> {
        let filtered_query = format!("{} |~ \"{}\"", query, filter);
        self.query_logs(&filtered_query, limit, since).await
    }
}

/// Loki query response structure
#[derive(Debug, Deserialize)]
struct LokiQueryResponse {
    status: String,
    data: LokiQueryData,
}

#[derive(Debug, Deserialize)]
struct LokiQueryData {
    #[serde(rename = "resultType")]
    result_type: String,
    result: Vec<LokiStream>,
}

#[derive(Debug, Deserialize)]
struct LokiStream {
    stream: std::collections::HashMap<String, String>,
    values: Vec<(String, String)>, // (timestamp, line)
}

/// Parse Loki response into LogEntry vec
fn parse_loki_response(response: LokiQueryResponse) -> Vec<LogEntry> {
    let mut entries = Vec::new();

    for stream in response.data.result {
        for (timestamp_str, line) in stream.values {
            let timestamp = timestamp_str.parse::<i64>().unwrap_or(0);
            entries.push(LogEntry {
                timestamp,
                line,
                labels: stream.stream.clone(),
            });
        }
    }

    // Sort by timestamp (oldest first for display)
    entries.sort_by_key(|e| e.timestamp);
    entries
}

/// Parse duration string to seconds
///
/// Supports: "30s", "5m", "2h", "1d"
fn parse_duration(s: &str) -> Option<u64> {
    let s = s.trim();
    if s.is_empty() {
        return None;
    }

    let (num_str, unit) = s.split_at(s.len() - 1);
    let num: u64 = num_str.parse().ok()?;

    let multiplier = match unit {
        "s" => 1,
        "m" => 60,
        "h" => 3600,
        "d" => 86400,
        _ => return None,
    };

    Some(num * multiplier)
}

/// Map component names to Loki job names
pub fn component_to_job(component: &str) -> Option<&'static str> {
    match component.to_lowercase().as_str() {
        "gateway" => Some("gateway"),
        "cni" => Some("flatnet-cni"),
        "prometheus" => Some("prometheus"),
        "grafana" => Some("grafana"),
        "loki" => Some("loki"),
        _ => None,
    }
}

/// Check if a name is a known component
pub fn is_known_component(name: &str) -> bool {
    component_to_job(name).is_some()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_duration() {
        assert_eq!(parse_duration("30s"), Some(30));
        assert_eq!(parse_duration("5m"), Some(300));
        assert_eq!(parse_duration("2h"), Some(7200));
        assert_eq!(parse_duration("1d"), Some(86400));
        assert_eq!(parse_duration("invalid"), None);
        assert_eq!(parse_duration(""), None);
    }

    #[test]
    fn test_component_to_job() {
        assert_eq!(component_to_job("gateway"), Some("gateway"));
        assert_eq!(component_to_job("Gateway"), Some("gateway"));
        assert_eq!(component_to_job("cni"), Some("flatnet-cni"));
        assert_eq!(component_to_job("unknown"), None);
    }

    #[test]
    fn test_is_known_component() {
        assert!(is_known_component("gateway"));
        assert!(is_known_component("prometheus"));
        assert!(!is_known_component("my-container"));
    }

    #[test]
    fn test_parse_loki_response() {
        let json = r#"{
            "status": "success",
            "data": {
                "resultType": "streams",
                "result": [
                    {
                        "stream": {"job": "gateway"},
                        "values": [
                            ["1700000000000000000", "log line 1"],
                            ["1700000001000000000", "log line 2"]
                        ]
                    }
                ]
            }
        }"#;

        let response: LokiQueryResponse = serde_json::from_str(json).unwrap();
        let entries = parse_loki_response(response);

        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].line, "log line 1");
        assert_eq!(entries[1].line, "log line 2");
    }
}
