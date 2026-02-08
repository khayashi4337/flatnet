//! HTTP clients for Flatnet services
//!
//! This module provides HTTP clients for communicating with various Flatnet services.

pub mod gateway;
pub mod loki;
pub mod podman;

pub use gateway::GatewayClient;
pub use loki::LokiClient;
pub use podman::PodmanClient;
