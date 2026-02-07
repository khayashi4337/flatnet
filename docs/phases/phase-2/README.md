# Phase 2: CNI Plugin 実装

## ゴール

Rust製CNIプラグインをPodmanと連携させ、コンテナ起動時にFlatnet IPを自動割り当てし、Gateway（Phase 1）から自動的に到達可能な状態を作る。

## スコープ

**含まれるもの:**
- CNI仕様に準拠したプラグイン実装（Rust）
- Podman との連携設定
- IP アドレスの自動割り当て（IPAM）
- veth ペアによるネットワーク設定
- Gateway への到達性確保

**含まれないもの:**
- マルチホスト対応 → Phase 3
- Nebula 連携 → Phase 3
- 暗号化通信 → Phase 3
- 高可用性・監視 → Phase 4

## 前提条件

- Phase 1 完了（Gateway が動作している）
- Rust 開発環境（rustup, cargo）
- Podman v4 系インストール済み
- WSL2 Ubuntu 24.04

## Phase 2 完了条件

- [ ] `podman run --network flatnet` でコンテナが起動する
- [ ] コンテナに Flatnet IP（例: 10.87.x.x）が割り当てられる
- [ ] Gateway（OpenResty）からコンテナに HTTP でアクセスできる
- [ ] コンテナ停止時に IP が解放される

---

## Stages 概要

| Stage | タイトル | 概要 | 目安期間 |
|-------|----------|------|----------|
| [Stage 1](./stage-1-cni-basics.md) | CNI仕様理解と開発環境 | CNI仕様の調査、Rust開発環境構築 | 2-3日 |
| [Stage 2](./stage-2-minimal-plugin.md) | 最小CNIプラグイン | ADD/DEL/CHECKの骨格実装 | 3-5日 |
| [Stage 3](./stage-3-network-setup.md) | ネットワーク設定 | IP割り当て、vethペア、ルーティング | 5-7日 |
| [Stage 4](./stage-4-integration.md) | Podman統合とGateway連携 | 実環境での動作確認 | 3-5日 |

### Stage 依存関係

```
Phase 1 (Gateway) ──────────────────────────────┐
                                                │
Stage 1 ──→ Stage 2 ──→ Stage 3 ──→ Stage 4 ←──┘
  │           │           │           │
  └───────────┴───────────┴───────────┘
              順次依存（前Stage完了が前提）
```

- Stage 1-3: Phase 1 と並行作業可能（ただし Stage 4 開始前に Phase 1 完了必須）
- Stage 4: Phase 1 + Stage 3 の両方が完了している必要あり

---

## アーキテクチャ（Phase 2 完了時）

```
[社内 LAN]
    │
    ▼ HTTP (80/443)
[Windows: OpenResty Gateway]
    │
    ▼ proxy_pass → 10.87.1.x
[WSL2]
    │
    ├── flatnet-br0 (10.87.1.1/24)  ← ブリッジ（ゲートウェイ）
    │       │
    │       ├── fn-a1b2c3d4 ─┐
    │       │                │ veth pair
    │       └────────────────┘
    │                        │
[Container netns]            │
    │                        │
    └── eth0 ←───────────────┘
        IP: 10.87.1.2/24
```

## 成果物

- `src/flatnet-cni/` - Rust CNI プラグイン
- `/opt/cni/bin/flatnet` - ビルド済みバイナリ
- `/etc/cni/net.d/flatnet.conflist` - CNI 設定ファイル
- ドキュメント更新

## 技術的な考慮事項

### CNI 仕様バージョン

CNI Spec 1.0.0 をターゲットとする。主要なオペレーション:
- `ADD`: コンテナ作成時のネットワーク設定
- `DEL`: コンテナ削除時のクリーンアップ
- `CHECK`: ネットワーク状態の検証

### IP アドレス設計

```
Flatnet CIDR: 10.87.0.0/16
  - 10.87.0.0/24:    予約（Gateway等）
  - 10.87.1.0/24:    Host-1 コンテナ用
  - 10.87.2.0/24:    Host-2 コンテナ用（Phase 3）
  ...
```

### Rust クレート候補

- `serde_json`: CNI 入出力の JSON 処理
- `nix`: Linux システムコール
- `rtnetlink`: netlink 操作
- `ipnetwork`: IP アドレス操作

---

## リスクと対策

| リスク | 影響 | 対策 |
|--------|------|------|
| Podman が netavark をデフォルト使用 | CNI が呼ばれない | Podman 設定で CNI モードを明示 |
| WSL2 の IP が変動 | Gateway からの到達性が失われる | Stage 4 で起動スクリプト整備 |
| rtnetlink の非同期処理 | 実装複雑化 | tokio ランタイム導入を検討 |
| veth 名の長さ制限（15文字） | 名前衝突 | container ID の短縮ハッシュを使用 |

## 関連ドキュメント

- [Phase 1: Gateway 基盤](../phase-1/README.md)
- [コンポーネント図](../../architecture/diagrams/component.puml)
- [コンテナ図](../../architecture/container.md)
