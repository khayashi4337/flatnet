# Stage 3: Forgejo 統合

## 概要

WSL2 内で Forgejo を Podman コンテナとして起動し、OpenResty 経由で社内 LAN からアクセスできる状態にする。

## ブランチ戦略

- ブランチ名: `phase1/stage-3-forgejo-integration`
- マージ先: `master`

## インプット（前提条件）

- Stage 2 完了（WSL2 へのプロキシが動作している）
- WSL2 内に Podman がインストール済み
  ```bash
  podman --version
  # 期待: podman version 4.x.x 以上
  ```
- Forgejo コンテナイメージが取得可能（インターネット接続）

## 目標

- Forgejo を Podman で安定して起動できる
- OpenResty から Forgejo へのプロキシが動作する
- 社内メンバーが Git 操作を実行できる

## 手段

- Podman で Forgejo コンテナを起動
- データ永続化のための volume 設定
- nginx.conf に Forgejo 用の location 設定を追加
- Git over HTTP の動作確認

## ディレクトリ構成

```
[WSL2] ~/forgejo/
       ├── data/                    ← Forgejo データ（Git リポジトリ等）
       └── config/                  ← Forgejo 設定
           └── app.ini              ← Forgejo 設定ファイル

[WSL2] /home/kh/prj/flatnet/
       ├── config/
       │   └── openresty/
       │       └── nginx.conf       ← Forgejo プロキシ設定を追加
       └── scripts/
           └── forgejo/
               ├── run.sh           ← Forgejo 起動スクリプト
               └── forgejo.container ← Quadlet 定義（自動起動用）

[Windows] F:\flatnet\
          └── config\
              └── nginx.conf        ← デプロイ先
```

## Sub-stages

### Sub-stage 3.1: Forgejo コンテナ準備

**内容:**

- Forgejo 公式イメージの pull
- データ永続化用ディレクトリの作成
- Podman run コマンドの作成

**手順:**

1. **データ永続化用ディレクトリを作成:**

```bash
mkdir -p ~/forgejo/data ~/forgejo/config
```

2. **Forgejo イメージを pull（バージョン固定）:**

```bash
# latest は避け、メジャーバージョンを固定
podman pull codeberg.org/forgejo/forgejo:9
```

3. **起動スクリプトを作成:**

ファイル: `/home/kh/prj/flatnet/scripts/forgejo/run.sh`

```bash
#!/bin/bash
set -euo pipefail

# Forgejo コンテナを起動
CONTAINER_NAME="forgejo"
IMAGE="codeberg.org/forgejo/forgejo:9"
DATA_DIR="${HOME}/forgejo/data"
CONFIG_DIR="${HOME}/forgejo/config"

# 既存コンテナがあれば停止・削除
if podman container exists "${CONTAINER_NAME}"; then
    echo "Stopping existing container..."
    podman stop "${CONTAINER_NAME}" || true
    podman rm "${CONTAINER_NAME}" || true
fi

# コンテナを起動
echo "Starting Forgejo..."
podman run -d \
    --name "${CONTAINER_NAME}" \
    -p 3000:3000 \
    -v "${DATA_DIR}:/data:Z" \
    -v "${CONFIG_DIR}:/etc/gitea:Z" \
    "${IMAGE}"

echo "Forgejo started. Access at http://localhost:3000"
```

```bash
mkdir -p /home/kh/prj/flatnet/scripts/forgejo
chmod +x /home/kh/prj/flatnet/scripts/forgejo/run.sh
```

4. **Forgejo を起動:**

```bash
./scripts/forgejo/run.sh
```

**完了条件:**

- [ ] コンテナが起動している
  ```bash
  podman ps --filter name=forgejo
  # 期待出力: forgejo コンテナが STATUS=Up で表示される
  ```
- [ ] WSL2 内から Forgejo にアクセスできる
  ```bash
  curl -s http://localhost:3000/ | head -5
  # 期待出力: HTML コンテンツ（Forgejo のページ）
  ```
- [ ] 起動スクリプトが Git 管理されている
  ```bash
  ls -la scripts/forgejo/run.sh
  # 期待出力: 実行権限付きのファイル
  ```

### Sub-stage 3.2: Forgejo 初期設定

**内容:**

- Forgejo の初期セットアップウィザードを実行
- 管理者アカウントの作成
- 基本設定の調整

**手順:**

1. **ブラウザで初期設定ウィザードにアクセス:**

