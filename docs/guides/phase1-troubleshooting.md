# Phase 1 トラブルシューティング

Phase 1（Gateway 基盤）でよく発生する問題と解決策。

## 目次

1. [ログの場所](#ログの場所)
2. [ポート競合](#1-ポート競合)
3. [接続できない](#2-接続できない)
4. [WSL2 IP 問題](#3-wsl2-ip-問題)
5. [OpenResty 関連](#4-openresty-関連)
6. [Forgejo 関連](#5-forgejo-関連)
7. [Git 操作関連](#6-git-操作関連)
8. [デバッグのヒント](#デバッグのヒント)

## ログの場所

| コンポーネント | ログの場所 |
|---------------|-----------|
| OpenResty エラーログ | `F:\flatnet\logs\error.log` |
| OpenResty アクセスログ | `F:\flatnet\logs\access.log` |
| Forgejo コンテナログ | `podman logs forgejo` |
| Forgejo ファイルログ | `~/forgejo/data/gitea/log/` |
| systemd サービスログ | `journalctl --user -u forgejo` |

## 1. ポート競合

### 1.1 ポート 80 が使用中

**症状:**

```
nginx: [emerg] bind() to 0.0.0.0:80 failed (10048: address already in use)
```

または

```
nginx: [emerg] bind() to 0.0.0.0:80 failed (10013: permission denied)
```

**対処:**

```powershell
# 使用中のプロセスを確認
netstat -ano | findstr :80
Get-Process -Id <PID>

# IIS が使用している場合
Stop-Service W3SVC
Set-Service W3SVC -StartupType Disabled

# Skype が使用している場合
# Skype 設定でポート 80/443 の使用を無効化

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

# nginx.conf の upstream IP を確認
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
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual" }
```

### 2.4 タイムアウト

**症状:** 接続がタイムアウトする

**対処:**

```bash
# WSL2 から Windows IP への接続確認
ping $(ip route | grep default | awk '{print $3}')

# Windows から WSL2 IP への接続確認（PowerShell）
$wsl2_ip = (wsl hostname -I).Trim().Split()[0]
Test-NetConnection -ComputerName $wsl2_ip -Port 3000
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

# 再度 IP を確認
ip addr show eth0
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
# Ctrl+C で停止
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

# 見つかったパスに合わせて nginx.conf の include を修正
```

### 4.4 OpenResty がリロードできない

**症状:** `nginx.exe -s reload` が失敗する

**対処:**

```powershell
# PID ファイルを確認
Test-Path F:\flatnet\logs\nginx.pid

# プロセスが動いているか確認
Get-Process nginx -ErrorAction SilentlyContinue

# プロセスがない場合は起動
cd F:\flatnet\openresty
.\nginx.exe -c F:\flatnet\config\nginx.conf
```

### 4.5 WSL2 からのデプロイでパスエラー

**症状:** デプロイスクリプトでパスが見つからないエラー

**対処:**

```bash
# Windows ドライブがマウントされているか確認
ls /mnt/f/

# マウントされていない場合
sudo mkdir -p /mnt/f
sudo mount -t drvfs F: /mnt/f

# 永続化する場合は /etc/fstab に追加
echo "F: /mnt/f drvfs defaults 0 0" | sudo tee -a /etc/fstab
```

## 5. Forgejo 関連

### 5.1 コンテナが起動しない

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

### 5.2 データディレクトリの権限エラー

**症状:** `permission denied` エラー

**対処:**

```bash
# 権限を確認
ls -la ~/forgejo/

# SELinux コンテキストを確認（:Z オプションが重要）
ls -laZ ~/forgejo/

# 権限を修正
chmod -R 755 ~/forgejo/data ~/forgejo/config
```

### 5.3 初期設定ウィザードが表示されない

**症状:** すでに設定済みと表示される

**対処:**

```bash
# app.ini が存在するか確認
test -f ~/forgejo/config/app.ini && echo "exists"

# 初期化し直す場合（データも削除される）
podman stop forgejo && podman rm forgejo
rm -rf ~/forgejo/data ~/forgejo/config
mkdir -p ~/forgejo/data ~/forgejo/config
./scripts/forgejo/run.sh
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

### 5.5 リダイレクトが localhost になる

**症状:** ログイン後のリダイレクトが localhost になる

**対処:**

```bash
# app.ini の ROOT_URL を確認
grep ROOT_URL ~/forgejo/config/app.ini

# 正しい URL に修正
vim ~/forgejo/config/app.ini
# ROOT_URL = http://<Windows IP>/

# 再起動
podman restart forgejo
```

## 6. Git 操作関連

### 6.0 ユーザー登録ができない

**症状:** 新規ユーザー登録ページにアクセスできない、または登録ボタンがない

**対処:**

```bash
# app.ini で登録が無効化されているか確認
grep DISABLE_REGISTRATION ~/forgejo/config/app.ini

# 登録を有効にする場合（管理者が手動でユーザーを追加することも可能）
# vim ~/forgejo/config/app.ini
# [service]
# DISABLE_REGISTRATION = false

# 再起動
podman restart forgejo
```

> **注意:** セキュリティ上、運用環境では `DISABLE_REGISTRATION = true` を推奨します。管理者は Forgejo の管理画面からユーザーを追加できます。

### 6.1 Git push で認証エラー

**症状:** `Authentication failed`

**対処:**

```bash
# 認証キャッシュをクリア
git credential-cache exit

# ユーザー名/パスワードを再入力

# または Personal Access Token を使用
# Forgejo Web UI > 設定 > アプリケーション > アクセストークン
```

### 6.2 大きなファイルの push でタイムアウト

**症状:** `fatal: the remote end hung up unexpectedly`

**対処:**

```bash
# Git のバッファサイズを増加
git config --global http.postBuffer 524288000

# nginx.conf の client_max_body_size を確認・増加
grep client_max_body_size /home/kh/prj/flatnet/config/openresty/nginx.conf
# 必要に応じて 500M や 1G に増加
```

### 6.3 git clone が遅い

**症状:** clone に非常に時間がかかる

**対処:**

```bash
# 浅いクローンを試す
git clone --depth 1 http://<Windows IP>/user/repo.git

# 圧縮を無効にする
git config --global core.compression 0
```

### 6.4 SSL 証明書エラー

**症状:** `SSL certificate problem`

**対処:**

Phase 1 では HTTP のみを使用しています。HTTPS を使用する場合は証明書の設定が必要です。

```bash
# 一時的に SSL 検証を無効化（非推奨）
git config --global http.sslVerify false

# または HTTP を使用
git clone http://<Windows IP>/user/repo.git
```

## デバッグのヒント

### 設定テスト

```powershell
# nginx 設定の文法チェック（Forgejo 用）
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx-forgejo.conf -t

# または Stage 2 の WSL2 プロキシ設定をテスト
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t
```

### 詳細なリクエスト確認

```bash
# curl で詳細表示
curl -v http://localhost/

# ヘッダーのみ確認
curl -I http://localhost/

# リダイレクトを追跡
curl -L -v http://localhost/user/login
```

### コンテナログ確認

```bash
# 最新50行
podman logs forgejo --tail 50

# リアルタイム監視
podman logs forgejo -f

# タイムスタンプ付き
podman logs forgejo -t
```

### OpenResty ログ確認

```powershell
# エラーログ（最新50行）
Get-Content F:\flatnet\logs\error.log -Tail 50

# アクセスログ（最新50行）
Get-Content F:\flatnet\logs\access.log -Tail 50

# リアルタイム監視
Get-Content F:\flatnet\logs\error.log -Wait
```

### ネットワーク確認

```bash
# WSL2 側
ip addr show eth0
ss -tlnp | grep LISTEN

# ルーティング確認
ip route
```

```powershell
# Windows 側
Get-NetIPAddress -AddressFamily IPv4
netstat -ano | findstr LISTENING
```

### systemd ジャーナル確認

```bash
# Forgejo サービスのログ
journalctl --user -u forgejo

# 最新のエントリ
journalctl --user -u forgejo -n 50

# リアルタイム
journalctl --user -u forgejo -f
```

## 問題が解決しない場合

1. ログを確認して具体的なエラーメッセージを特定
2. [運用ガイド](./phase1-operations.md) で正しい手順を再確認
3. [セットアップガイド](./phase1-setup-guide.md) で設定を見直し
4. [検証チェックリスト](./phase1-validation-checklist.md) で各項目を確認

## 関連ドキュメント

- [セットアップガイド](./phase1-setup-guide.md)
- [運用ガイド](./phase1-operations.md)
- [検証チェックリスト](./phase1-validation-checklist.md)
- [クイックスタート](./quickstart.md)
