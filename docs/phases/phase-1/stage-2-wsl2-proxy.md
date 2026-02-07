# Stage 2: WSL2 プロキシ設定

## 概要

OpenResty から WSL2 内のサービスへ HTTP リクエストをプロキシする仕組みを構築する。WSL2 の IP アドレス管理方法も確立する。

## ブランチ戦略

- ブランチ名: `phase1/stage-2-wsl2-proxy`
- マージ先: `master`

## インプット（前提条件）

- Stage 1 完了（OpenResty が Windows 上で動作している）
- WSL2 (Ubuntu 24.04) がインストール済み
- WSL2 内でテスト用 HTTP サーバーが起動可能（Python http.server 等）

## 目標

- WSL2 の IP アドレスを安定して取得できる
- OpenResty から WSL2 内サービスへプロキシできる
- WSL2 IP 変更時の対応方法を確立する

## 手段

- WSL2 の IP アドレス取得スクリプトを作成
- nginx.conf に upstream と proxy_pass を設定
- IP 変更時の自動更新スクリプトを整備

## ディレクトリ構成

```
[WSL2] /home/kh/prj/flatnet/
       ├── config/
       │   └── openresty/
       │       ├── nginx.conf          ← Stage 2 でプロキシ設定を追加
       │       └── conf.d/
       │           ├── proxy-params.conf     ← プロキシ共通設定
       │           └── websocket-params.conf ← WebSocket 対応設定
       └── scripts/
           ├── deploy-config.sh        ← Stage 1 で作成済み
           ├── get-wsl2-ip.sh          ← WSL2 IP 取得
           └── update-upstream.sh      ← upstream 更新

[Windows] F:\flatnet\
          ├── openresty\               ← OpenResty 本体
          ├── config\
          │   ├── nginx.conf           ← デプロイ先
          │   └── conf.d\              ← 共通設定デプロイ先
          ├── logs\
          └── scripts\
              ├── get-wsl2-ip.ps1           ← WSL2 IP 取得
              └── update-nginx-upstream.ps1 ← upstream 更新
```

## Sub-stages

### Sub-stage 2.1: WSL2 IP 取得方法の確立

**内容:**

- WSL2 内から IP を取得するコマンドの確認
- Windows 側から WSL2 IP を取得する方法
- IP アドレス取得スクリプトの作成

**手順:**

1. **WSL2 内から IP を取得:**

```bash
# WSL2 (Ubuntu) で実行
ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1
```

2. **Windows 側から WSL2 IP を取得:**

```powershell
# PowerShell で実行
(wsl hostname -I).Trim().Split()[0]
```

3. **WSL2 側スクリプト作成:**

ファイル: `/home/kh/prj/flatnet/scripts/get-wsl2-ip.sh`

```bash
#!/bin/bash
# WSL2 の IP アドレスを取得
ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1
```

```bash
chmod +x /home/kh/prj/flatnet/scripts/get-wsl2-ip.sh
```

4. **Windows 側スクリプトディレクトリ作成 (PowerShell):**

```powershell
New-Item -ItemType Directory -Path F:\flatnet\scripts -Force
```

5. **Windows 側スクリプト作成:**

ファイル: `F:\flatnet\scripts\get-wsl2-ip.ps1`

```powershell
# WSL2 の IP アドレスを取得
$wsl2_ip = (wsl hostname -I).Trim().Split()[0]
Write-Output $wsl2_ip
```

**完了条件:**

- [ ] WSL2 内からスクリプトで IP を取得できる
  ```bash
  ./scripts/get-wsl2-ip.sh
  # 期待出力: 172.x.x.x 形式の IP アドレス
  ```
- [ ] Windows 側からスクリプトで IP を取得できる
  ```powershell
  F:\flatnet\scripts\get-wsl2-ip.ps1
  # 期待出力: 172.x.x.x 形式の IP アドレス
  ```

### Sub-stage 2.2: 静的プロキシ設定

**内容:**

- WSL2 内でテストサーバーを起動
- nginx.conf に WSL2 向け upstream を追加
- location ブロックで proxy_pass を設定

**手順:**

1. **WSL2 内でテストサーバーを起動:**

```bash
# WSL2 (Ubuntu) で実行
mkdir -p ~/test-server
echo "<html><body><h1>WSL2 Test Server</h1></body></html>" > ~/test-server/index.html
cd ~/test-server && python3 -m http.server 8080
```

2. **WSL2 の IP アドレスを確認:**

```bash
./scripts/get-wsl2-ip.sh
# 例: 172.25.160.1
```

