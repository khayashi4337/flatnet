# Flatnet

NAT-free container networking.

> ⚠️ This project is under active development.

## What is Flatnet?

Flatnet は、WSL2 + Podman 環境における多段NAT問題を解消し、コンテナへの直接到達性を提供するネットワーキングツールです。

## Architecture

- [System Context](docs/architecture/context.md) - システム全体の文脈
- [Container Diagram](docs/architecture/container.md) - コンテナ構成

## Roadmap

[全体ロードマップ](docs/phases/README.md) を参照。

| Phase | 概要 | 状態 |
|-------|------|------|
| [Phase 1](docs/phases/phase-1/README.md) | Gateway 基盤 - OpenResty で NAT 地獄を解消 | 設計中 |
| Phase 2 | CNI Plugin - コンテナ管理の自動化 | 未着手 |
| Phase 3 | マルチホスト - 複数ホスト間通信 | 未着手 |
| Phase 4 | 本番運用準備 - 監視・セキュリティ | 未着手 |

## Tech Stack

- **CNI Plugin**: Rust
- **Gateway**: OpenResty (Nginx + Lua)
- **Container Runtime**: Podman
