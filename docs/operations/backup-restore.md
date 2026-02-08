# Flatnet バックアップ・リストア手順

このドキュメントでは、Flatnet システムのバックアップとリストア手順を説明します。

## 目次

1. [バックアップ対象](#バックアップ対象)
2. [バックアップ手順](#バックアップ手順)
3. [リストア手順](#リストア手順)
4. [自動バックアップ設定](#自動バックアップ設定)
5. [リストアテスト](#リストアテスト)
6. [ベストプラクティス](#ベストプラクティス)

---

## バックアップ対象

### 対象一覧

| 対象 | 場所 | 頻度 | 保持期間 | 優先度 |
|------|------|------|----------|--------|
| Gateway 設定 | `F:\flatnet\openresty\conf\` | 変更時 | 世代管理 | 高 |
| CNI Plugin 設定 | `/etc/cni/net.d/` | 変更時 | 世代管理 | 高 |
| Nebula 証明書 | `F:\flatnet\config\nebula\` | 変更時 | 永久保持 | 最高 |
| Prometheus データ | Podman volume: `prometheus_data` | 日次 | 7日 | 中 |
| Grafana ダッシュボード | Grafana API 経由 | 日次 | 7日 | 中 |
| Grafana データベース | Podman volume: `grafana_data` | 日次 | 7日 | 中 |
| Loki データ | Podman volume: `loki_data` | 日次 | 7日 | 低 |
| Alertmanager 設定 | `monitoring/alertmanager/` | 変更時 | 世代管理 | 高 |

### 重要な注意事項

- **CA 秘密鍵 (`ca.key`)**: 最重要。安全なオフライン場所にも保管すること
- **バックアップ先**: `/backup/flatnet/` (WSL2) および `F:\flatnet\backups\` (Windows)
- **暗号化**: 証明書・鍵のバックアップは暗号化を推奨

---

## バックアップ手順

### 手動バックアップ

#### 1. 設定ファイルのバックアップ

**WSL2:**

```bash
#!/bin/bash
# 設定バックアップ

BACKUP_DIR="/backup/flatnet/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# CNI 設定
cp -r /etc/cni/net.d "$BACKUP_DIR/cni-config"

# 監視設定
cp -r ~/prj/flatnet/monitoring/prometheus "$BACKUP_DIR/prometheus-config"
cp -r ~/prj/flatnet/monitoring/alertmanager "$BACKUP_DIR/alertmanager-config"
cp -r ~/prj/flatnet/monitoring/grafana "$BACKUP_DIR/grafana-config"

echo "Backup completed: $BACKUP_DIR"
```

**Windows PowerShell:**

```powershell
# 設定バックアップ
$backupDir = "F:\flatnet\backups\$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $backupDir -Force

# OpenResty 設定
Copy-Item -Recurse F:\flatnet\openresty\conf $backupDir\openresty-conf

# Nebula 設定と証明書
Copy-Item -Recurse F:\flatnet\config\nebula $backupDir\nebula-config

Write-Host "Backup completed: $backupDir"
```

#### 2. Grafana ダッシュボードのエクスポート

```bash
#!/bin/bash
# Grafana ダッシュボードエクスポート

BACKUP_DIR="/backup/flatnet/$(date +%Y%m%d)/grafana-dashboards"
mkdir -p "$BACKUP_DIR"

# Grafana の認証情報（環境変数または直接指定）
GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-flatnet}"

# 全ダッシュボードの UID を取得
dashboard_uids=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
    "$GRAFANA_URL/api/search?type=dash-db" | jq -r '.[].uid')

# 各ダッシュボードをエクスポート
for uid in $dashboard_uids; do
    echo "Exporting dashboard: $uid"
    curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
        "$GRAFANA_URL/api/dashboards/uid/$uid" \
        > "$BACKUP_DIR/$uid.json"
done

echo "Exported $(echo "$dashboard_uids" | wc -w) dashboards to $BACKUP_DIR"
```

#### 3. Prometheus スナップショット

```bash
#!/bin/bash
# Prometheus スナップショット作成

# スナップショット作成
response=$(curl -s -X POST http://localhost:9090/api/v1/admin/tsdb/snapshot)
snapshot_name=$(echo "$response" | jq -r '.data.name')

if [ "$snapshot_name" = "null" ] || [ -z "$snapshot_name" ]; then
    echo "Failed to create snapshot: $response"
    exit 1
fi

echo "Snapshot created: $snapshot_name"

# スナップショットディレクトリを取得（Podman volume 内）
# 注: 実際のパスは Podman volume の場所に依存
echo "Snapshot location: prometheus_data volume: /prometheus/snapshots/$snapshot_name"
```

#### 4. 完全バックアップスクリプト

完全なバックアップは `scripts/backup.sh` を使用します。

```bash
# バックアップ実行
~/prj/flatnet/scripts/backup.sh
```

---

## リストア手順

### 事前確認

1. リストア先の環境が正常に動作していること
2. 現在の設定をバックアップしておくこと（念のため）
3. サービスの停止が必要な場合、影響範囲を確認

### 1. 設定ファイルのリストア

**WSL2:**

```bash
#!/bin/bash
# 設定リストア

BACKUP_DIR="/backup/flatnet/20240101_120000"  # リストア対象の日付

# サービス停止
cd ~/prj/flatnet/monitoring
podman-compose down

# CNI 設定リストア
sudo cp -r "$BACKUP_DIR/cni-config/"* /etc/cni/net.d/

# 監視設定リストア
cp -r "$BACKUP_DIR/prometheus-config/"* ~/prj/flatnet/monitoring/prometheus/
cp -r "$BACKUP_DIR/alertmanager-config/"* ~/prj/flatnet/monitoring/alertmanager/
cp -r "$BACKUP_DIR/grafana-config/"* ~/prj/flatnet/monitoring/grafana/

# サービス再開
podman-compose up -d

echo "Restore completed from: $BACKUP_DIR"
```

**Windows PowerShell:**

```powershell
# 設定リストア
$backupDir = "F:\flatnet\backups\20240101_120000"  # リストア対象

# Gateway 停止
cd F:\flatnet\openresty
.\nginx.exe -s stop

# OpenResty 設定リストア
Copy-Item -Recurse -Force $backupDir\openresty-conf\* F:\flatnet\openresty\conf\

# Nebula 設定リストア
Copy-Item -Recurse -Force $backupDir\nebula-config\* F:\flatnet\config\nebula\

# 設定テスト
.\nginx.exe -t

# Gateway 起動
.\nginx.exe

# Nebula 再起動
Restart-Service Nebula

Write-Host "Restore completed from: $backupDir"
```

### 2. Grafana ダッシュボードのインポート

```bash
#!/bin/bash
# Grafana ダッシュボードインポート

BACKUP_DIR="/backup/flatnet/20240101/grafana-dashboards"
GRAFANA_URL="http://localhost:3000"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-flatnet}"

for file in "$BACKUP_DIR"/*.json; do
    if [ -f "$file" ]; then
        echo "Importing: $file"

        # ダッシュボード JSON を抽出して再インポート用に加工
        dashboard=$(jq '.dashboard | .id = null' "$file")

        # インポート
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -u "$GRAFANA_USER:$GRAFANA_PASS" \
            -d "{\"dashboard\": $dashboard, \"overwrite\": true}" \
            "$GRAFANA_URL/api/dashboards/db"

        echo ""
    fi
done

echo "Import completed"
```

### 3. Prometheus データのリストア

Prometheus データのリストアは、通常スナップショットからの復元となります。

```bash
# 1. Prometheus 停止
cd ~/prj/flatnet/monitoring
podman-compose stop prometheus

# 2. 既存データの退避（オプション）
# Podman volume のデータは直接操作が必要

# 3. スナップショットからのリストア
# 注: 実際のパスは環境に依存
# スナップショットを prometheus_data ボリュームにコピー

# 4. Prometheus 再起動
podman-compose start prometheus
```

### 4. 完全リストアスクリプト

完全なリストアは `scripts/restore.sh` を使用します。

```bash
# 利用可能なバックアップの一覧
~/prj/flatnet/scripts/restore.sh --list

# 特定の日付からリストア
~/prj/flatnet/scripts/restore.sh --date 20240101
```

---

## 自動バックアップ設定

### cron による自動バックアップ（WSL2）

```bash
# crontab 編集
crontab -e

# 毎日 3:00 にバックアップ実行
0 3 * * * /home/kh/prj/flatnet/scripts/backup.sh >> /var/log/flatnet/backup.log 2>&1

# 毎週日曜 4:00 に古いバックアップを削除
0 4 * * 0 find /backup/flatnet -type d -mtime +7 -exec rm -rf {} + 2>/dev/null
```

### systemd タイマーによる自動バックアップ（WSL2/代替）

`/etc/systemd/system/flatnet-backup.timer`:

```ini
[Unit]
Description=Flatnet Daily Backup Timer

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

`/etc/systemd/system/flatnet-backup.service`:

```ini
[Unit]
Description=Flatnet Backup Service

[Service]
Type=oneshot
ExecStart=/home/kh/prj/flatnet/scripts/backup.sh
User=kh
```

```bash
# 有効化
sudo systemctl enable flatnet-backup.timer
sudo systemctl start flatnet-backup.timer
```

### タスクスケジューラによる自動バックアップ（Windows）

```powershell
# バックアップタスクの登録
$action = New-ScheduledTaskAction `
    -Execute "PowerShell.exe" `
    -Argument "-ExecutionPolicy Bypass -File F:\flatnet\scripts\backup-windows.ps1"

$trigger = New-ScheduledTaskTrigger -Daily -At 3:00AM

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -WakeToRun

Register-ScheduledTask `
    -TaskName "Flatnet-Backup" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -RunLevel Highest
```

---

## リストアテスト

### テスト手順

定期的（月次推奨）にリストアテストを実施して、バックアップが正常に機能することを確認します。

#### 1. テスト環境の準備

```bash
# テスト用ディレクトリ作成
mkdir -p /tmp/flatnet-restore-test

# 本番環境のサービスには影響を与えないよう注意
```

#### 2. 設定ファイルのリストアテスト

```bash
#!/bin/bash
# リストアテスト（設定ファイル）

BACKUP_DIR="/backup/flatnet/$(ls -t /backup/flatnet | head -1)"
TEST_DIR="/tmp/flatnet-restore-test"

echo "Testing restore from: $BACKUP_DIR"

# CNI 設定
cp -r "$BACKUP_DIR/cni-config" "$TEST_DIR/"
diff -r "$BACKUP_DIR/cni-config" "$TEST_DIR/cni-config"
if [ $? -eq 0 ]; then
    echo "[PASS] CNI config restore"
else
    echo "[FAIL] CNI config restore"
fi

# クリーンアップ
rm -rf "$TEST_DIR/*"
```

#### 3. Grafana ダッシュボードのテスト

```bash
#!/bin/bash
# Grafana ダッシュボードリストアテスト

BACKUP_DIR="/backup/flatnet/$(ls -t /backup/flatnet | head -1)/grafana-dashboards"

# ダッシュボード JSON の整合性確認
for file in "$BACKUP_DIR"/*.json; do
    if jq empty "$file" 2>/dev/null; then
        echo "[PASS] Valid JSON: $(basename "$file")"
    else
        echo "[FAIL] Invalid JSON: $(basename "$file")"
    fi
done
```

#### 4. テスト結果の記録

```markdown
## リストアテスト結果

**テスト日:** YYYY-MM-DD
**テスト者:**
**バックアップ日:** YYYY-MM-DD

### 結果

| 項目 | 結果 | 備考 |
|------|------|------|
| 設定ファイル | PASS/FAIL | |
| Grafana ダッシュボード | PASS/FAIL | |
| Prometheus データ | PASS/FAIL | |

### 問題点

（発見された問題があれば記載）

### 改善事項

（必要な改善があれば記載）
```

---

## ベストプラクティス

### 1. 3-2-1 ルール

- **3**: 少なくとも 3 つのデータコピー
- **2**: 2 つの異なるメディア/場所に保存
- **1**: 1 つはオフサイト（別の場所）に保存

### 2. バックアップの暗号化

重要なデータ（証明書、設定）は暗号化して保存:

```bash
# 暗号化してバックアップ
tar czf - /backup/flatnet/20240101 | \
    gpg --symmetric --cipher-algo AES256 -o /external/flatnet-backup-20240101.tar.gz.gpg

# 復号
gpg -d /external/flatnet-backup-20240101.tar.gz.gpg | tar xzf -
```

### 3. バックアップの検証

- 毎回バックアップ後にチェックサムを生成
- 定期的にリストアテストを実施

```bash
# チェックサム生成
sha256sum /backup/flatnet/20240101/* > /backup/flatnet/20240101/checksums.txt

# チェックサム検証
sha256sum -c /backup/flatnet/20240101/checksums.txt
```

### 4. ドキュメント化

- バックアップ手順を最新に保つ
- 復旧時間目標（RTO）を定義
- 復旧ポイント目標（RPO）を定義

### 5. アラート設定

バックアップ失敗時にアラートを発報:

```bash
# backup.sh の最後に追加（main 関数の最後の exit 0 の前に挿入）
backup_result=$?
if [ $backup_result -ne 0 ]; then
    # アラート送信（Alertmanager または他の通知システム）
    curl -X POST http://localhost:9093/api/v2/alerts \
        -H "Content-Type: application/json" \
        -d '[{"labels":{"alertname":"BackupFailed","severity":"warning"}}]'
    exit $backup_result
fi
```

---

## トラブルシューティング

### バックアップ失敗

#### 症状: Grafana ダッシュボードのエクスポートが失敗

**原因と対処:**

1. **認証エラー**
   ```bash
   # 認証情報を確認
   curl -u admin:flatnet http://localhost:3000/api/org

   # API キーを使用する場合
   export GRAFANA_API_KEY="your-api-key"
   ./backup.sh
   ```

2. **Grafana が起動していない**
   ```bash
   # Grafana の状態確認
   curl http://localhost:3000/api/health

   # 起動していない場合
   cd ~/prj/flatnet/monitoring && podman-compose up -d grafana
   ```

#### 症状: Prometheus スナップショット作成が失敗

**原因と対処:**

1. **Admin API が無効**
   - Prometheus の起動オプションに `--web.enable-admin-api` を追加

2. **ディスク容量不足**
   ```bash
   df -h
   podman system prune -a -f
   ```

#### 症状: チェックサム検証が失敗

**原因と対処:**

1. **ファイル破損**: バックアップを再取得
2. **転送中のエラー**: 再度バックアップを実行

### リストア失敗

#### 症状: リストア中にエラーが発生

**対処手順:**

1. **pre-restore バックアップから復元**
   ```bash
   # 自動作成された pre-restore バックアップを確認
   ls -la /backup/flatnet/pre-restore_*

   # pre-restore バックアップから復元
   ./restore.sh --date pre-restore_YYYYMMDD_HHMMSS
   ```

2. **サービスの状態確認**
   ```bash
   cd ~/prj/flatnet/monitoring
   podman-compose ps
   podman-compose logs --tail 50
   ```

#### 症状: Grafana ダッシュボードのインポートが失敗

**原因と対処:**

1. **認証エラー**
   ```bash
   # 認証確認
   curl -u admin:flatnet http://localhost:3000/api/org

   # API キーを使用
   export GRAFANA_API_KEY="your-api-key"
   ./restore.sh --latest --grafana
   ```

2. **ダッシュボード JSON の破損**
   ```bash
   # JSON の検証
   jq empty /backup/flatnet/YYYYMMDD/grafana-dashboards/*.json
   ```

#### 症状: パーミッションエラー

**対処:**

```bash
# CNI 設定は sudo が必要
sudo ./restore.sh --latest --cni

# または個別に権限を付与
sudo chown -R $(whoami) /etc/cni/net.d
```

### リストア後の問題

#### 症状: サービスが起動しない

**対処手順:**

1. **設定ファイルの検証**
   ```bash
   # Prometheus 設定確認
   podman exec flatnet-prometheus promtool check config /etc/prometheus/prometheus.yml

   # Alertmanager 設定確認
   podman exec flatnet-alertmanager amtool check-config /etc/alertmanager/alertmanager.yml
   ```

2. **コンテナログの確認**
   ```bash
   podman-compose logs prometheus
   podman-compose logs grafana
   ```

3. **pre-restore バックアップに戻す**
   ```bash
   ./restore.sh --date pre-restore_YYYYMMDD_HHMMSS
   ```

---

## 関連ドキュメント

- [Daily Operations](daily-operations.md) - 日常運用ガイド
- [Runbook](runbook.md) - 障害対応手順
- [Maintenance](maintenance.md) - メンテナンス手順
- [scripts/backup.sh](../../scripts/backup.sh) - バックアップスクリプト
- [scripts/restore.sh](../../scripts/restore.sh) - リストアスクリプト
