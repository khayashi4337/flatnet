# Flatnet

NAT-free container networking.

> ⚠️ This project is under active development.

## What is Flatnet?

Flatnet は、WSL2 + Podman 環境における多段NAT問題を解消し、コンテナへの直接到達性を提供するネットワーキングツールです。

## Architecture

- [System Context](docs/architecture/context.md) - システム全体の文脈
- [Container Diagram](docs/architecture/container.md) - コンテナ構成

## Roadmap

- [Phase 1: 基盤構築](docs/phases/phase-1/README.md)

## Tech Stack

- **CNI Plugin**: Rust
- **Gateway**: OpenResty (Nginx + Lua)
- **Container Runtime**: Podman
