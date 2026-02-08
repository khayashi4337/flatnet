# Phase 1 運用ガイド

Phase 1（Gateway 基盤）の日常運用手順。

## 目次

1. [起動/停止コマンド](#起動停止コマンド)
2. [ログ確認](#ログ確認)
3. [設定変更手順](#設定変更手順)
4. [バックアップ](#バックアップ)
5. [リストア](#リストア)
6. [アップデート](#アップデート)
7. [定期メンテナンス](#定期メンテナンス)
8. [監視](#監視)

## 起動/停止コマンド

### OpenResty

#### 手動管理（サービス化していない場合）

> **注意:** Forgejo を使用する場合は `nginx-forgejo.conf` を指定します。

| 操作 | コマンド（PowerShell） |
|------|------------------------|
| 起動 | `cd F:\flatnet\openresty; .\nginx.exe -c F:\flatnet\config\nginx-forgejo.conf` |
| 停止 | `.\nginx.exe -c F:\flatnet\config\nginx-forgejo.conf -s stop` |
| リロード | `.\nginx.exe -c F:\flatnet\config\nginx-forgejo.conf -s reload` |
| 設定テスト | `.\nginx.exe -c F:\flatnet\config\nginx-forgejo.conf -t` |
| プロセス確認 | `Get-Process nginx -ErrorAction SilentlyContinue` |
| 強制終了 | `Stop-Process -Name nginx -Force` |

#### サービス管理（NSSM 使用時）

| 操作 | コマンド |
|------|----------|
| 起動 | `Start-Service OpenResty` |
| 停止 | `Stop-Service OpenResty` |
| 再起動 | `Restart-Service OpenResty` |
| 状態確認 | `Get-Service OpenResty` |

### Forgejo

#### Podman 直接操作

| 操作 | コマンド（WSL2） |
|------|------------------|
| 起動 | `podman start forgejo` |
| 停止 | `podman stop forgejo` |
| 再起動 | `podman restart forgejo` |
| 状態確認 | `podman ps --filter name=forgejo` |
| ログ確認 | `podman logs forgejo --tail 50` |
| コンテナに入る | `podman exec -it forgejo /bin/bash` |

#### systemd サービス管理（Quadlet 使用時）

| 操作 | コマンド |
|------|----------|
| 起動 | `systemctl --user start forgejo` |
| 停止 | `systemctl --user stop forgejo` |
| 再起動 | `systemctl --user restart forgejo` |
| 状態確認 | `systemctl --user status forgejo` |
| 有効化 | `systemctl --user enable forgejo` |
| 無効化 | `systemctl --user disable forgejo` |
| ログ確認 | `journalctl --user -u forgejo` |

## ログ確認

### OpenResty ログ（PowerShell）

```powershell
# エラーログ（最新 50 行）
Get-Content F:\flatnet\logs\error.log -Tail 50

# アクセスログ（最新 50 行）
Get-Content F:\flatnet\logs\access.log -Tail 50

# リアルタイム監視
Get-Content F:\flatnet\logs\error.log -Wait

# 特定の文字列を検索
Select-String -Path F:\flatnet\logs\error.log -Pattern "error"
```

### Forgejo ログ（WSL2）

```bash
# コンテナログ（最新 50 行）
podman logs forgejo --tail 50

# リアルタイム監視
podman logs forgejo -f

# タイムスタンプ付き
podman logs forgejo -t --tail 50

# systemd ジャーナル
journalctl --user -u forgejo -f

# ファイルログ
ls -la ~/forgejo/data/gitea/log/
tail -f ~/forgejo/data/gitea/log/*.log
```

## 設定変更手順

### nginx 設定の変更

> **注意:** Forgejo を使用する場合は `nginx-forgejo.conf` と `conf.d/forgejo.conf` を編集します。
> Stage 2 の WSL2 プロキシのみを使用する場合は `nginx.conf` を編集します。

1. **WSL2 側で設定ファイルを編集:**

```bash
# Forgejo 用（Stage 3）
vim /home/kh/prj/flatnet/config/openresty/conf.d/forgejo.conf

# WSL2 プロキシ用（Stage 2）
vim /home/kh/prj/flatnet/config/openresty/nginx.conf
```

2. **設定をデプロイしてテスト:**

```bash
# デプロイスクリプトを使用（推奨）
./scripts/deploy-config.sh --forgejo  # Forgejo 用
./scripts/deploy-config.sh            # WSL2 プロキシ用

# または手動でコピー
cp /home/kh/prj/flatnet/config/openresty/*.conf /mnt/f/flatnet/config/
cp -r /home/kh/prj/flatnet/config/openresty/conf.d/* /mnt/f/flatnet/config/conf.d/
```

3. **設定テスト（PowerShell）:**

```powershell
# Forgejo 用
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx-forgejo.conf -t

# WSL2 プロキシ用
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t
```

4. **設定をリロード（PowerShell）:**

```powershell
# サービスの場合
Restart-Service OpenResty

# 手動の場合（Forgejo 用）
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx-forgejo.conf -s reload

# 手動の場合（WSL2 プロキシ用）
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -s reload
```

### WSL2 IP 更新

WSL2 再起動後に IP アドレスが変わった場合:

```bash
# 方法1: スクリプトを使用（推奨）
./scripts/update-upstream.sh --reload

# 方法2: 手動で更新
# 1. IP を確認
ip addr show eth0 | grep 'inet '

# 2. nginx.conf を編集
vim /home/kh/prj/flatnet/config/openresty/nginx.conf
# upstream の server 行を更新

# 3. デプロイとリロード
./scripts/deploy-config.sh --reload
```

### Forgejo 設定変更

1. **設定ファイルを編集:**

```bash
vim ~/forgejo/config/app.ini
```

2. **Forgejo を再起動:**

```bash
# systemd サービスの場合
systemctl --user restart forgejo

# Podman 直接の場合
podman restart forgejo
```

主要な設定項目:

| 設定 | 場所 | 説明 |
|------|------|------|
| `ROOT_URL` | `[server]` | 外部からアクセスする URL |
| `DOMAIN` | `[server]` | サーバーのドメイン名 |
| `DISABLE_SSH` | `[server]` | SSH アクセスの無効化 |
| `LFS_START_SERVER` | `[server]` | Git LFS の有効化 |
| `DISABLE_REGISTRATION` | `[service]` | 新規登録の無効化 |

## バックアップ

### 対象データ

| データ | 場所 | 重要度 | バックアップ方法 |
|--------|------|--------|-----------------|
| Forgejo データ | `~/forgejo/data/` | 高 | tar 圧縮 |
| Forgejo 設定 | `~/forgejo/config/` | 高 | tar 圧縮 |
| nginx 設定 | `config/openresty/` | 中 | Git 管理 |
| OpenResty ログ | `F:\flatnet\logs\` | 低 | 任意 |

### バックアップ手順

> **セキュリティ注意:** バックアップには認証情報やユーザーデータが含まれます。バックアップファイルは適切に保護してください。

```bash
# Forgejo を停止
systemctl --user stop forgejo
# または: podman stop forgejo

# バックアップディレクトリを作成（パーミッション制限）
mkdir -p ~/backups
chmod 700 ~/backups

# バックアップ
tar czf ~/backups/forgejo-backup-$(date +%Y%m%d).tar.gz ~/forgejo/

# バックアップファイルのパーミッションを制限
chmod 600 ~/backups/forgejo-backup-*.tar.gz

# Forgejo を再開
systemctl --user start forgejo
# または: podman start forgejo

# バックアップを確認
ls -lh ~/backups/
```

### 自動バックアップ（cron）

```bash
# crontab を編集
crontab -e

# 毎日 3:00 にバックアップ（7日間保持）
0 3 * * * systemctl --user stop forgejo && tar czf ~/backups/forgejo-backup-$(date +\%Y\%m\%d).tar.gz ~/forgejo/ && systemctl --user start forgejo && find ~/backups -name "forgejo-backup-*.tar.gz" -mtime +7 -delete
```

## リストア

### リストア手順

```bash
# Forgejo を停止
systemctl --user stop forgejo
# または: podman stop forgejo

# 既存データを退避
mv ~/forgejo ~/forgejo.old

# バックアップからリストア
tar xzf ~/backups/forgejo-backup-YYYYMMDD.tar.gz -C ~/

# ディレクトリ構造を確認
ls -la ~/forgejo/

# Forgejo を再開
systemctl --user start forgejo

# 動作確認
curl http://localhost:3000/

# 動作確認後、古いデータを削除
rm -rf ~/forgejo.old
```

## アップデート

### Forgejo のアップデート

```bash
# 現在のバージョンを確認
podman inspect forgejo | grep -i version

# バックアップを取得
tar czf ~/backups/forgejo-backup-pre-update-$(date +%Y%m%d).tar.gz ~/forgejo/

# 新しいイメージを pull
podman pull codeberg.org/forgejo/forgejo:9

# Forgejo を再起動
systemctl --user restart forgejo
# または
podman stop forgejo && podman rm forgejo
./scripts/forgejo/run.sh

# バージョンを確認
podman inspect forgejo | grep -i version
```

**注意:** メジャーバージョンアップ時は、リリースノートを確認して移行手順に従ってください。

### OpenResty のアップデート

1. **新しいバージョンをダウンロード:**

   https://openresty.org/en/download.html から Windows 版をダウンロード

2. **OpenResty を停止:**

```powershell
Stop-Service OpenResty
# または: .\nginx.exe -s stop
```

3. **古いバージョンを退避:**

```powershell
Rename-Item F:\flatnet\openresty F:\flatnet\openresty.old
```

4. **新しいバージョンを展開:**

```powershell
Expand-Archive -Path openresty-x.x.x-win64.zip -DestinationPath F:\flatnet\
Rename-Item "F:\flatnet\openresty-x.x.x-win64" "openresty"
```

5. **OpenResty を起動:**

```powershell
Start-Service OpenResty
# または: cd F:\flatnet\openresty; .\nginx.exe -c F:\flatnet\config\nginx.conf
```

6. **動作確認後、古いバージョンを削除:**

```powershell
Remove-Item -Recurse F:\flatnet\openresty.old
```

## 定期メンテナンス

### ログローテーション

OpenResty のログは手動で管理します:

```powershell
# 古いログを圧縮（月次）
$date = Get-Date -Format "yyyyMM"
Compress-Archive -Path F:\flatnet\logs\*.log -DestinationPath "F:\flatnet\logs\archive-$date.zip"

# ログファイルをクリア
Clear-Content F:\flatnet\logs\access.log
Clear-Content F:\flatnet\logs\error.log

# OpenResty に新しいファイルを開かせる
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -s reopen
```

### ディスク使用量確認

```bash
# Forgejo データ
du -sh ~/forgejo/data/

# Git リポジトリ
du -sh ~/forgejo/data/git/repositories/

# ログ
du -sh ~/forgejo/data/gitea/log/
```

```powershell
# OpenResty ログ
Get-ChildItem F:\flatnet\logs\ | Measure-Object -Property Length -Sum | Select-Object @{n="Size(MB)";e={$_.Sum/1MB}}
```

### コンテナイメージのクリーンアップ

```bash
# 使用していないイメージを削除
podman image prune -a

# ビルドキャッシュを削除
podman system prune
```

## 監視

### ヘルスチェック

```bash
# 定期的なヘルスチェック（WSL2）
while true; do
    echo "$(date): $(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/)"
    sleep 60
done
```

```powershell
# 定期的なヘルスチェック（Windows）
while ($true) {
    $status = (Invoke-WebRequest -Uri http://localhost/health -TimeoutSec 5 -ErrorAction SilentlyContinue).StatusCode
    Write-Host "$(Get-Date): $status"
    Start-Sleep -Seconds 60
}
```

### サービス状態確認スクリプト

```bash
#!/bin/bash
# check-status.sh

echo "=== Flatnet Gateway Status ==="
echo ""

echo "Forgejo Container:"
podman ps --filter name=forgejo --format "  Status: {{.Status}}"

echo ""
echo "Forgejo HTTP:"
echo "  Response: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/)"

echo ""
echo "Gateway HTTP:"
echo "  Response: $(curl -s -o /dev/null -w '%{http_code}' http://localhost/health 2>/dev/null || echo 'N/A')"

echo ""
echo "WSL2 IP:"
echo "  $(ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)"
```

### アラート設定（オプション）

systemd タイマーでヘルスチェックを自動化:

```ini
# ~/.config/systemd/user/forgejo-health.service
[Unit]
Description=Forgejo Health Check

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'curl -sf http://localhost:3000/ || systemctl --user restart forgejo'
```

```ini
# ~/.config/systemd/user/forgejo-health.timer
[Unit]
Description=Forgejo Health Check Timer

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl --user enable --now forgejo-health.timer
```

## 関連ドキュメント

- [セットアップガイド](./phase1-setup-guide.md) - 初期セットアップ手順
- [トラブルシューティング](./phase1-troubleshooting.md) - 問題発生時の対処法
- [検証チェックリスト](./phase1-validation-checklist.md) - セットアップ完了の確認
- [クイックスタート](./quickstart.md) - 簡易版セットアップ手順
