# Flatnet プロジェクトコンテキスト

## プロジェクト概要

WSL2 + Podman 環境の多段 NAT 問題を解消するゲートウェイと CNI プラグイン。

```
問題: 社内LAN → Windows → WSL2 → コンテナ（3段NAT）
解決: OpenResty を窓口としてカプセル化し、NAT 地獄を解消
```

## 設計原則

- **クライアントは HTTP のみ**: Nebula 等のインストール不要、ブラウザで完結
- **サーバー側で吸収**: NAT 問題は Gateway + CNI で解決
- **Graceful Escalation**: Gateway 経由が常に動作、最適化は後から

## 設計判断（決定済み）

- CNI Plugin 実装言語: Rust
- Gateway: OpenResty (Nginx + Lua) on Windows
- Container Runtime: Podman on WSL2
- ドキュメント管理: C4 モデルベース
- 計画粒度: Phase > Stage > Sub-stage

## 構成

```
docs/
├── architecture/
│   ├── diagrams/          # PlantUML 図
│   ├── design-notes/      # 設計判断メモ
│   └── research/          # 技術調査（e4mc 等）
└── phases/                # 開発計画
src/                       # Rust ソースコード（Phase 2〜）
```

## 現在のフェーズ

**Phase 1: Gateway 基盤**（設計中）

- OpenResty を Windows 上で起動
- WSL2 内サービスへ HTTP プロキシ
- Forgejo にブラウザからアクセス可能に

## Phase 概要

| Phase | 内容 | 状態 |
|-------|------|------|
| Phase 1 | Gateway 基盤（NAT 地獄の解消）| 設計中 |
| Phase 2 | CNI Plugin（コンテナ管理自動化）| 未着手 |
| Phase 3 | マルチホスト（複数ホスト間通信）| 未着手 |
| Phase 4 | 本番運用準備 | 未着手 |

## 技術的な前提

- Windows 11 + WSL2 (Ubuntu 24.04)
- Podman v4 系
- OpenResty (Windows 版)

## 参考調査

- [e4mc 調査](docs/architecture/research/e4mc-analysis.md): NAT 越え技術の参考
- [フォールバック戦略](docs/architecture/design-notes/fallback-strategy.md): Phase 3 で活用予定