3. **nginx.conf にプロキシ設定を追加:**

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

    # WSL2 バックエンド（IP は環境に応じて変更）
    upstream wsl2_backend {
        server 172.25.160.1:8080;  # WSL2 IP を設定
    }

    server {
        listen 80;
        server_name localhost;

        # ヘルスチェック用エンドポイント
        location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
        }

        # WSL2 へのプロキシ
        location /wsl2/ {
            proxy_pass http://wsl2_backend/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # デフォルト（Stage 1 のテストページ）
        location / {
            root   F:/flatnet/openresty/html;
            index  index.html;
        }
    }
}
```

4. **設定をデプロイしてテスト:**

```bash
# WSL2 から実行
./scripts/deploy-config.sh --reload
```

**完了条件:**

- [ ] WSL2 内でテストサーバーが起動している
  ```bash
  curl http://localhost:8080/
  # 期待出力: WSL2 Test Server の HTML
  ```
- [ ] OpenResty 経由で WSL2 にアクセスできる
  ```powershell
  (Invoke-WebRequest -Uri http://localhost/wsl2/).Content
  # 期待出力: WSL2 Test Server の HTML
  ```
- [ ] 設定テストが成功する
  ```powershell
  F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t
  # 期待出力: test is successful
  ```

### Sub-stage 2.3: IP 更新スクリプト

**内容:**

WSL2 再起動時に IP アドレスが変わるため、nginx.conf の upstream を自動更新するスクリプトを作成する。

> **設計判断:** Lua による動的 IP 解決は複雑になるため、起動時スクリプト方式を採用。

**手順:**

1. **Windows 側更新スクリプト作成:**

ファイル: `F:\flatnet\scripts\update-nginx-upstream.ps1`

```powershell
# WSL2 IP を取得して nginx.conf の upstream を更新
param(
    [switch]$Reload
)

$configPath = "F:\flatnet\config\nginx.conf"
$nginxBin = "F:\flatnet\openresty\nginx.exe"

# WSL2 IP を取得
$wsl2_ip = (wsl hostname -I).Trim().Split()[0]
if (-not $wsl2_ip) {
    Write-Error "Failed to get WSL2 IP address"
    exit 1
}
Write-Host "WSL2 IP: $wsl2_ip"

# nginx.conf の upstream IP を置換
$content = Get-Content $configPath -Raw
$newContent = $content -replace 'server \d+\.\d+\.\d+\.\d+:', "server ${wsl2_ip}:"
$newContent | Set-Content $configPath -NoNewline

Write-Host "Updated $configPath"

# 設定テスト
& $nginxBin -c $configPath -t
if ($LASTEXITCODE -ne 0) {
    Write-Error "Configuration test failed"
    exit 1
}

# リロード（オプション）
if ($Reload) {
    & $nginxBin -c $configPath -s reload
    Write-Host "OpenResty reloaded"
}

Write-Host "Done."
```

2. **WSL2 側更新スクリプト作成:**

ファイル: `/home/kh/prj/flatnet/scripts/update-upstream.sh`

```bash
#!/bin/bash
set -euo pipefail

# WSL2 IP を取得して nginx.conf を更新

CONFIG_FILE="/home/kh/prj/flatnet/config/openresty/nginx.conf"
WIN_CONFIG="/mnt/f/flatnet/config/nginx.conf"

# WSL2 IP を取得
WSL2_IP=$(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
if [ -z "${WSL2_IP}" ]; then
    echo "Error: Failed to get WSL2 IP"
    exit 1
fi
echo "WSL2 IP: ${WSL2_IP}"

# nginx.conf の upstream IP を置換（Git 管理側）
sed -i -E "s/server [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:/server ${WSL2_IP}:/g" "${CONFIG_FILE}"
echo "Updated ${CONFIG_FILE}"

# デプロイ
cd /home/kh/prj/flatnet
./scripts/deploy-config.sh "$@"
```

```bash
chmod +x /home/kh/prj/flatnet/scripts/update-upstream.sh
```

**使用方法:**

```bash
# WSL2 から: IP 更新 + デプロイ
./scripts/update-upstream.sh

# WSL2 から: IP 更新 + デプロイ + リロード
./scripts/update-upstream.sh --reload

# Windows から: IP 更新 + リロード
F:\flatnet\scripts\update-nginx-upstream.ps1 -Reload
```

**完了条件:**

- [ ] スクリプトで WSL2 IP を nginx.conf に反映できる
  ```bash
  ./scripts/update-upstream.sh
  grep "server 172" /home/kh/prj/flatnet/config/openresty/nginx.conf
  # 期待出力: server 172.x.x.x:8080; が表示される
  ```
- [ ] WSL2 再起動後、スクリプト実行でプロキシが復旧する
  ```bash
  # WSL2 再起動後
  ./scripts/update-upstream.sh --reload
  curl http://localhost/wsl2/  # Windows 側から
  # 期待出力: WSL2 のコンテンツ
  ```

### Sub-stage 2.4: プロキシヘッダーの調整

**内容:**

- プロキシヘッダーの設定
- WebSocket 対応の準備（Forgejo で必要）
- 共通設定のスニペット化

**手順:**

1. **プロキシ共通設定ファイル作成:**

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

2. **WebSocket 対応設定ファイル作成:**

ファイル: `/home/kh/prj/flatnet/config/openresty/conf.d/websocket-params.conf`

```nginx
# WebSocket 対応設定
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

3. **nginx.conf で include:**

```nginx
location /wsl2/ {
    include F:/flatnet/config/conf.d/proxy-params.conf;
    proxy_pass http://wsl2_backend/;
}
```

4. **クライアント IP 確認用テストサーバー:**

```bash
# WSL2 で実行
python3 << 'EOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        headers = {k: v for k, v in self.headers.items()}
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(headers, indent=2).encode())

HTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
EOF
```

**完了条件:**

- [ ] プロキシ経由でクライアント IP が取得できる
  ```powershell
  (Invoke-WebRequest -Uri http://localhost/wsl2/).Content
  # 期待出力: X-Real-IP, X-Forwarded-For ヘッダーが含まれる JSON
  ```
- [ ] 設定ファイルがデプロイされている
  ```powershell
  Test-Path F:\flatnet\config\conf.d\proxy-params.conf
  # 期待出力: True
  ```

## 成果物

### Windows 側

| パス | 説明 |
|------|------|
| `F:\flatnet\config\nginx.conf` | プロキシ設定追加版 |
| `F:\flatnet\config\conf.d\proxy-params.conf` | プロキシ共通設定 |
| `F:\flatnet\config\conf.d\websocket-params.conf` | WebSocket 対応設定 |
| `F:\flatnet\scripts\get-wsl2-ip.ps1` | WSL2 IP 取得スクリプト |
| `F:\flatnet\scripts\update-nginx-upstream.ps1` | upstream 更新スクリプト |

### WSL2 側（Git 管理）

| パス | 説明 |
|------|------|
| `config/openresty/nginx.conf` | プロキシ設定追加版（正） |
| `config/openresty/conf.d/proxy-params.conf` | プロキシ共通設定 |
| `config/openresty/conf.d/websocket-params.conf` | WebSocket 対応設定 |
| `scripts/get-wsl2-ip.sh` | WSL2 IP 取得スクリプト |
| `scripts/update-upstream.sh` | upstream 更新スクリプト |

## 完了条件

| 条件 | 確認コマンド |
|------|-------------|
| WSL2 内のサービスに OpenResty 経由でアクセスできる | `Invoke-WebRequest http://localhost/wsl2/` |
| WSL2 IP を取得できる | `./scripts/get-wsl2-ip.sh` |
| upstream 更新スクリプトが動作する | `./scripts/update-upstream.sh --reload` |
| プロキシヘッダーが設定されている | レスポンスで X-Real-IP を確認 |
| 設定ファイルが Git 管理されている | `git status` |

## トラブルシューティング

### WSL2 に接続できない

**症状:** `502 Bad Gateway` または `Connection refused`

**対処:**

```bash
# WSL2 内でサービスが起動しているか確認
curl http://localhost:8080/

# WSL2 の IP アドレスを確認
./scripts/get-wsl2-ip.sh

# nginx.conf の upstream IP が正しいか確認
grep "server 172" /home/kh/prj/flatnet/config/openresty/nginx.conf

# IP を更新
./scripts/update-upstream.sh --reload
```

### WSL2 IP が取得できない

**症状:** スクリプトが空の結果を返す

**対処:**

```bash
# eth0 インターフェースを確認
ip addr show

# eth0 がない場合（WSL2 再起動が必要な場合）
# Windows 側から
wsl --shutdown
wsl

# 再度 IP を確認
ip addr show eth0
```

### プロキシヘッダーが反映されない

**症状:** バックエンドで X-Real-IP が取得できない

**対処:**

```bash
# conf.d ディレクトリがデプロイされているか確認
ls -la /mnt/f/flatnet/config/conf.d/

# include パスが正しいか確認
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t
```

## 備考

- Lua による動的 IP 解決は複雑になるため、起動時スクリプト方式を採用
- WSL2 のネットワークモード（NAT / mirrored）によって挙動が異なる場合がある
- mirrored モードの場合は `localhost` で接続可能だが、本ドキュメントは NAT モード前提

## 次のステップ

Stage 2 完了後は [Stage 3: Forgejo 統合](./stage-3-forgejo-integration.md) に進み、Forgejo を WSL2 内で起動して OpenResty 経由でアクセスできるようにする。
