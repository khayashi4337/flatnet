# Phase 1 運用ガイド

Phase 1（Gateway 基盤）の日常運用手順。

## 起動/停止コマンド

### OpenResty

| 操作 | コマンド（PowerShell） |
|------|------------------------|
| 起動 | `cd F:\flatnet\openresty; .\nginx.exe -c F:\flatnet\config\nginx.conf` |
| 停止 | `.\nginx.exe -c F:\flatnet\config\nginx.conf -s stop` |
| リロード | `.\nginx.exe -c F:\flatnet\config\nginx.conf -s reload` |
| 設定テスト | `.\nginx.exe -c F:\flatnet\config\nginx.conf -t` |
| プロセス確認 | `Get-Process nginx -ErrorAction SilentlyContinue` |
| 強制終了 | `Stop-Process -Name nginx -Force` |

サービス化している場合:

| 操作 | コマンド |
|------|----------|
| 起動 | `Start-Service OpenResty` |
| 停止 | `Stop-Service OpenResty` |
| 再起動 | `Restart-Service OpenResty` |
| 状態確認 | `Get-Service OpenResty` |

### Forgejo

| 操作 | コマンド（WSL2） |
|------|------------------|
| 起動 | `podman start forgejo` |
| 停止 | `podman stop forgejo` |
| 再起動 | `podman restart forgejo` |
| 状態確認 | `podman ps --filter name=forgejo` |
| ログ確認 | `podman logs forgejo --tail 50` |

systemd サービスを使用している場合:

| 操作 | コマンド |
|------|----------|
| 起動 | `systemctl --user start forgejo` |
| 停止 | `systemctl --user stop forgejo` |
| 再起動 | `systemctl --user restart forgejo` |
| 状態確認 | `systemctl --user status forgejo` |

## ログ確認

### OpenResty ログ（PowerShell）

```powershell
# エラーログ（最新 50 行）
Get-Content F:\flatnet\logs\error.log -Tail 50

# アクセスログ（最新 50 行）
Get-Content F:\flatnet\logs\access.log -Tail 50

# リアルタイム監視
Get-Content F:\flatnet\logs\error.log -Wait
```

### Forgejo ログ（WSL2）

```bash
# コンテナログ
podman logs forgejo --tail 50

# リアルタイム監視
podman logs forgejo -f

# systemd ジャーナル
journalctl --user -u forgejo -f
```

## 設定変更手順

### nginx.conf の変更

1. WSL2 側で設定ファイルを編集:

```bash
vim /home/kh/prj/flatnet/config/openresty/nginx.conf
```

2. 設定をデプロイしてテスト:

```bash
cp /home/kh/prj/flatnet/config/openresty/nginx.conf /mnt/f/flatnet/config/
```

```powershell
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t
```

3. 設定をリロード:

```powershell
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -s reload
```

### WSL2 IP 更新

WSL2 再起動後に IP アドレスが変わった場合:

```bash
# IP を確認
ip addr show eth0 | grep 'inet '

# nginx.conf を更新（手動）
vim /home/kh/prj/flatnet/config/openresty/nginx.conf
# upstream forgejo の server 行を更新

# またはスクリプト使用
./scripts/update-upstream.sh --reload
```

### Forgejo 設定変更

1. 設定ファイルを編集:

```bash
vim ~/forgejo/config/app.ini
```

2. Forgejo を再起動:

```bash
podman restart forgejo
# または
systemctl --user restart forgejo
```

## バックアップ

### 対象データ

| データ | 場所 | 重要度 |
|--------|------|--------|
| Forgejo データ | `~/forgejo/data/` | 高 |
| Forgejo 設定 | `~/forgejo/config/` | 高 |
| nginx 設定 | `config/openresty/` | Git 管理 |

### バックアップ手順

```bash
# Forgejo を停止
systemctl --user stop forgejo
# または: podman stop forgejo

# バックアップ
tar czf forgejo-backup-$(date +%Y%m%d).tar.gz ~/forgejo/

# Forgejo を再開
systemctl --user start forgejo
```

### リストア手順

```bash
# Forgejo を停止
systemctl --user stop forgejo

# 既存データを退避
mv ~/forgejo ~/forgejo.old

# バックアップからリストア
tar xzf forgejo-backup-YYYYMMDD.tar.gz -C ~/

# Forgejo を再開
systemctl --user start forgejo

# 動作確認後、古いデータを削除
rm -rf ~/forgejo.old
```

## アップデート

### Forgejo のアップデート

```bash
# 新しいイメージを pull
podman pull codeberg.org/forgejo/forgejo:9

# Forgejo を再起動
systemctl --user restart forgejo
# または
podman stop forgejo && podman rm forgejo
./scripts/forgejo/run.sh
```

### OpenResty のアップデート

1. 新しいバージョンを https://openresty.org/en/download.html からダウンロード
2. OpenResty を停止:

```powershell
Stop-Service OpenResty
# または: .\nginx.exe -s stop
```

3. 古いバージョンを退避:

```powershell
Rename-Item F:\flatnet\openresty F:\flatnet\openresty.old
```

4. 新しいバージョンを展開:

```powershell
Expand-Archive -Path openresty-x.x.x-win64.zip -DestinationPath F:\flatnet\
Rename-Item "F:\flatnet\openresty-x.x.x-win64" "openresty"
```

5. OpenResty を起動:

```powershell
Start-Service OpenResty
```

6. 動作確認後、古いバージョンを削除:

```powershell
Remove-Item -Recurse F:\flatnet\openresty.old
```

## 定期メンテナンス

### ログローテーション

OpenResty のログは手動で管理:

```powershell
# 古いログを圧縮（月次）
$date = Get-Date -Format "yyyyMM"
Compress-Archive -Path F:\flatnet\logs\*.log -DestinationPath "F:\flatnet\logs\archive-$date.zip"
# ログファイルをクリア
Clear-Content F:\flatnet\logs\access.log
Clear-Content F:\flatnet\logs\error.log
# OpenResty に新しいファイルを開かせる
.\nginx.exe -s reopen
```

### ディスク使用量確認

```bash
# Forgejo データ
du -sh ~/forgejo/data/

# Git リポジトリ
du -sh ~/forgejo/data/git/repositories/
```

```powershell
# OpenResty ログ
Get-ChildItem F:\flatnet\logs\ | Measure-Object -Property Length -Sum
```

## 関連ドキュメント

- [クイックスタート](./quickstart.md)
- [セットアップガイド](./phase1-setup-guide.md)
- [トラブルシューティング](./phase1-troubleshooting.md)
