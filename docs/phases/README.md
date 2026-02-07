# Flatnet ロードマップ

全体を4つのPhaseに分けて段階的に構築する。

アーキテクチャ図: [component.puml](../architecture/diagrams/component.puml)

---

## Phase 1: CNI Plugin 実装

| 項目 | 内容 |
|------|------|
| **前提条件** | WSL2 + Podman がインストール済み、Rust 開発環境が利用可能 |
| **目標** | Rust製 CNI プラグインが動作し、コンテナ間でオーバーレイ通信ができる |
| **内容** | FlatnetCNI (ADD/DEL/CHECK)、NetworkNamespace操作、TunnelManager、IPAddressManager の実装 |
| **終了条件** | Podman上の2コンテナが Flatnet トンネル経由で相互に通信できる |
| **備考** | Lighthouse はモック/ローカル実装で代替可能。本格実装は Phase 3 |

詳細: [Phase 1 詳細](./phase-1/README.md)

---

## Phase 2: Gateway 統合

| 項目 | 内容 |
|------|------|
| **前提条件** | Phase 1 完了、Windows 上で OpenResty が利用可能 |
| **目標** | 社内LANからブラウザで Flatnet 上のサービスにアクセスできる |
| **内容** | Gateway (OpenResty)、LuaRouter の実装、TLS終端、Flatnet IP へのプロキシ |
| **終了条件** | 社内LANのブラウザから Forgejo UI にアクセスできる |
| **備考** | VPNクライアント不要でアクセス可能にすることが重要 |

---

## Phase 3: Lighthouse 本格実装

| 項目 | 内容 |
|------|------|
| **前提条件** | Phase 2 完了、複数ホスト環境が利用可能 |
| **目標** | 複数ホストにまたがるコンテナが Flatnet で直接通信できる |
| **内容** | Lighthouse サーバー、NodeRegistry、LighthouseClient の本格実装、NAT穴あけ (handle_punch) |
| **終了条件** | 異なるホスト上のコンテナ同士が Flatnet IP で相互に通信できる |
| **備考** | Phase 1 のモック Lighthouse を本番実装に置き換え |

---

## Phase 4: 本番運用準備

| 項目 | 内容 |
|------|------|
| **前提条件** | Phase 3 完了 |
| **目標** | 安定した本番運用ができる状態にする |
| **内容** | 監視・ログ収集、障害時の自動復旧、セキュリティ強化、ドキュメント整備 |
| **終了条件** | 1週間の連続運用テストを問題なく完了、運用手順書が整備されている |
| **備考** | リモートメンバー対応（VPN経由アクセス）もこのフェーズで検討 |

---

## コンポーネントと Phase の対応

| コンポーネント | Phase 1 | Phase 2 | Phase 3 | Phase 4 |
|---------------|---------|---------|---------|---------|
| FlatnetCNI | ● 実装 | | | |
| NetworkNamespace | ● 実装 | | | |
| TunnelManager | ● 実装 | | | |
| IPAddressManager | ● 実装 | | | |
| LighthouseClient | ○ モック | | ● 本実装 | |
| Gateway | | ● 実装 | | |
| LuaRouter | | ● 実装 | | |
| Lighthouse | | | ● 実装 | |
| NodeRegistry | | | ● 実装 | |

---

## 現在の進捗

```
Phase 1: CNI Plugin      [=>            ] 設計中
Phase 2: Gateway統合     [              ] 未着手
Phase 3: Lighthouse      [              ] 未着手
Phase 4: 本番運用準備    [              ] 未着手
```