```
http://localhost:3000/
```

> 初回アクセス時に設定ウィザードが表示される

2. **基本設定を入力:**

| 設定項目 | 推奨値 | 説明 |
|----------|--------|------|
| データベースタイプ | SQLite3 | 小規模運用向け |
| サイトタイトル | Flatnet Forgejo | 任意 |
| リポジトリのルートパス | /data/git/repositories | デフォルト |
| Git LFS ルートパス | /data/git/lfs | デフォルト |
| 実行ユーザー | git | デフォルト |
| サーバードメイン | (Windows IP) | 例: 192.168.1.100 |
| SSH サーバーポート | (無効化) | Phase 1 では HTTP のみ |
| Forgejo ベース URL | http://(Windows IP)/ | OpenResty 経由の URL |
| ログパス | /data/gitea/log | デフォルト |

3. **管理者アカウントを作成:**

| 項目 | 入力値 |
|------|--------|
| ユーザー名 | admin（任意） |
| パスワード | 強固なパスワード |
| メールアドレス | admin@example.com |

4. **「Forgejo をインストール」をクリック**

5. **設定ファイルを確認:**

```bash
# app.ini が生成されていることを確認
cat ~/forgejo/config/app.ini | head -20
```

**完了条件:**

- [ ] 設定ウィザードが完了している
  ```bash
  test -f ~/forgejo/config/app.ini && echo "OK"
  # 期待出力: OK
  ```
- [ ] 管理者でログインできる
  ```
  ブラウザで http://localhost:3000/ にアクセスしてログイン
  ```
- [ ] ダッシュボードが表示される

### Sub-stage 3.3: OpenResty 連携

**内容:**

- nginx.conf に Forgejo 用の location を追加
- Forgejo の `app.ini` で ROOT_URL を設定
- 大きなリポジトリ用のバッファ設定

**手順:**

1. **nginx.conf に Forgejo 用の設定を追加:**

ファイル: `/home/kh/prj/flatnet/config/openresty/nginx.conf`

```nginx
worker_processes 1;
error_log F:/flatnet/logs/error.log info;
pid       F:/flatnet/logs/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       F:/flatnet/openresty/conf/mime.types;
    default_type  application/octet-stream;
    access_log    F:/flatnet/logs/access.log;

    # Git の大きなファイル対応
    client_max_body_size 100M;

    # Forgejo バックエンド
    upstream forgejo {
        server 172.25.160.1:3000;  # WSL2 IP を設定
    }

    server {
        listen 80;
        server_name _;

        # ヘルスチェック用エンドポイント
        location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
        }

        # Forgejo へのプロキシ
        location / {
            include F:/flatnet/config/conf.d/proxy-params.conf;

            # Git 操作用のタイムアウト延長
            proxy_read_timeout 300s;
            proxy_send_timeout 300s;

            proxy_pass http://forgejo;
        }
    }
}
```

2. **Forgejo の ROOT_URL を設定:**

```bash
# app.ini を編集
vim ~/forgejo/config/app.ini
```

```ini
[server]
DOMAIN = 192.168.1.100          ; Windows の LAN IP
ROOT_URL = http://192.168.1.100/
HTTP_PORT = 3000
DISABLE_SSH = true               ; Phase 1 では SSH 無効
```

3. **Forgejo を再起動して設定を反映:**

```bash
podman restart forgejo
```

4. **nginx 設定をデプロイ:**

```bash
./scripts/update-upstream.sh --reload
```

**完了条件:**

- [ ] 社内 LAN から Forgejo にアクセスできる
  ```powershell
  # Windows から
  (Invoke-WebRequest -Uri http://localhost/).StatusCode
  # 期待出力: 200
  ```
  ```bash
  # 別端末から
  curl -I http://<Windows IP>/
  # 期待出力: HTTP/1.1 200 OK
  ```
- [ ] ログイン・ログアウトが正常に動作する（ブラウザで確認）
- [ ] リダイレクトが正しい URL になる
  ```bash
  # ログインページの URL を確認
  curl -sI http://<Windows IP>/user/login | grep Location
  # 期待出力: Location に Windows IP が含まれる（localhost ではない）
  ```

### Sub-stage 3.4: Git 操作確認

**内容:**

- テストリポジトリの作成
- git clone/push の動作確認
- 認証（HTTP Basic）の動作確認

**手順:**

1. **Forgejo Web UI でテストリポジトリを作成:**

