# Stage 3: Forgejo 統合

## 概要

WSL2 内で Forgejo を Podman コンテナとして起動し、OpenResty 経由で社内 LAN からアクセスできる状態にする。

## ブランチ戦略

- ブランチ名: `phase1/stage-3-forgejo-integration`
- マージ先: `master`

## インプット（前提条件）

- Stage 2 完了（WSL2 へのプロキシが動作している）
- WSL2 内に Podman がインストール済み
- Forgejo コンテナイメージが取得可能

## 目標

- Forgejo を Podman で安定して起動できる
- OpenResty から Forgejo へのプロキシが動作する
- 社内メンバーが Git 操作を実行できる

## 手段

- Podman で Forgejo コンテナを起動
- データ永続化のための volume 設定
- nginx.conf に Forgejo 用の location 設定を追加
- Git over HTTP の動作確認

## Sub-stages

### Sub-stage 3.1: Forgejo コンテナ準備

**内容:**
- Forgejo 公式イメージの pull（バージョン固定推奨）
  ```bash
  # latest は避け、特定バージョンを使用
  podman pull codeberg.org/forgejo/forgejo:9
  ```
- データ永続化用ディレクトリの作成
  ```bash
  mkdir -p ~/forgejo/data ~/forgejo/config
  ```
- Podman run コマンドの作成
  ```bash
  podman run -d \
    --name forgejo \
    -p 3000:3000 \
    -v ~/forgejo/data:/data:Z \
    -v ~/forgejo/config:/etc/gitea:Z \
    codeberg.org/forgejo/forgejo:9
  ```

**完了条件:**
- [ ] `podman run` で Forgejo が起動する
- [ ] WSL2 内から `http://localhost:3000` でアクセスできる

### Sub-stage 3.2: Forgejo 初期設定

**内容:**
- Forgejo の初期セットアップウィザードを実行
- 管理者アカウントの作成
- 基本設定の調整
  - サイト URL
  - SSH ポート（使用する場合）
  - データベース設定（SQLite）

**完了条件:**
- [ ] Forgejo のダッシュボードが表示される
- [ ] 管理者でログインできる

### Sub-stage 3.3: OpenResty 連携

**内容:**
- nginx.conf に Forgejo 用の location を追加
  ```nginx
  upstream forgejo {
      server <WSL2_IP>:3000;
  }

  server {
      listen 80;
      server_name _;

      location / {
          proxy_pass http://forgejo;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
      }
  }
  ```
- Forgejo の `app.ini` で ROOT_URL を外部アクセス URL に設定
  ```ini
  [server]
  ROOT_URL = http://<Windows IP>/
  ```
- 静的ファイルのキャッシュ設定（オプション）

**完了条件:**
- [ ] 社内 LAN から `http://<Windows IP>/` で Forgejo にアクセスできる
- [ ] ログイン・ログアウトが正常に動作する

### Sub-stage 3.4: Git 操作確認

**内容:**
- テストリポジトリの作成
- git clone の動作確認
  ```bash
  git clone http://<Windows IP>/user/repo.git
  ```
- git push の動作確認
- 認証（HTTP Basic）の動作確認

**完了条件:**
- [ ] git clone が成功する
- [ ] git push が成功する
- [ ] 認証が正しく動作する

### Sub-stage 3.5: Podman 自動起動設定

**内容:**
- systemd ユーザーサービスの作成
- WSL2 起動時に Forgejo コンテナが自動起動する設定
- ヘルスチェックの設定（オプション）

**完了条件:**
- [ ] WSL2 再起動後も Forgejo が自動で起動する

## 成果物

- `scripts/wsl2/forgejo/run.sh` - Forgejo 起動スクリプト
- `scripts/wsl2/forgejo/forgejo.container` - Quadlet 定義ファイル（オプション）
- `C:\openresty\conf\nginx.conf` - Forgejo プロキシ設定追加版
- Forgejo データ（WSL2 内）: `~/forgejo/data/`, `~/forgejo/config/`

## 完了条件

- [ ] Forgejo が WSL2 内で起動している
- [ ] 社内 LAN のブラウザから Forgejo UI にアクセスできる
- [ ] Git clone/push が動作する
- [ ] WSL2 再起動後も自動でサービスが復旧する

## 備考

- Forgejo のバージョンは安定版を使用し、メジャーバージョンを固定することを推奨
- SSH でのアクセスは Phase 1 のスコープ外（HTTP のみ）
- 大規模なリポジトリや多数のユーザーがいる場合は、PostgreSQL への移行を検討
