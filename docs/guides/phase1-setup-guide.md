# Phase 1 セットアップガイド

Phase 1（Gateway 基盤）の環境構築手順書。

## 前提条件

| 項目 | 要件 |
|------|------|
| OS | Windows 10/11 (21H2 以降) |
| WSL2 | Ubuntu 24.04 |
| Podman | 4.x 以上 |
| メモリ | 8GB 以上推奨 |
| ディスク | F: ドライブに 10GB 以上の空き |

## 1. OpenResty インストール

### 1.1 ディレクトリ作成（PowerShell 管理者）

```powershell
New-Item -ItemType Directory -Path F:\flatnet -Force
New-Item -ItemType Directory -Path F:\flatnet\config -Force
New-Item -ItemType Directory -Path F:\flatnet\logs -Force
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

## 2. WSL2 プロキシ設定

### 2.1 WSL2 側ディレクトリ作成

```bash
mkdir -p /home/kh/prj/flatnet/config/openresty/conf.d
mkdir -p /home/kh/prj/flatnet/scripts
```

### 2.2 nginx.conf 設定

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

    client_max_body_size 100M;

    upstream forgejo {
        server 172.x.x.x:3000;  # WSL2 IP に変更
    }

    server {
        listen 80;
        server_name _;

        location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
        }

        location / {
            include F:/flatnet/config/conf.d/proxy-params.conf;
            proxy_read_timeout 300s;
            proxy_send_timeout 300s;
            proxy_pass http://forgejo;
        }
    }
}
```

### 2.3 プロキシ共通設定

ファイル: `/home/kh/prj/flatnet/config/openresty/conf.d/proxy-params.conf`

```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_connect_timeout 60s;
proxy_send_timeout 60s;
proxy_read_timeout 60s;
```

### 2.4 WSL2 IP 取得

```bash
ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1
```

取得した IP で nginx.conf の `upstream forgejo` を更新。

### 2.5 設定デプロイ

```bash
cp /home/kh/prj/flatnet/config/openresty/nginx.conf /mnt/f/flatnet/config/
mkdir -p /mnt/f/flatnet/config/conf.d
cp /home/kh/prj/flatnet/config/openresty/conf.d/* /mnt/f/flatnet/config/conf.d/
```

## 3. Windows Firewall 設定（PowerShell 管理者）

```powershell
New-NetFirewallRule -DisplayName "OpenResty HTTP" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
New-NetFirewallRule -DisplayName "OpenResty HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow
```

## 4. Forgejo 起動

### 4.1 データディレクトリ作成

```bash
mkdir -p ~/forgejo/data ~/forgejo/config
```

### 4.2 イメージ取得

```bash
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

### 4.4 初期設定

1. ブラウザで `http://localhost:3000/` にアクセス
2. 設定ウィザードを完了:
   - データベースタイプ: SQLite3
   - サーバードメイン: (Windows の LAN IP)
   - Forgejo ベース URL: `http://(Windows IP)/`
   - SSH サーバーポート: 無効化
3. 管理者アカウントを作成

### 4.5 app.ini 設定

`~/forgejo/config/app.ini` を編集:

```ini
[server]
DOMAIN = 192.168.1.100
ROOT_URL = http://192.168.1.100/
HTTP_PORT = 3000
DISABLE_SSH = true
```

```bash
podman restart forgejo
```

## 5. OpenResty 起動

```powershell
cd F:\flatnet\openresty
.\nginx.exe -c F:\flatnet\config\nginx.conf -t  # 設定テスト
.\nginx.exe -c F:\flatnet\config\nginx.conf     # 起動
```

## 6. 動作確認

```powershell
# ヘルスチェック
(Invoke-WebRequest -Uri http://localhost/health).Content
# 期待: OK

# Forgejo アクセス
(Invoke-WebRequest -Uri http://localhost/).StatusCode
# 期待: 200
```

別端末から:

```bash
curl http://<Windows IP>/health
# 期待: OK
```

## 7. 自動起動設定（オプション）

### 7.1 OpenResty サービス化（NSSM 使用）

```powershell
# NSSM をダウンロードして F:\flatnet\ に配置
F:\flatnet\nssm.exe install OpenResty F:\flatnet\openresty\nginx.exe
F:\flatnet\nssm.exe set OpenResty AppDirectory F:\flatnet\openresty
F:\flatnet\nssm.exe set OpenResty AppParameters "-c F:\flatnet\config\nginx.conf"
F:\flatnet\nssm.exe set OpenResty Start SERVICE_AUTO_START
Start-Service OpenResty
```

### 7.2 Forgejo systemd サービス

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

```bash
mkdir -p ~/.config/containers/systemd
cp forgejo.container ~/.config/containers/systemd/
podman stop forgejo && podman rm forgejo
systemctl --user daemon-reload
systemctl --user enable --now forgejo
```

## 関連ドキュメント

- [トラブルシューティング](./phase1-troubleshooting.md)
- [運用ガイド](./phase1-operations.md)
- [クイックスタート](./quickstart.md)