- ブラウザで `http://<Windows IP>/` にアクセス
- ログイン後、「+」 > 「新しいリポジトリ」
- リポジトリ名: `test-repo`
- 可視性: プライベート
- 「リポジトリを作成」をクリック

2. **git clone をテスト:**

```bash
# 任意の作業ディレクトリで実行
cd /tmp
git clone http://<Windows IP>/admin/test-repo.git
# ユーザー名とパスワードを入力
cd test-repo
```

3. **ファイルを追加して push:**

```bash
echo "# Test Repository" > README.md
git add README.md
git commit -m "Initial commit"
git push origin main
# ユーザー名とパスワードを入力
```

4. **認証情報のキャッシュ設定（オプション）:**

```bash
# 15 分間キャッシュ
git config --global credential.helper 'cache --timeout=900'

# または Git Credential Manager を使用
git config --global credential.helper manager
```

5. **大きなファイルのテスト（オプション）:**

```bash
# 10MB のテストファイルを作成
dd if=/dev/zero of=large-file.bin bs=1M count=10
git add large-file.bin
git commit -m "Add large file"
git push origin main
```

**完了条件:**

- [ ] git clone が成功する
  ```bash
  git clone http://<Windows IP>/admin/test-repo.git /tmp/test-clone
  # 期待出力: Cloning into '/tmp/test-clone'... done.
  ```
- [ ] git push が成功する
  ```bash
  cd /tmp/test-clone
  echo "test" >> README.md
  git add . && git commit -m "test" && git push
  # 期待出力: main -> main
  ```
- [ ] 認証が正しく動作する（誤ったパスワードで拒否される）
  ```bash
  # 間違ったパスワードで clone を試行
  GIT_ASKPASS=false git clone http://wronguser:wrongpass@<Windows IP>/admin/test-repo.git /tmp/fail-test 2>&1 | grep -i "auth\|401"
  # 期待出力: Authentication failed または 401
  ```

### Sub-stage 3.5: Podman 自動起動設定

**内容:**

- Quadlet による systemd ユーザーサービスの作成
- WSL2 起動時に Forgejo コンテナが自動起動する設定
- WSL2 自動起動の設定

**手順:**

1. **Quadlet 定義ファイルを作成:**

ファイル: `~/.config/containers/systemd/forgejo.container`

```ini
[Unit]
Description=Forgejo Git Service
After=local-fs.target

[Container]
ContainerName=forgejo
Image=codeberg.org/forgejo/forgejo:9
PublishPort=3000:3000
Volume=%h/forgejo/data:/data:Z
Volume=%h/forgejo/config:/etc/gitea:Z

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

2. **Quadlet 定義ファイルをリポジトリにも保存:**

ファイル: `/home/kh/prj/flatnet/scripts/forgejo/forgejo.container`

（上記と同じ内容を保存）

3. **ユーザーディレクトリにコピー:**

```bash
mkdir -p ~/.config/containers/systemd
cp /home/kh/prj/flatnet/scripts/forgejo/forgejo.container ~/.config/containers/systemd/
```

4. **既存のコンテナを停止:**

```bash
podman stop forgejo && podman rm forgejo
```

5. **systemd ユーザーサービスを有効化:**

```bash
# systemd ユーザーデーモンをリロード
systemctl --user daemon-reload

