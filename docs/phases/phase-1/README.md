# Phase 1: Gateway 基盤

## ゴール

OpenResty を Windows 上の窓口として、社内メンバーがブラウザから WSL2 内サービスにアクセスできる状態を作る。

## スコープ

**含まれるもの:**
- OpenResty (Windows) のセットアップ
- WSL2 内サービスへの HTTP プロキシ設定
- Forgejo の動作確認
- セットアップ・運用ドキュメント

**含まれないもの:**
- CNI プラグイン → Phase 2
- コンテナの自動登録 → Phase 2
- マルチホスト対応 → Phase 3

## Phase 1 完了条件

- [ ] OpenResty が Windows 上で起動している
- [ ] 社内 LAN のブラウザから Forgejo にアクセスできる
- [ ] WSL2 の IP 変更時の対応手順が文書化されている
- [ ] セットアップ手順書・運用ガイドが整備されている

---

## Stages 概要

| Stage | タイトル | 概要 | 成果物 |
|-------|---------|------|--------|
| 1 | [OpenResty セットアップ](./stage-1-openresty-setup.md) | Windows に OpenResty をインストール | OpenResty 動作環境 |
| 2 | [WSL2 プロキシ設定](./stage-2-wsl2-proxy.md) | OpenResty から WSL2 への転送 | プロキシ設定・IP 管理スクリプト |
| 3 | [Forgejo 統合](./stage-3-forgejo-integration.md) | Forgejo の起動と動作確認 | Forgejo 環境・Git 操作確認 |
| 4 | [ドキュメント整備](./stage-4-documentation.md) | 手順書・ガイドの作成 | セットアップ・運用ドキュメント |

---

## Stage 1: OpenResty セットアップ

**概要:** Windows 上に OpenResty をインストールし、基本的な HTTP サーバーとして動作させる。

**Sub-stages:**
1. OpenResty インストール
2. 基本設定
3. Windows Firewall 設定
4. サービス化（オプション）

**完了条件:**
- [ ] OpenResty が Windows 上で起動する
- [ ] `http://localhost/` でデフォルトページが表示される
- [ ] Windows Firewall で 80/443 ポートが開放されている

詳細: [stage-1-openresty-setup.md](./stage-1-openresty-setup.md)

---

## Stage 2: WSL2 プロキシ設定

**概要:** OpenResty から WSL2 内のサービスへ HTTP リクエストをプロキシする仕組みを構築する。

**Sub-stages:**
1. WSL2 IP 取得方法の確立
2. 静的プロキシ設定
3. 動的 IP 解決（Lua）
4. プロキシヘッダーの調整

**完了条件:**
- [ ] WSL2 内で起動したサービスに OpenResty 経由でアクセスできる
- [ ] `proxy_pass` 設定が動作する
- [ ] WSL2 IP の取得・更新手順が確立されている

詳細: [stage-2-wsl2-proxy.md](./stage-2-wsl2-proxy.md)

---

## Stage 3: Forgejo 統合

**概要:** WSL2 内で Forgejo を Podman コンテナとして起動し、OpenResty 経由で社内 LAN からアクセスできる状態にする。

**Sub-stages:**
1. Forgejo コンテナ準備
2. Forgejo 初期設定
3. OpenResty 連携
4. Git 操作確認
5. Podman 自動起動設定

**完了条件:**
- [ ] Forgejo が WSL2 内で起動している
- [ ] 社内 LAN のブラウザから Forgejo UI にアクセスできる
- [ ] Git clone/push が動作する

詳細: [stage-3-forgejo-integration.md](./stage-3-forgejo-integration.md)

---

## Stage 4: ドキュメント整備

**概要:** Phase 1 の成果を他者が再現できるよう、セットアップ手順書とトラブルシューティングガイドを整備する。

**Sub-stages:**
1. セットアップ手順書
2. トラブルシューティングガイド
3. 運用ガイド
4. 検証テスト

**完了条件:**
- [ ] セットアップ手順書が完成
- [ ] 別の環境で手順書通りに構築できることを確認

詳細: [stage-4-documentation.md](./stage-4-documentation.md)

---

## 成果物

- OpenResty 設定ファイル一式
- Forgejo 用 Podman 設定
- セットアップ手順書
- トラブルシューティングガイド
- 運用ガイド

## 技術メモ

### WSL2 の IP アドレス問題

WSL2 の IP は再起動時に変わる可能性がある:

```bash
# WSL2 内で IP 確認
ip addr show eth0 | grep inet
```

対策案:
1. 起動時スクリプトで nginx.conf を更新
2. Lua で動的に解決
3. localhost forwarding (実験的機能)

### ネットワーク構成（Phase 1 完了時）

```
[社内 LAN]
    |
    v HTTP (80/443)
[Windows: OpenResty]
    |
    v proxy_pass
[WSL2: Forgejo Container]
```

## 関連ドキュメント

- [Phase ロードマップ](../README.md)
- [コンポーネント図](../../architecture/diagrams/component.puml)
