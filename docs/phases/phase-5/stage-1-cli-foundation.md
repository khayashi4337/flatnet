# Stage 1: CLI 基盤と status コマンド

## 概要

Flatnet CLI ツールの基盤を構築し、最初のコマンドとして `flatnet status` を実装する。システム全体の状態を一目で確認できるようにする。

## ブランチ戦略

- ブランチ名: `phase5/stage-1-cli-foundation`
- マージ先: `master`

## インプット（前提条件）

- Phase 1-4 が完了している
- Gateway API が稼働している（:8080）
- Rust 開発環境が整っている

## 目標

- Rust CLI プロジェクトをセットアップする
- `flatnet status` コマンドを実装する
- Gateway/CNI/Monitoring の状態を取得・表示する

## 手段

- clap クレートで CLI を構築
- reqwest で HTTP API を呼び出し
- colored/tabled でフォーマット出力

---

## Sub-stages

### Sub-stage 1.1: プロジェクトセットアップ

**内容:**
- Cargo プロジェクト作成
- 依存関係の設定
- 基本的な CLI 構造

**ディレクトリ構成:**
```
src/flatnet-cli/
├── Cargo.toml
├── src/
│   ├── main.rs
│   ├── cli.rs
│   ├── commands/
│   │   └── mod.rs
│   ├── clients/
│   │   └── mod.rs
│   └── config.rs
```

**Cargo.toml:**
```toml
[package]
name = "flatnet-cli"
version = "0.1.0"
edition = "2021"
description = "Flatnet CLI tool for system management"
authors = ["Flatnet Team"]

[[bin]]
name = "flatnet"
path = "src/main.rs"

[dependencies]
clap = { version = "4", features = ["derive", "color", "env"] }
tokio = { version = "1", features = ["full"] }
reqwest = { version = "0.11", features = ["json"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
colored = "2"
tabled = "0.14"
anyhow = "1"
thiserror = "1"
dirs = "5"
toml = "0.8"

[dev-dependencies]
assert_cmd = "2"
predicates = "3"
```

**完了条件:**
- [ ] `cargo build` が成功する
- [ ] `flatnet --help` が動作する
- [ ] `flatnet --version` が動作する

---

### Sub-stage 1.2: 設定管理

**内容:**
- 設定ファイル読み込み（~/.config/flatnet/config.toml）
- 環境変数によるオーバーライド
- デフォルト値の設定

**設定ファイル例:**
```toml
# ~/.config/flatnet/config.toml

[gateway]
url = "http://10.100.1.1:8080"
# または環境変数 FLATNET_GATEWAY_URL

[monitoring]
prometheus_url = "http://localhost:9090"
grafana_url = "http://localhost:3000"

[display]
color = true
```

**完了条件:**
- [ ] 設定ファイルが読み込める
- [ ] 環境変数でオーバーライドできる
- [ ] デフォルト値が適用される

---

### Sub-stage 1.3: Gateway クライアント

**内容:**
- Gateway API への HTTP クライアント実装
- `/api/status` エンドポイントの呼び出し
- `/api/containers` エンドポイントの呼び出し
- エラーハンドリング

**API エンドポイント:**
```
GET /api/status        → システム状態
GET /api/containers    → コンテナ一覧
GET /api/health        → ヘルスチェック
```

**完了条件:**
- [ ] Gateway API に接続できる
- [ ] レスポンスをパースできる
- [ ] 接続エラーを適切に処理できる

---

### Sub-stage 1.4: status コマンド実装

**内容:**
- `flatnet status` コマンドの実装
- 各コンポーネントの状態取得
- カラー出力とフォーマット

**出力例:**
```
$ flatnet status

╭─────────────────────────────────────────────────╮
│ Flatnet System Status                           │
├─────────────────────────────────────────────────┤
│ Gateway      ● Running    10.100.1.1:80         │
│ CNI Plugin   ● Ready      10.87.1.0/24 (3 IPs)  │
│ Nebula       ● Connected  2 peers               │
│ Prometheus   ● Running    :9090                 │
│ Grafana      ● Running    :3000                 │
│ Loki         ● Running    :3100                 │
╰─────────────────────────────────────────────────╯

Containers: 3 running
Uptime: 5d 12h 34m
```

**オプション:**
```
flatnet status           # デフォルト表示
flatnet status --json    # JSON 出力
flatnet status --watch   # リアルタイム更新
```

**完了条件:**
- [ ] `flatnet status` が動作する
- [ ] すべてのコンポーネント状態が表示される
- [ ] カラー出力が正しく表示される
- [ ] `--json` オプションが動作する

---

## 成果物

| 種別 | パス | 説明 |
|------|------|------|
| ソースコード | `src/flatnet-cli/` | CLI ツール |
| バイナリ | `target/release/flatnet` | ビルド成果物 |

## 完了条件

- [ ] `cargo build --release` が成功する
- [ ] `flatnet --help` が動作する
- [ ] `flatnet --version` が動作する
- [ ] `flatnet status` でシステム状態が表示される
- [ ] Gateway 未起動時にエラーメッセージが表示される

## 技術メモ

### Windows Gateway への接続

WSL2 から Windows 上の Gateway にアクセスするには:

```rust
// WSL2 から Windows ホストの IP を取得
fn get_windows_ip() -> Option<String> {
    // /etc/resolv.conf の nameserver を読み取る
    let content = std::fs::read_to_string("/etc/resolv.conf").ok()?;
    for line in content.lines() {
        if line.starts_with("nameserver") {
            return line.split_whitespace().nth(1).map(String::from);
        }
    }
    None
}
```

### 非同期処理

```rust
#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Status(args) => commands::status::run(args).await?,
        // ...
    }

    Ok(())
}
```

## 依存関係

- Phase 1-4 完了

## リスク

- Gateway API が変更された場合の互換性
  - 対策: API バージョニングの導入を検討
- Windows/WSL2 間のネットワーク問題
  - 対策: 接続テストと詳細なエラーメッセージ