# サービスを有効化して起動
systemctl --user enable --now forgejo
```

6. **WSL2 の systemd を有効化（未設定の場合）:**

ファイル: `/etc/wsl.conf`

```ini
[boot]
systemd=true
```

> 変更後、`wsl --shutdown` で WSL2 を再起動

7. **WSL2 の自動起動設定（Windows 側）:**

Windows のスタートアップに以下を追加:

```powershell
# スタートアップフォルダに配置するスクリプト
# %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\start-wsl.cmd
wsl --exec bash -c "systemctl --user is-active forgejo || systemctl --user start forgejo"
```

または Windows タスクスケジューラで設定:

```powershell
# タスクを作成
$action = New-ScheduledTaskAction -Execute "wsl" -Argument "--exec bash -c 'sleep 5 && systemctl --user start forgejo'"
$trigger = New-ScheduledTaskTrigger -AtLogon
Register-ScheduledTask -TaskName "Start Forgejo" -Action $action -Trigger $trigger
```

**完了条件:**

- [ ] systemd サービスが有効になっている
  ```bash
  systemctl --user is-enabled forgejo
  # 期待出力: enabled
  ```
- [ ] サービスが起動している
  ```bash
  systemctl --user status forgejo
  # 期待出力: Active: active (running)
  ```
- [ ] WSL2 再起動後も Forgejo が自動で起動する
  ```powershell
  # Windows から WSL2 を再起動
  wsl --shutdown
  wsl --exec bash -c "sleep 10 && curl -s http://localhost:3000/ | head -1"
  # 期待出力: HTML コンテンツ
  ```

## 成果物

### Windows 側

| パス | 説明 |
|------|------|
| `F:\flatnet\config\nginx.conf` | Forgejo プロキシ設定追加版 |

### WSL2 側（Git 管理）

| パス | 説明 |
|------|------|
| `config/openresty/nginx.conf` | Forgejo プロキシ設定追加版（正） |
| `scripts/forgejo/run.sh` | Forgejo 起動スクリプト |
| `scripts/forgejo/forgejo.container` | Quadlet 定義ファイル |

### WSL2 側（データ）

| パス | 説明 |
|------|------|
| `~/forgejo/data/` | Forgejo データ（Git リポジトリ等） |
| `~/forgejo/config/` | Forgejo 設定（app.ini） |
| `~/.config/containers/systemd/forgejo.container` | Quadlet 定義（デプロイ先） |

## 完了条件

| 条件 | 確認コマンド |
|------|-------------|
| Forgejo が起動している | `podman ps --filter name=forgejo` |
| 社内 LAN からアクセスできる | `curl http://<Windows IP>/` |
| Git clone が動作する | `git clone http://<Windows IP>/user/repo.git` |
| Git push が動作する | `git push origin main` |
| 自動起動が設定されている | `systemctl --user is-enabled forgejo` |
| WSL2 再起動後も復旧する | `wsl --shutdown && wsl` 後に確認 |

## トラブルシューティング

### Forgejo が起動しない

**症状:** `podman ps` でコンテナが表示されない

**対処:**

```bash
# コンテナのログを確認
podman logs forgejo

# ポート 3000 が使用中でないか確認
ss -tlnp | grep 3000

# 手動で起動してエラーを確認
podman run -it --rm \
    -p 3000:3000 \
    -v ~/forgejo/data:/data:Z \
    -v ~/forgejo/config:/etc/gitea:Z \
    codeberg.org/forgejo/forgejo:9
```

### OpenResty 経由でアクセスできない

**症状:** `502 Bad Gateway` または `Connection refused`

**対処:**

```bash
# WSL2 内から Forgejo にアクセスできるか確認
curl http://localhost:3000/

# nginx.conf の upstream IP を確認
grep "server 172" /home/kh/prj/flatnet/config/openresty/nginx.conf

# IP を更新
./scripts/update-upstream.sh --reload
```

### Git push で認証エラー

**症状:** `Authentication failed`

**対処:**

```bash
# 認証キャッシュをクリア
git credential-cache exit

# Forgejo でパスワード再設定
# または Personal Access Token を使用
# Forgejo Web UI > 設定 > アプリケーション > アクセストークン
```

### 大きなファイルの push でタイムアウト

**症状:** `fatal: the remote end hung up unexpectedly`

**対処:**

```bash
# Git のバッファサイズを増加
git config --global http.postBuffer 524288000

# nginx.conf の client_max_body_size を確認
grep client_max_body_size /home/kh/prj/flatnet/config/openresty/nginx.conf
# 必要に応じて増加（例: 500M）
```

### systemd サービスが起動しない

**症状:** `systemctl --user status forgejo` でエラー

**対処:**

```bash
# WSL2 で systemd が有効か確認
ps -p 1 -o comm=
# 期待出力: systemd（init の場合は /etc/wsl.conf を設定）

# Quadlet 定義の文法チェック
/usr/libexec/podman/quadlet --dryrun ~/.config/containers/systemd/

# ログを確認
journalctl --user -u forgejo
```

## 備考

- Forgejo のバージョンは安定版を使用し、メジャーバージョンを固定することを推奨
- SSH でのアクセスは Phase 1 のスコープ外（HTTP のみ）
- 大規模なリポジトリや多数のユーザーがいる場合は、PostgreSQL への移行を検討
- バックアップは `~/forgejo/data/` と `~/forgejo/config/` を対象とする

## 次のステップ

Stage 3 完了後は [Stage 4: ドキュメント整備](./stage-4-documentation.md) に進み、セットアップ手順書とトラブルシューティングガイドを整備する。
