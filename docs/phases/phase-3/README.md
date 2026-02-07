# Phase 3: マルチホスト対応

## ゴール

複数の Windows+WSL2 ホスト間でコンテナが相互に通信できる状態を作る。Nebula Lighthouse を活用しつつ、クライアントには HTTP のみで完結する透過的なアクセスを維持する。

## スコープ

**含まれるもの:**
- Nebula Lighthouse の導入・設定
- ホスト間トンネルの構築
- CNI Plugin のマルチホスト対応拡張
- Graceful Escalation パターンの実装
- フォールバック機構

**含まれないもの:**
- リモートメンバー対応（インターネット越え）→ Phase 4
- 監視・ログ基盤 → Phase 4
- セキュリティ強化（認証・認可の高度化）→ Phase 4

## 設計原則

1. **クライアントは HTTP のみ**: Nebula はサーバー側に閉じ込め、クライアントには見せない
2. **Graceful Escalation**: Gateway 経由が常に動作、P2P は最適化として追加
3. **信頼性 > 最適化**: P2P 失敗時も接続を維持

## Phase 3 完了条件

- [ ] 複数ホストの Gateway が相互に認識している
- [ ] 異なるホスト上のコンテナ同士が Flatnet IP で通信可能
- [ ] P2P 経路確立時は直接通信、失敗時は Gateway 経由にフォールバック
- [ ] クライアントは変わらず HTTP のみでアクセスできる

---

## Stages 概要

| Stage | タイトル | 概要 |
|-------|----------|------|
| Stage 1 | Nebula Lighthouse 導入 | Lighthouse の設置と基本設定 |
| Stage 2 | ホスト間トンネル構築 | Windows 間の Nebula トンネル確立 |
| Stage 3 | CNI Plugin マルチホスト拡張 | IP 割り当ての分散化、ルーティング設定 |
| Stage 4 | Graceful Escalation 実装 | フォールバック機構の実装 |
| Stage 5 | 統合テスト・ドキュメント | マルチホスト環境での動作確認 |

---

## Stage 依存関係

```
Phase 2 完了
    │
    ▼
[Stage 1: Lighthouse 導入]
    │
    ▼
[Stage 2: ホスト間トンネル]
    │
    ▼
[Stage 3: CNI マルチホスト] ← Phase 2 の CNI Plugin も前提
    │
    ▼
[Stage 4: Graceful Escalation]
    │
    ▼
[Stage 5: 統合テスト]
    │
    ▼
Phase 3 完了
```

---

## Stage 詳細

各 Stage の詳細は個別ファイルを参照:

- [Stage 1: Nebula Lighthouse 導入](./stage-1-lighthouse-setup.md)
- [Stage 2: ホスト間トンネル構築](./stage-2-host-tunnel.md)
- [Stage 3: CNI Plugin マルチホスト拡張](./stage-3-cni-multihost.md)
- [Stage 4: Graceful Escalation 実装](./stage-4-graceful-escalation.md)
- [Stage 5: 統合テスト・ドキュメント](./stage-5-integration-test.md)

---

## アーキテクチャ（Phase 3 完了時）

```
[社内 LAN]
    │
    ├── HTTP ──→ [Host A: OpenResty Gateway]
    │                  │
    │                  ├── Nebula ←──────────┐
    │                  │                     │
    │                  └── WSL2 ──→ [Container A1, A2...]
    │                                        │
    │                     Nebula Tunnel      │
    │                         │              │
    └── HTTP ──→ [Host B: OpenResty Gateway] │
                       │                     │
                       ├── Nebula ←──────────┘
                       │
                       └── WSL2 ──→ [Container B1, B2...]

[Lighthouse] (別サーバー or Host A に同居)
    └── ノード管理、NAT 越え支援
```

## 成果物

- Nebula Lighthouse 設定ファイル
- ホスト間トンネル設定
- CNI Plugin マルチホスト対応版
- Graceful Escalation 実装
- マルチホスト運用手順書

## 技術的な前提

- Phase 2 が完了している（CNI Plugin が単一ホストで動作）
- 複数の Windows+WSL2 環境が社内 LAN に存在
- Nebula バイナリが入手可能

## 関連ドキュメント

- [Lighthouse 方針](../../architecture/design-notes/lighthouse-decision.md)
- [フォールバック戦略](../../architecture/design-notes/fallback-strategy.md)
- [e4mc 調査](../../architecture/research/e4mc-analysis.md)
