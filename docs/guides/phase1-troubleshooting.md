# Phase 1 トラブルシューティング

Phase 1（Gateway 基盤）でよく発生する問題と解決策。

## ログの場所

| コンポーネント | ログの場所 |
|---------------|-----------|
| OpenResty エラーログ | `F:\flatnet\logs\error.log` |
| OpenResty アクセスログ | `F:\flatnet\logs\access.log` |
| Forgejo | `podman logs forgejo` |
| Forgejo（ファイル） | `~/forgejo/data/gitea/log/` |
| systemd サービス | `journalctl --user -u forgejo` |

## 1. ポート競合

### 1.1 ポート 80 が使用中

**症状:**

```
nginx: [emerg] bind() to 0.0.0.0:80 failed (10048: address already in use)
```

**対処:**

```powershell
# 使用中のプロセスを確認
netstat -ano | findstr :80
Get-Process -Id <PID>

# IIS が使用している場合
Stop-Service W3SVC
Set-Service W3SVC -StartupType Disabled

# 別のポートを使用する場合
# nginx.conf で listen 8080; に変更
```

### 1.2 ポート 3000 が使用中

**症状:** Forgejo コンテナが起動しない

**対処:**

```bash
# 使用中のプロセスを確認
ss -tlnp | grep 3000

# 別のポートを使用
podman run -d --name forgejo -p 3001:3000 ...
# nginx.conf の upstream を 3001 に変更
```

## 2. 接続できない

### 2.1 502 Bad Gateway

**症状:** ブラウザで 502 エラー

**原因:** OpenResty が WSL2 のバックエンドに接続できない

**対処:**

```bash
# WSL2 内で Forgejo が起動しているか確認
podman ps --filter name=forgejo
curl http://localhost:3000/

# WSL2 IP が正しいか確認
ip addr show eth0 | grep 'inet '

# nginx.conf の upstream IP を更新
grep "server 172" /home/kh/prj/flatnet/config/openresty/nginx.conf

# 設定を更新してリロード
./scripts/update-upstream.sh --reload
```

### 2.2 Connection refused

**症状:** curl で接続拒否

**対処:**

```bash
# サービスが起動しているか確認
podman ps

# Forgejo を手動で起動
podman start forgejo

# または再作成
./scripts/forgejo/run.sh
```

### 2.3 LAN からアクセスできない

**症状:** localhost では動作するが、他の端末からアクセスできない

**対処:**

```powershell
# Firewall ルールの確認
Get-NetFirewallRule -DisplayName "OpenResty*" | Select-Object DisplayName, Enabled

# ネットワークプロファイルを確認（Private でないとブロックされる可能性）
Get-NetConnectionProfile

# プロファイルを Private に変更
Set-NetConnectionProfile -InterfaceAlias "イーサネット" -NetworkCategory Private

# Windows IP を確認
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq "Dhcp" }
```

## 3. WSL2 IP 問題

### 3.1 WSL2 再起動で IP が変わった

**症状:** WSL2 再起動後に 502 エラー

**対処:**

```bash
# 新しい IP を確認
ip addr show eth0 | grep 'inet '

# nginx.conf を更新
./scripts/update-upstream.sh --reload
```

### 3.2 WSL2 IP が取得できない

**症状:** スクリプトが空の結果を返す

**対処:**

```bash
# eth0 インターフェースを確認
ip addr show

# eth0 がない場合、WSL2 を再起動
# Windows 側から:
wsl --shutdown
wsl
```

### 3.3 Windows から WSL2 に接続できない

**症状:** PowerShell から WSL2 IP に ping が通らない

**対処:**

```powershell
# WSL2 IP を確認
(wsl hostname -I).Trim().Split()[0]

# WSL2 内のサービスに直接接続テスト
$wsl2_ip = (wsl hostname -I).Trim().Split()[0]
Test-NetConnection -ComputerName $wsl2_ip -Port 3000
```

## 4. OpenResty 関連

### 4.1 nginx.exe が起動しない

**症状:** コマンドを実行しても何も起動しない

**対処:**

```powershell
# ログディレクトリが存在するか確認
Test-Path F:\flatnet\logs
New-Item -ItemType Directory -Path F:\flatnet\logs -Force

# 設定テスト
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t

# フォアグラウンドで起動してエラーを確認
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -g "daemon off;"
```

### 4.2 設定エラー

**症状:** `nginx: [emerg] unknown directive`

**対処:**

```powershell
# 設定ファイルの構文チェック
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t

# エラーログを確認
Get-Content F:\flatnet\logs\error.log -Tail 20
```

### 4.3 mime.types が見つからない

**症状:** `open() "F:/flatnet/openresty/conf/mime.types" failed`

**対処:**

```powershell
# mime.types の場所を確認
Get-ChildItem -Path F:\flatnet\openresty -Recurse -Filter mime.types

# nginx.conf の include パスを修正
```

## 5. Forgejo 関連

### 5.1 コンテナが起動しない

**症状:** `podman ps` でコンテナが表示されない

**対処:**

```bash
# コンテナのログを確認
podman logs forgejo

# 手動で起動してエラーを確認
podman run -it --rm \
    -p 3000:3000 \
    -v ~/forgejo/data:/data:Z \
    -v ~/forgejo/config:/etc/gitea:Z \
    codeberg.org/forgejo/forgejo:9
```

### 5.2 Git push で認証エラー

**症状:** `Authentication failed`

**対処:**

```bash
# 認証キャッシュをクリア
git credential-cache exit

# Personal Access Token を使用
# Forgejo Web UI > 設定 > アプリケーション > アクセストークン
```

### 5.3 大きなファイルの push でタイムアウト

**症状:** `fatal: the remote end hung up unexpectedly`

**対処:**

```bash
# Git のバッファサイズを増加
git config --global http.postBuffer 524288000

# nginx.conf の client_max_body_size を確認・増加
grep client_max_body_size /home/kh/prj/flatnet/config/openresty/nginx.conf
```

### 5.4 systemd サービスが起動しない

**症状:** `systemctl --user status forgejo` でエラー

**対処:**

```bash
# WSL2 で systemd が有効か確認
ps -p 1 -o comm=
# 期待: systemd

# systemd が無効な場合、/etc/wsl.conf を設定
# [boot]
# systemd=true
# 設定後: wsl --shutdown

# Quadlet 定義の文法チェック
/usr/libexec/podman/quadlet --dryrun ~/.config/containers/systemd/

# ログを確認
journalctl --user -u forgejo
```

## デバッグのヒント

### 設定テスト

```powershell
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t
```

### 詳細なリクエスト確認

```bash
curl -v http://localhost/
```

### コンテナログ確認

```bash
podman logs forgejo --tail 50
```

### OpenResty ログ確認

```powershell
Get-Content F:\flatnet\logs\error.log -Tail 50
Get-Content F:\flatnet\logs\access.log -Tail 50
```

## 関連ドキュメント

- [クイックスタート](./quickstart.md)
- [セットアップガイド](./phase1-setup-guide.md)
- [運用ガイド](./phase1-operations.md)
