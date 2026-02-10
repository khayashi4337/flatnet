# Flatnet

NAT-free container networking for WSL2 + Podman.

## What is Flatnet?

WSL2 + Podman 環境で発生する多段 NAT 問題を解消し、社内 LAN からコンテナへフラットに到達できるようにします。

```
Before: 社内LAN → Windows → WSL2 → コンテナ（3段NAT）
After:  社内LAN → Gateway → コンテナ（フラット）
```

**クライアント側のインストール不要** — ブラウザさえあれば、隣の席の人があなたのコンテナにアクセスできます。

### Components

| Component | Description | Language |
|-----------|-------------|----------|
| **CNI Plugin** | Podman 用ネットワークプラグイン（WSL2 側） | Rust |
| **Gateway** | Host Windows 側の HTTP プロキシ | OpenResty |
| **CLI** | システム管理・診断ツール | Rust |

## Quick Start

```bash
# CLI のインストール
curl -fsSL https://raw.githubusercontent.com/khayashi4337/flatnet/master/scripts/install-cli.sh | bash

# 基本的な使い方
flatnet status    # システム状態を確認
flatnet doctor    # 診断を実行
flatnet ps        # コンテナ一覧
flatnet logs      # ログを確認
```

詳細は [CLI ドキュメント](docs/cli/README.md) を参照。

## CNI Implementation Highlights

「個人で CNI Plugin を実装した」と言っても信じてもらえないので、核心部分へのポインターを示します。

### Network Namespace 操作

[`src/flatnet-cni/src/netns.rs:46`](src/flatnet-cni/src/netns.rs#L46) — `setns()` システムコールでコンテナの network namespace に入る：

```rust
setns(target_ns.as_raw_fd(), CloneFlags::CLONE_NEWNET)
```

### Veth ペア作成

[`src/flatnet-cni/src/veth.rs:97-117`](src/flatnet-cni/src/veth.rs#L97) — rtnetlink で veth ペアを作成：

```rust
handle
    .link()
    .add()
    .veth(host_ifname.clone(), container_ifname.to_string())
    .execute()
    .await
```

### Container Namespace への移動

[`src/flatnet-cni/src/veth.rs:152-164`](src/flatnet-cni/src/veth.rs#L152) — veth の片側をコンテナの namespace に移動：

```rust
handle
    .link()
    .set(container_index)
    .setns_by_fd(netns_file.as_raw_fd())
    .execute()
    .await
```

### CNI ADD フロー

[`src/flatnet-cni/src/main.rs:165-185`](src/flatnet-cni/src/main.rs#L165) — CNI Spec 1.0.0 準拠の ADD コマンド実装：

1. Bridge の作成/確認
2. IP アドレスの割り当て（IPAM）
3. Veth ペアの作成
4. Host 側 veth を Bridge に接続
5. Container 側インターフェースの設定（namespace 内で）
6. Gateway への登録（マルチホスト対応）

## Similar Projects

- [slackhq/nebula-cni](https://github.com/slackhq/nebula-cni) — Slack による Nebula 用 CNI Plugin（Go 実装）

Flatnet との違い：nebula-cni はコンテナを Nebula ネットワークに参加させるもので、アクセス側にも Nebula クライアントが必要です。Flatnet は Gateway が HTTP を中継するため、クライアント側のインストールが不要です。

## Documentation

- [CLI チュートリアル](docs/cli/getting-started.md) — 使い方を学ぶ
- [CLI リファレンス](docs/cli/README.md) — コマンド一覧
- [トラブルシューティング](docs/cli/troubleshooting.md) — 問題解決
- [アーキテクチャ](docs/architecture/context.md) — システム設計

## License

MIT
