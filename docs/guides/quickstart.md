# クイックスタート

最小限の手順で Phase 1（Gateway 基盤）を動作させる。

## 前提

- Windows 10/11 + WSL2 (Ubuntu 24.04)
- Podman インストール済み
- F: ドライブに空き容量あり

## 手順

### 1. OpenResty 配置（Windows）

```powershell
# ディレクトリ作成
New-Item -ItemType Directory -Path F:\flatnet\config, F:\flatnet\logs -Force

# OpenResty をダウンロードして F:\flatnet\openresty に展開
# URL: https://openresty.org/en/download.html
```

### 2. Forgejo 起動（WSL2）

```bash
mkdir -p ~/forgejo/data ~/forgejo/config
podman run -d --name forgejo -p 3000:3000 \
    -v ~/forgejo/data:/data:Z \
    -v ~/forgejo/config:/etc/gitea:Z \
    codeberg.org/forgejo/forgejo:9
```

### 3. nginx.conf 作成

WSL2 の IP を確認:

```bash
ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1
# 例: 172.25.160.1
```

`/mnt/f/flatnet/config/nginx.conf` を作成:

```nginx
worker_processes 1;
error_log F:/flatnet/logs/error.log;
pid       F:/flatnet/logs/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       F:/flatnet/openresty/conf/mime.types;
    access_log    F:/flatnet/logs/access.log;
    client_max_body_size 100M;

    upstream forgejo {
        server 172.25.160.1:3000;  # WSL2 IP に変更
    }

    server {
        listen 80;

        location /health {
            return 200 'OK';
        }

        location / {
            proxy_pass http://forgejo;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
```

### 4. Firewall 設定（PowerShell 管理者）

```powershell
New-NetFirewallRule -DisplayName "OpenResty HTTP" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
```

### 5. OpenResty 起動

```powershell
cd F:\flatnet\openresty
.\nginx.exe -c F:\flatnet\config\nginx.conf
```

### 6. 確認

```powershell
(Invoke-WebRequest http://localhost/health).Content
# 期待: OK
```

ブラウザで `http://localhost/` にアクセスして Forgejo の初期設定を完了。

## 次のステップ

- 詳細: [セットアップガイド](./phase1-setup-guide.md)
- 問題発生時: [トラブルシューティング](./phase1-troubleshooting.md)
- 運用: [運用ガイド](./phase1-operations.md)
