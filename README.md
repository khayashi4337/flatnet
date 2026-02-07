# Flatnet

NAT-free container networking for WSL2 + Podman.

> ⚠️ This project is under active development.

## What is Flatnet?

Flatnet は 2 つのコンポーネントを提供します：

1. **CNI Plugin** — Podman 用ネットワークプラグイン（WSL2 側）
2. **Gateway** — Host Windows 側の窓口（OpenResty）

これにより、WSL2 + Podman 環境の多段 NAT 問題を解消し、社内 LAN からコンテナへフラットに到達できます。

```
Before: 社内LAN → Windows → WSL2 → コンテナ（3段NAT）
After:  社内LAN → Gateway → コンテナ（フラット）
```

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
