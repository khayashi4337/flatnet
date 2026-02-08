# Flatnet

NAT-free container networking for WSL2 + Podman.

## What is Flatnet?

Flatnet は 3 つのコンポーネントを提供します：

1. **CNI Plugin** — Podman 用ネットワークプラグイン（WSL2 側）
2. **Gateway** — Host Windows 側の窓口（OpenResty）
3. **CLI** — システム管理ツール

これにより、WSL2 + Podman 環境の多段 NAT 問題を解消し、社内 LAN からコンテナへフラットに到達できます。

```
Before: 社内LAN → Windows → WSL2 → コンテナ（3段NAT）
After:  社内LAN → Gateway → コンテナ（フラット）
```

## Quick Start

### CLI のインストール

```bash
curl -fsSL https://raw.githubusercontent.com/khayashi4337/flatnet/master/scripts/install-cli.sh | bash
```

### 基本的な使い方

```bash
flatnet status    # システム状態を確認
flatnet doctor    # 診断を実行
flatnet ps        # コンテナ一覧
flatnet logs      # ログを確認
```

詳細は [CLI ドキュメント](docs/cli/README.md) を参照。

## Architecture

- [System Context](docs/architecture/context.md) - システム全体の文脈
- [Container Diagram](docs/architecture/container.md) - コンテナ構成

## Features

| Phase | 概要 | 状態 |
|-------|------|------|
| [Phase 1](docs/phases/phase-1/README.md) | Gateway 基盤 - OpenResty で NAT 地獄を解消 | 完了 |
| [Phase 2](docs/phases/phase-2/README.md) | CNI Plugin - コンテナ管理の自動化 | 完了 |
| [Phase 3](docs/phases/phase-3/README.md) | マルチホスト - 複数ホスト間通信 | 完了 |
| [Phase 4](docs/phases/phase-4/README.md) | 本番運用準備 - 監視・セキュリティ | 完了 |
| [Phase 5](docs/phases/phase-5/README.md) | CLI Tool - システム管理ツール | 完了 |

詳細は [ロードマップ](docs/phases/README.md) を参照。

## Tech Stack

- **CNI Plugin**: Rust
- **Gateway**: OpenResty (Nginx + Lua)
- **CLI**: Rust
- **Container Runtime**: Podman
- **Monitoring**: Prometheus, Grafana, Loki

## Documentation

- [CLI チュートリアル](docs/cli/getting-started.md) - 使い方を学ぶ
- [CLI リファレンス](docs/cli/README.md) - コマンド一覧
- [トラブルシューティング](docs/cli/troubleshooting.md) - 問題解決

## License

MIT
