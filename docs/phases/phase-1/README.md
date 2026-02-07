# Phase 1: Gateway 基盤

## ゴール

OpenResty を Windows 上の窓口として、社内メンバーがブラウザから WSL2 内サービスにアクセスできる状態を作る。

## スコープ

**含まれるもの:**
- OpenResty (Windows) のセットアップ
- WSL2 内サービスへの HTTP プロキシ設定
- Forgejo の動作確認

**含まれないもの:**
- CNI プラグイン → Phase 2
- コンテナの自動登録 → Phase 2
- マルチホスト対応 → Phase 3

## Phase 1 完了条件

- [ ] OpenResty が Windows 上で起動している
- [ ] 社内 LAN のブラウザから Forgejo にアクセスできる
- [ ] WSL2 の IP 変更時の対応手順が文書化されている

---

## Stages

### Stage 1: OpenResty セットアップ

**概要**
- Windows 用 OpenResty のインストール
- 基本的な nginx.conf の設定
- 起動確認

**完了条件**
- [ ] OpenResty が Windows 上で起動する
- [ ] `http://localhost/` でデフォルトページが表示される
- [ ] Windows Firewall で 80/443 ポートが開放されている

---

### Stage 2: WSL2 プロキシ設定

**概要**
- WSL2 の IP アドレス取得方法の確立
- OpenResty から WSL2 へのプロキシ設定
- Lua による動的ルーティング（オプション）

**完了条件**
- [ ] WSL2 内で起動したサービスに OpenResty 経由でアクセスできる
- [ ] `proxy_pass` 設定が動作する
- [ ] WSL2 IP の取得・更新手順が確立されている

---

### Stage 3: Forgejo 統合

**概要**
- WSL2 内で Forgejo を Podman で起動
- OpenResty から Forgejo へのプロキシ
- 動作確認

**完了条件**
- [ ] Forgejo が WSL2 内で起動している
- [ ] 社内 LAN のブラウザから Forgejo UI にアクセスできる
- [ ] Git clone/push が動作する

---

### Stage 4: ドキュメント整備

**概要**
- セットアップ手順書の作成
- トラブルシューティングガイド
- WSL2 IP 変更時の対応手順

**完了条件**
- [ ] セットアップ手順書が完成
- [ ] 別の環境で手順書通りに構築できることを確認

---

## 成果物

- OpenResty 設定ファイル一式
- Forgejo 用 Podman 設定
- セットアップ手順書

## 技術メモ

### WSL2 の IP アドレス問題

WSL2 の IP は再起動時に変わる可能性がある：

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
    │
    ▼ HTTP (80/443)
[Windows: OpenResty]
    │
    ▼ proxy_pass
[WSL2: Forgejo Container]
```
