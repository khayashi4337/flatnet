# Flatnet ロードマップ

## コンセプト

```
問題: WSL2 + Podman 環境の NAT 地獄
      社内LAN → Windows → WSL2 → コンテナ（3段NAT）

解決: OpenResty を窓口としてカプセル化
      社内メンバーは HTTP のみでコンテナに到達
      Nebula 等のクライアントインストール不要
```

アーキテクチャ図: [component.puml](../architecture/diagrams/component.puml)

---

## Phase 1: Gateway 基盤

| 項目 | 内容 |
|------|------|
| **前提条件** | Windows + WSL2 環境、OpenResty インストール可能 |
| **目標** | 社内メンバーがブラウザから WSL2 内のサービスにアクセスできる |
| **内容** | OpenResty を Windows 上で起動、WSL2 内へ HTTP プロキシ |
| **終了条件** | ブラウザから `http://host/` で WSL2 内の Forgejo にアクセス可能 |
| **備考** | この時点では CNI は未実装。手動で WSL2 内サービスを設定 |

詳細: [Phase 1 詳細](./phase-1/README.md)

---

## Phase 2: CNI Plugin 実装

| 項目 | 内容 |
|------|------|
| **前提条件** | Phase 1 完了、Rust 開発環境、Podman インストール済み |
| **目標** | コンテナ起動時に自動で Flatnet IP が割り当てられ、Gateway から到達可能 |
| **内容** | Rust 製 CNI プラグイン、IP 割り当て、Gateway への自動登録 |
| **終了条件** | `podman run --network flatnet` でコンテナ起動 → ブラウザからアクセス可能 |
| **備考** | WSL2 内のローカル通信。トンネル/暗号化は不要 |

詳細: [Phase 2 詳細](./phase-2/README.md)

---

## Phase 3: マルチホスト対応（将来拡張）

| 項目 | 内容 |
|------|------|
| **前提条件** | Phase 2 完了、複数の Windows+WSL2 ホストが存在 |
| **目標** | 複数ホストのコンテナが相互に通信できる |
| **内容** | ホスト間トンネル、Lighthouse によるノード管理 |
| **終了条件** | 異なるホスト上のコンテナ同士が Flatnet IP で通信可能 |
| **備考** | e4mc 調査の知見を活用。Graceful Escalation パターン |

---

## Phase 4: 本番運用準備

| 項目 | 内容 |
|------|------|
| **前提条件** | Phase 3 完了（または Phase 2 で十分な場合はスキップ）|
| **目標** | 安定した本番運用ができる状態 |
| **内容** | 監視・ログ、セキュリティ強化、ドキュメント整備 |
| **終了条件** | 1週間の連続運用テスト完了、運用手順書整備 |
| **備考** | リモートメンバー対応もこのフェーズで検討 |

---

## Phase と解決する問題の対応

```
Phase 1: Gateway        → NAT 地獄の解消（手動設定）
Phase 2: CNI Plugin     → コンテナ管理の自動化
Phase 3: マルチホスト   → 複数ホスト間の連携
Phase 4: 本番運用       → 安定性・運用性
```

## 現在の進捗

```
Phase 1: Gateway        [=>            ] 設計中
Phase 2: CNI Plugin     [              ] 未着手
Phase 3: マルチホスト   [              ] 未着手
Phase 4: 本番運用       [              ] 未着手
```

## 関連ドキュメント

- [e4mc 調査](../architecture/research/e4mc-analysis.md) - 参考にした技術調査
- [フォールバック戦略](../architecture/design-notes/fallback-strategy.md) - Phase 3 で活用
