# Phase 1 セットアップガイド

Phase 1（Gateway 基盤）の環境構築手順書。Windows 上の OpenResty をゲートウェイとして、WSL2 内の Forgejo に社内 LAN からアクセスできるようにします。

## 目次

1. [前提条件](#前提条件)
2. [OpenResty インストール](#1-openresty-インストール)
3. [WSL2 プロキシ設定](#2-wsl2-プロキシ設定)
4. [Windows Firewall 設定](#3-windows-firewall-設定)
5. [Forgejo セットアップ](#4-forgejo-セットアップ)
6. [OpenResty 起動](#5-openresty-起動)
7. [動作確認](#6-動作確認)
8. [自動起動設定](#7-自動起動設定オプション)
9. [Git 操作確認](#8-git-操作確認)

## 前提条件

| 項目 | 要件 |
|------|------|
| OS | Windows 10/11 (21H2 以降) |
| WSL2 | Ubuntu 24.04 |
| Podman | 4.x 以上 |
| メモリ | 8GB 以上推奨 |
| ディスク | F: ドライブに 10GB 以上の空き |

### WSL2 での systemd 有効化

Forgejo の自動起動には systemd が必要です。WSL2 で systemd を有効にしていない場合は、以下の設定を行ってください。

ファイル: `/etc/wsl.conf`

```ini
[boot]
systemd=true
```

設定後、WSL2 を再起動します。

```powershell
wsl --shutdown
wsl
```

確認:

```bash
ps -p 1 -o comm=
# 期待出力: systemd
```

## 1. OpenResty インストール

### 1.1 ディレクトリ作成（PowerShell 管理者）

```powershell
New-Item -ItemType Directory -Path F:\flatnet -Force
New-Item -ItemType Directory -Path F:\flatnet\config -Force
New-Item -ItemType Directory -Path F:\flatnet\config\conf.d -Force
New-Item -ItemType Directory -Path F:\flatnet\logs -Force
New-Item -ItemType Directory -Path F:\flatnet\scripts -Force
```

### 1.2 OpenResty ダウンロードと展開

1. https://openresty.org/en/download.html から Windows 版（win64）をダウンロード
2. ZIP を展開:

```powershell
cd $env:USERPROFILE\Downloads
Expand-Archive -Path openresty-1.25.3.1-win64.zip -DestinationPath F:\flatnet\
Rename-Item -Path "F:\flatnet\openresty-1.25.3.1-win64" -NewName "openresty"
```

### 1.3 動作確認

```powershell
F:\flatnet\openresty\nginx.exe -v
# 期待出力: nginx version: openresty/1.25.3.1
```

### 1.4 テストページ作成

```powershell
$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Flatnet Gateway</title>
    <meta charset="utf-8">
</head>
<body>
    <h1>Flatnet Gateway</h1>
    <p>OpenResty is running.</p>
</body>
</html>
"@
$html | Out-File -FilePath F:\flatnet\openresty\html\index.html -Encoding utf8
```

## 2. WSL2 プロキシ設定

### 2.1 WSL2 側ディレクトリ作成

```bash
mkdir -p /home/kh/prj/flatnet/config/openresty/conf.d
mkdir -p /home/kh/prj/flatnet/scripts/forgejo
```

### 2.2 nginx.conf 設定

ファイル: `/home/kh/prj/flatnet/config/openresty/nginx.conf`

プロジェクトの `config/openresty/nginx.conf` を使用するか、`examples/openresty/nginx.conf` を参考に作成してください。

主要な設定項目:

```nginx
# WSL2 バックエンドの定義
upstream forgejo {
    server 172.x.x.x:3000;  # WSL2 IP に変更
    keepalive 32;
}

# Git の大きなファイル対応
client_max_body_size 100M;

# プロキシヘッダー（クライアント IP の伝達）
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
```

### 2.3 プロキシ共通設定

ファイル: `/home/kh/prj/flatnet/config/openresty/conf.d/proxy-params.conf`

```nginx
# プロキシ共通設定
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-Port $server_port;

# タイムアウト設定
proxy_connect_timeout 60s;
proxy_send_timeout 60s;
proxy_read_timeout 60s;

# バッファ設定
proxy_buffering on;
proxy_buffer_size 4k;
proxy_buffers 8 4k;
```

### 2.4 WebSocket 対応設定

ファイル: `/home/kh/prj/flatnet/config/openresty/conf.d/websocket-params.conf`

```nginx
# WebSocket 対応設定
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";

# WebSocket は長時間接続
proxy_read_timeout 3600s;
proxy_send_timeout 3600s;
```

### 2.5 WSL2 IP 取得

```bash
ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1
# 例: 172.25.160.1
```

取得した IP で nginx.conf の `upstream forgejo` を更新してください。

### 2.6 設定デプロイ

```bash
# デプロイスクリプトを使用（推奨）
# conf.d ディレクトリも含めて自動的にコピーされます
./scripts/deploy-config.sh

# 手動でコピーする場合
cp /home/kh/prj/flatnet/config/openresty/nginx.conf /mnt/f/flatnet/config/
mkdir -p /mnt/f/flatnet/config/conf.d
cp /home/kh/prj/flatnet/config/openresty/conf.d/* /mnt/f/flatnet/config/conf.d/
```

## 3. Windows Firewall 設定（PowerShell 管理者）

> **注意:** ネットワークプロファイルが「Public」の場合、Firewall ルールを追加しても LAN からのアクセスがブロックされることがあります。社内 LAN に接続している場合は「Private」プロファイルを推奨します。

```powershell
# ネットワークプロファイルを確認
Get-NetConnectionProfile

# 必要に応じて Private に変更（社内 LAN の場合）
# Set-NetConnectionProfile -InterfaceAlias "イーサネット" -NetworkCategory Private
```

```powershell
# ポートベースのルール
New-NetFirewallRule -DisplayName "OpenResty HTTP" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
New-NetFirewallRule -DisplayName "OpenResty HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow

# 上記が機能しない場合は、プログラムベースのルールを追加
New-NetFirewallRule -DisplayName "OpenResty Program" -Direction Inbound -Program "F:\flatnet\openresty\nginx.exe" -Action Allow
```

確認:

```powershell
Get-NetFirewallRule -DisplayName "OpenResty*" | Format-Table DisplayName, Enabled, Action
```

## 4. Forgejo セットアップ

### 4.1 データディレクトリ作成

```bash
mkdir -p ~/forgejo/data ~/forgejo/config
```

### 4.2 イメージ取得

```bash
# バージョンを固定して pull（latest は避ける）
podman pull codeberg.org/forgejo/forgejo:9
```

### 4.3 コンテナ起動

```bash
podman run -d \
    --name forgejo \
    -p 3000:3000 \
    -v ~/forgejo/data:/data:Z \
    -v ~/forgejo/config:/etc/gitea:Z \
    codeberg.org/forgejo/forgejo:9
```

または、スクリプトを使用:

```bash
./scripts/forgejo/run.sh
```

### 4.4 初期設定

> **セキュリティ注意:** 初期設定ウィザードで最初に作成するアカウントが管理者になります。ウィザード完了前に他のユーザーがアクセスできないよう、Firewall 設定は動作確認後に行うことを推奨します。

1. ブラウザで `http://localhost:3000/` にアクセス
2. 設定ウィザードを完了:

   | 設定項目 | 推奨値 |
   |----------|--------|
   | データベースタイプ | SQLite3 |
   | サイトタイトル | Flatnet Forgejo（任意） |
   | サーバードメイン | (Windows の LAN IP) |
   | Forgejo ベース URL | `http://(Windows IP)/` |
   | SSH サーバーポート | 無効化（Phase 1 では HTTP のみ） |

3. 管理者アカウントを作成

> **運用ヒント:** 社内利用の場合、初期設定完了後に `app.ini` で `DISABLE_REGISTRATION = true` を設定して新規ユーザー登録を無効化することを推奨します。

### 4.5 app.ini 設定

初期設定後、`~/forgejo/config/app.ini` を編集して ROOT_URL を設定します。

```ini
[server]
DOMAIN = 192.168.1.100          ; Windows の LAN IP に変更
ROOT_URL = http://192.168.1.100/
HTTP_PORT = 3000
DISABLE_SSH = true              ; Phase 1 では SSH 無効

[service]
DISABLE_REGISTRATION = true     ; 新規ユーザー登録を無効化（推奨）
```

> **セキュリティ注意:** Phase 1 では HTTP（非暗号化）を使用しています。認証情報がネットワーク上を平文で流れるため、社内 LAN など信頼できるネットワーク環境でのみ使用してください。HTTPS 対応は Phase 4 で実装予定です。

設定を反映:

```bash
podman restart forgejo
```

## 5. OpenResty 起動

Forgejo を使用する場合は `nginx-forgejo.conf` を使用します。

```powershell
cd F:\flatnet\openresty

# 設定テスト（Forgejo 用）
.\nginx.exe -c F:\flatnet\config\nginx-forgejo.conf -t
# 期待出力: test is successful

# 起動（Forgejo 用）
.\nginx.exe -c F:\flatnet\config\nginx-forgejo.conf
```

> **注意:** Stage 2 の WSL2 プロキシのみをテストする場合は `nginx.conf` を使用します。

プロセス確認:

```powershell
Get-Process nginx
```

## 6. 動作確認

### Windows 側から確認

```powershell
# ヘルスチェック
(Invoke-WebRequest -Uri http://localhost/health).Content
# 期待: OK

# Forgejo アクセス
(Invoke-WebRequest -Uri http://localhost/).StatusCode
# 期待: 200
```

### WSL2 側から確認

```bash
# Forgejo 直接アクセス
curl http://localhost:3000/
```

### 別端末から確認

```bash
curl http://<Windows IP>/health
# 期待: OK

curl -I http://<Windows IP>/
# 期待: HTTP/1.1 200 OK
```

## 7. 自動起動設定（オプション）

### 7.1 OpenResty サービス化（NSSM 使用）

1. NSSM をダウンロード: https://nssm.cc/download
2. `nssm.exe` (win64) を `F:\flatnet\` にコピー
3. サービス登録:

```powershell
# 既存の nginx プロセスを停止
Stop-Process -Name nginx -Force -ErrorAction SilentlyContinue

# サービス登録
# 注意: Forgejo を使用する場合は nginx-forgejo.conf を指定してください
F:\flatnet\nssm.exe install OpenResty F:\flatnet\openresty\nginx.exe
F:\flatnet\nssm.exe set OpenResty AppDirectory F:\flatnet\openresty
F:\flatnet\nssm.exe set OpenResty AppParameters "-c F:\flatnet\config\nginx-forgejo.conf"
F:\flatnet\nssm.exe set OpenResty Description "Flatnet Gateway (OpenResty)"
F:\flatnet\nssm.exe set OpenResty Start SERVICE_AUTO_START

# サービス開始
Start-Service OpenResty

# 確認
Get-Service OpenResty
```

### 7.2 Forgejo systemd サービス

1. Quadlet 定義ファイルを作成:

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

2. サービスを有効化:

```bash
# ディレクトリ作成
mkdir -p ~/.config/containers/systemd

# Quadlet 定義をコピー
cp /home/kh/prj/flatnet/scripts/forgejo/forgejo.container ~/.config/containers/systemd/

# 既存コンテナを停止
podman stop forgejo && podman rm forgejo

# systemd をリロードしてサービスを有効化
systemctl --user daemon-reload
systemctl --user enable --now forgejo

# 確認
systemctl --user status forgejo
```

## 8. Git 操作確認

### 8.1 テストリポジトリ作成

1. ブラウザで `http://<Windows IP>/` にアクセス
2. ログイン後、「+」 > 「新しいリポジトリ」
3. リポジトリ名: `test-repo`
4. 「リポジトリを作成」をクリック

### 8.2 git clone テスト

```bash
cd /tmp
git clone http://<Windows IP>/admin/test-repo.git
# ユーザー名とパスワードを入力
cd test-repo
```

### 8.3 git push テスト

```bash
echo "# Test Repository" > README.md
git add README.md
git commit -m "Initial commit"
git push origin main
# ユーザー名とパスワードを入力
```

### 8.4 認証情報のキャッシュ（オプション）

毎回パスワードを入力しなくて済むように:

```bash
# 15 分間キャッシュ
git config --global credential.helper 'cache --timeout=900'
```

## WSL2 IP 変更時の対応

WSL2 を再起動すると IP アドレスが変わる場合があります。その場合は以下を実行:

```bash
# スクリプトで IP を更新してデプロイ + リロード
./scripts/update-upstream.sh --reload
```

または手動で:

1. 新しい IP を確認: `ip addr show eth0 | grep 'inet '`
2. nginx.conf の upstream IP を更新
3. 設定をデプロイ: `cp config/openresty/nginx.conf /mnt/f/flatnet/config/`
4. OpenResty をリロード: `F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx-forgejo.conf -s reload`

## 関連ドキュメント

- [トラブルシューティング](./phase1-troubleshooting.md) - 問題発生時の対処法
- [運用ガイド](./phase1-operations.md) - 日常運用の手順
- [検証チェックリスト](./phase1-validation-checklist.md) - セットアップ完了の確認
- [クイックスタート](./quickstart.md) - 簡易版セットアップ手順

## サンプルファイル

- `examples/openresty/nginx.conf` - nginx.conf のサンプル（Forgejo 用、自己完結型）
- `examples/forgejo/run.sh` - Forgejo 起動スクリプトのサンプル

> **実際の設定ファイル:**
> - `config/openresty/nginx-forgejo.conf` - Forgejo 用のメイン設定（include 使用）
> - `config/openresty/conf.d/forgejo.conf` - Forgejo サーバーブロック定義
