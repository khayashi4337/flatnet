# Phase 5: Flatnet CLI ツール

## ゴール

Flatnet システム全体を統一的に管理・監視できる CLI ツールを提供する。インストール、状態確認、診断を簡単に行えるようにし、運用者の体験を向上させる。

## スコープ

**含まれるもの:**
- `flatnet` CLI ツール（Rust 実装）
- システム状態表示（status）
- 診断機能（doctor）
- コンテナ一覧（ps）
- ログ表示（logs）
- インストール/アップグレード支援

**含まれないもの:**
- GUI ダッシュボード → Grafana を使用
- コンテナ作成/削除 → Podman を直接使用
- ネットワーク設定変更 → 設定ファイルを直接編集

## Phase 5 完了条件

- [ ] `flatnet status` でシステム全体の状態が確認できる
- [ ] `flatnet doctor` で問題を診断できる
- [ ] `flatnet ps` でコンテナと Flatnet IP が確認できる
- [ ] `flatnet logs` でコンポーネントのログが確認できる
- [ ] ワンライナーインストールスクリプトが提供されている
- [ ] ドキュメントが整備されている

---

## Stages

### Stage 1: CLI 基盤と status コマンド

**概要**
- Rust CLI プロジェクトのセットアップ
- `flatnet status` コマンドの実装
- Gateway/CNI/Monitoring の状態取得

**完了条件**
- [ ] `flatnet --help` が動作する
- [ ] `flatnet status` でシステム状態が表示される
- [ ] カラー出力とフォーマットが整っている

詳細: [stage-1-cli-foundation.md](./stage-1-cli-foundation.md)

---

### Stage 2: doctor コマンド

**概要**
- システム診断機能の実装
- 問題の自動検出と推奨アクション表示
- ヘルスチェックの統合

**完了条件**
- [ ] `flatnet doctor` が動作する
- [ ] 各コンポーネントの問題を検出できる
- [ ] 修正方法が提案される

詳細: [stage-2-doctor.md](./stage-2-doctor.md)

---

### Stage 3: ps と logs コマンド

**概要**
- コンテナ一覧表示（Flatnet IP 付き）
- ログ表示機能

**完了条件**
- [ ] `flatnet ps` でコンテナ一覧が表示される
- [ ] `flatnet logs <component>` でログが表示される

詳細: [stage-3-ps-logs.md](./stage-3-ps-logs.md)

---

### Stage 4: インストーラーとドキュメント

**概要**
- ワンライナーインストールスクリプト
- アップグレード機能
- ユーザードキュメント

**完了条件**
- [ ] インストールスクリプトが動作する
- [ ] `flatnet upgrade` が動作する
- [ ] ユーザーガイドが完成している

詳細: [stage-4-installer.md](./stage-4-installer.md)

---

## 成果物

- `src/flatnet-cli/` - CLI ツールソースコード
- `scripts/install-cli.sh` - インストールスクリプト
- `docs/cli/` - CLI ユーザーガイド

## 技術選定

### CLI フレームワーク

```toml
[dependencies]
clap = { version = "4", features = ["derive", "color"] }
tokio = { version = "1", features = ["full"] }
reqwest = { version = "0.11", features = ["json"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
colored = "2"
tabled = "0.14"  # テーブル表示
indicatif = "0.17"  # プログレスバー
```

### アーキテクチャ

```
flatnet-cli
├── main.rs           # エントリポイント
├── cli.rs            # CLI 定義 (clap)
├── commands/
│   ├── mod.rs
│   ├── status.rs     # status コマンド
│   ├── doctor.rs     # doctor コマンド
│   ├── ps.rs         # ps コマンド
│   └── logs.rs       # logs コマンド
├── clients/
│   ├── mod.rs
│   ├── gateway.rs    # Gateway API クライアント
│   ├── podman.rs     # Podman クライアント
│   └── prometheus.rs # Prometheus クライアント
└── config.rs         # 設定管理
```

## 前提条件

- Phase 1-4 が完了していること
- Rust 開発環境（WSL2）
- Gateway API が稼働していること

## Phase 依存関係

```
Phase 5 の前提:
├── Phase 1: Gateway 基盤 → Gateway API を使用
├── Phase 2: CNI Plugin → IPAM 状態を読み取り
├── Phase 3: マルチホスト → Nebula 状態を確認
└── Phase 4: 本番運用 → Prometheus/Loki と連携
```

## 関連ドキュメント

- [ロードマップ（全体）](../README.md)
- [Phase 4: 本番運用準備](../phase-4/README.md)
- [Gateway API 仕様](../../architecture/design-notes/gateway-api.md)
