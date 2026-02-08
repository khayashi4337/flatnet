# Flatnet メンテナンス手順

このドキュメントでは、Flatnet システムの計画メンテナンス、アップデート、ロールバック手順を説明します。

## 目次

1. [計画メンテナンスワークフロー](#計画メンテナンスワークフロー)
2. [Gateway アップデート手順](#gateway-アップデート手順)
3. [CNI Plugin アップデート手順](#cni-plugin-アップデート手順)
4. [監視スタックアップデート](#監視スタックアップデート)
5. [Nebula アップデート](#nebula-アップデート)
6. [ロールバック手順](#ロールバック手順)
7. [メンテナンスチェックリスト](#メンテナンスチェックリスト)

---

## 計画メンテナンスワークフロー

### 概要フロー

```
1. 計画 → 2. 告知 → 3. 準備 → 4. 実施 → 5. 確認 → 6. 完了
```

### 詳細手順

#### 1. メンテナンス計画

- **日時の決定**: 影響が最小の時間帯を選択
- **影響範囲の確認**: 停止するサービスと影響を受けるユーザーを特定
- **所要時間の見積もり**: 作業時間 + バッファ
- **ロールバック計画**: 問題発生時の戻し手順を確認

#### 2. メンテナンス告知

告知テンプレート:

```
件名: 【メンテナンス予告】Flatnet システムメンテナンス

関係者各位

下記の日程でシステムメンテナンスを実施いたします。

■ 日時
  YYYY年MM月DD日 HH:MM 〜 HH:MM（予定）

■ 影響
  ・影響を受けるサービス: [サービス名]
  ・予想ダウンタイム: 約 XX 分

■ 作業内容
  ・[作業内容の概要]

■ 連絡先
  ・作業責任者: [担当者名]
  ・連絡先: [連絡先]

ご不便をおかけしますが、ご理解のほどよろしくお願いいたします。
```

#### 3. 事前準備

```bash
# 1. バックアップの取得
~/prj/flatnet/scripts/backup.sh

# 2. バックアップの確認
ls -la /backup/flatnet/$(date +%Y%m%d)*

# 3. ロールバック手順の確認
cat ~/prj/flatnet/docs/operations/maintenance.md

# 4. 必要なファイルの準備
# - 新しいバイナリ/設定ファイル
# - ロールバック用の古いバイナリ
```

#### 4. メンテナンス実施

```bash
# 監視アラートの一時停止
curl -X POST http://localhost:9093/api/v2/silences \
    -H "Content-Type: application/json" \
    -d '{
        "matchers": [{"name": "severity", "value": ".*", "isRegex": true}],
        "startsAt": "'$(date -Iseconds)'",
        "endsAt": "'$(date -d "+2 hours" -Iseconds)'",
        "createdBy": "maintenance",
        "comment": "Planned maintenance"
    }'

# 作業実施
# ... (各コンポーネントのアップデート手順を実行)

# 動作確認
curl http://localhost:8080/api/health
```

#### 5. 復旧確認

```bash
# サービス状態確認
podman ps
Get-Service Nebula  # Windows (Nebula)
Get-Service OpenResty  # Windows (OpenResty)

# ヘルスチェック
curl http://localhost:8080/api/health
curl http://localhost:9090/-/ready
curl http://localhost:3000/api/health

# ログ確認（エラーがないか）
podman-compose logs --tail 50
```

#### 6. メンテナンス完了

```bash
# 監視アラートの再開（サイレンスの削除）
# Alertmanager UI または API で実施

# 完了通知を送信
```

完了通知テンプレート:

```
件名: 【完了】Flatnet システムメンテナンス

関係者各位

予定しておりましたシステムメンテナンスが完了しましたのでお知らせいたします。

■ 完了日時
  YYYY年MM月DD日 HH:MM

■ 実施内容
  ・[実施した内容]

■ 確認結果
  ・全サービス正常稼働を確認

ご協力ありがとうございました。
```

---

## Gateway アップデート手順

### 事前準備

```powershell
# 1. 現在のバージョン確認
cd F:\flatnet\openresty
.\nginx.exe -v

# 2. 設定のバックアップ
$backupDir = "F:\flatnet\backups\gateway-$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $backupDir -Force
Copy-Item -Recurse F:\flatnet\openresty\conf $backupDir\conf
Copy-Item -Recurse F:\flatnet\openresty\lualib $backupDir\lualib

# 3. 新しい OpenResty のダウンロード
# https://openresty.org/en/download.html から取得
```

### アップデート実行

```powershell
# 1. 新しい OpenResty を展開
# F:\flatnet\openresty-new\ に展開

# 2. 設定ファイルをコピー
Copy-Item -Recurse F:\flatnet\openresty\conf\* F:\flatnet\openresty-new\conf\
Copy-Item -Recurse F:\flatnet\openresty\lualib\* F:\flatnet\openresty-new\lualib\ -ErrorAction SilentlyContinue

# 3. 設定テスト
cd F:\flatnet\openresty-new
.\nginx.exe -t

# 4. 旧 Gateway 停止
cd F:\flatnet\openresty
.\nginx.exe -s stop

# 5. ディレクトリ入れ替え
Rename-Item F:\flatnet\openresty F:\flatnet\openresty-old
Rename-Item F:\flatnet\openresty-new F:\flatnet\openresty

# 6. 新 Gateway 起動
cd F:\flatnet\openresty
.\nginx.exe

# 7. 動作確認
curl http://localhost/
curl http://localhost:8080/api/health
```

### 問題発生時のロールバック

```powershell
# 1. 新 Gateway 停止
cd F:\flatnet\openresty
.\nginx.exe -s stop

# 2. ディレクトリを戻す
Rename-Item F:\flatnet\openresty F:\flatnet\openresty-failed
Rename-Item F:\flatnet\openresty-old F:\flatnet\openresty

# 3. 旧 Gateway 起動
cd F:\flatnet\openresty
.\nginx.exe

# 4. 動作確認
curl http://localhost/
```

---

## CNI Plugin アップデート手順

### 事前準備

```bash
# 1. 現在のバージョン確認
/opt/cni/bin/flatnet --version 2>/dev/null || echo "Version not available"

# 2. バックアップ
sudo cp /opt/cni/bin/flatnet /opt/cni/bin/flatnet.bak.$(date +%Y%m%d)
sudo cp /etc/cni/net.d/10-flatnet.conflist /etc/cni/net.d/10-flatnet.conflist.bak

# 3. 実行中のコンテナを確認
podman ps --filter "network=flatnet"
```

### アップデート実行

```bash
# 1. 新しいバイナリをビルド（またはダウンロード）
cd ~/prj/flatnet/src/flatnet-cni
git pull
cargo build --release

# 2. 新しいバイナリを配置
sudo cp target/release/flatnet /opt/cni/bin/flatnet
sudo chmod +x /opt/cni/bin/flatnet

# 3. 設定ファイルの更新（必要な場合）
# /etc/cni/net.d/10-flatnet.conflist を編集

# 4. 新しいコンテナで動作確認
podman run --rm --network flatnet alpine ping -c 3 10.87.1.1

# 5. 既存コンテナの再起動（必要な場合）
# 注: 既存コンテナは再起動まで古い設定で動作
```

### 問題発生時のロールバック

```bash
# 1. バックアップから復元
sudo cp /opt/cni/bin/flatnet.bak.$(date +%Y%m%d) /opt/cni/bin/flatnet

# 2. 設定も復元（変更した場合）
sudo cp /etc/cni/net.d/10-flatnet.conflist.bak /etc/cni/net.d/10-flatnet.conflist

# 3. 動作確認
podman run --rm --network flatnet alpine ping -c 3 10.87.1.1
```

---

## 監視スタックアップデート

### イメージの更新

```bash
cd ~/prj/flatnet/monitoring

# 1. 現在のイメージを確認
podman images | grep -E "prometheus|grafana|alertmanager|loki"

# 2. podman-compose.yml のバージョンを更新
# 例: image: docker.io/prom/prometheus:v2.48.1 → v2.49.0

# 3. 新しいイメージを取得
podman-compose pull

# 4. サービスの再起動
podman-compose down
podman-compose up -d

# 5. 動作確認
podman-compose ps
curl http://localhost:9090/-/ready
curl http://localhost:3000/api/health
```

### 設定の更新

```bash
cd ~/prj/flatnet/monitoring

# 1. 設定ファイルのバックアップ
cp -r prometheus prometheus.bak
cp -r alertmanager alertmanager.bak

# 2. 設定を更新
vim prometheus/prometheus.yml

# 3. 設定の検証
podman exec flatnet-prometheus promtool check config /etc/prometheus/prometheus.yml

# 4. 設定のリロード（再起動なし）
curl -X POST http://localhost:9090/-/reload

# 5. 確認
curl http://localhost:9090/api/v1/status/config | jq '.data.yaml' | head -20
```

### Grafana ダッシュボード更新

```bash
# 1. 現在のダッシュボードをバックアップ
~/prj/flatnet/scripts/backup.sh

# 2. 新しいダッシュボードをインポート
# Grafana UI から JSON をインポート
# または API 経由:
curl -X POST -H "Content-Type: application/json" \
    -u admin:flatnet \
    -d @new-dashboard.json \
    http://localhost:3000/api/dashboards/db
```

### 問題発生時のロールバック

```bash
cd ~/prj/flatnet/monitoring

# 1. 設定を復元
rm -rf prometheus
mv prometheus.bak prometheus

# 2. イメージを古いバージョンに戻す
# podman-compose.yml のバージョンを戻す

# 3. サービス再起動
podman-compose down
podman-compose up -d
```

---

## Nebula アップデート

### 事前準備

```powershell
# 1. 現在のバージョン確認
F:\flatnet\nebula\nebula.exe -version

# 2. バックアップ
$backupDir = "F:\flatnet\backups\nebula-$(Get-Date -Format 'yyyyMMdd')"
New-Item -ItemType Directory -Path $backupDir -Force
Copy-Item F:\flatnet\nebula\* $backupDir\
Copy-Item F:\flatnet\config\nebula\* $backupDir\

# 3. 新しい Nebula をダウンロード
# https://github.com/slackhq/nebula/releases
```

### アップデート実行

```powershell
# 1. サービス停止
Stop-Service Nebula

# 2. 新しいバイナリを配置
Copy-Item nebula.exe F:\flatnet\nebula\nebula.exe
Copy-Item nebula-cert.exe F:\flatnet\nebula\nebula-cert.exe

# 3. サービス起動
Start-Service Nebula

# 4. 動作確認
Get-Service Nebula
ping 10.100.0.1  # Lighthouse

# 5. ログ確認
Get-Content F:\flatnet\logs\nebula.log -Tail 50
```

### 問題発生時のロールバック

```powershell
# 1. サービス停止
Stop-Service Nebula

# 2. バックアップから復元
$backupDir = "F:\flatnet\backups\nebula-$(Get-Date -Format 'yyyyMMdd')"
Copy-Item $backupDir\nebula.exe F:\flatnet\nebula\nebula.exe
Copy-Item $backupDir\nebula-cert.exe F:\flatnet\nebula\nebula-cert.exe

# 3. サービス起動
Start-Service Nebula

# 4. 確認
ping 10.100.0.1
```

---

## ロールバック手順

### 共通のロールバックフロー

1. **問題の検知**: ヘルスチェック失敗、エラーログ、ユーザー報告
2. **判断**: ロールバックが必要か、修正対応か
3. **ロールバック実行**: 各コンポーネントの手順に従う
4. **確認**: サービス復旧を確認
5. **報告**: 関係者への報告

### ロールバック判断基準

| 状況 | 判断 | 制限時間 |
|------|------|----------|
| サービスが完全に停止 | 即時ロールバック | 5分以内に判断 |
| 一部機能が動作しない | 修正を試みる | 15分以内に修正できなければロールバック |
| パフォーマンス低下のみ | 調査して判断 | 30分以内に判断 |
| ログにエラーがあるが動作 | 調査して判断 | 1時間以内に判断 |

### ロールバック後の確認

ロールバック後は必ず以下を確認してください：

1. **サービス状態の確認**
   ```bash
   # ヘルスチェック
   curl http://localhost:8080/api/health
   curl http://localhost:9090/-/ready
   curl http://localhost:3000/api/health
   ```

2. **ログでエラーがないか確認**
   ```bash
   podman-compose logs --tail 50 | grep -i error
   ```

3. **監視アラートの再開**
   ```bash
   # Alertmanager のサイレンスを解除
   ```

4. **関係者への報告**
   - ロールバック実施の報告
   - 原因調査の予定

### ロールバック失敗時の対処

ロールバックも失敗した場合：

1. **即座にエスカレーション**
   - 開発チームに連絡
   - 影響範囲を報告

2. **ログと証拠の保全**
   ```bash
   podman-compose logs > /tmp/incident-logs-$(date +%Y%m%d_%H%M%S).txt
   ```

3. **可能な応急処置**
   - サービスの一時停止
   - ユーザーへの告知

### 緊急ロールバックスクリプト

**WSL2:**

```bash
#!/bin/bash
# emergency-rollback.sh

COMPONENT=$1

case $COMPONENT in
    "cni")
        echo "Rolling back CNI Plugin..."
        sudo cp /opt/cni/bin/flatnet.bak.* /opt/cni/bin/flatnet
        echo "Done. Test with: podman run --rm --network flatnet alpine ping -c 3 10.87.1.1"
        ;;
    "monitoring")
        echo "Rolling back Monitoring Stack..."
        cd ~/prj/flatnet/monitoring
        git checkout HEAD~1 podman-compose.yml
        podman-compose down
        podman-compose up -d
        ;;
    *)
        echo "Usage: $0 [cni|monitoring]"
        exit 1
        ;;
esac
```

**Windows PowerShell:**

```powershell
# emergency-rollback.ps1
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("gateway", "nebula")]
    [string]$Component
)

switch ($Component) {
    "gateway" {
        Write-Host "Rolling back Gateway..."
        cd F:\flatnet\openresty
        .\nginx.exe -s stop
        Rename-Item F:\flatnet\openresty F:\flatnet\openresty-failed
        Rename-Item F:\flatnet\openresty-old F:\flatnet\openresty
        cd F:\flatnet\openresty
        .\nginx.exe
        Write-Host "Done. Test with: curl http://localhost/"
    }
    "nebula" {
        Write-Host "Rolling back Nebula..."
        Stop-Service Nebula
        $backupDir = Get-ChildItem F:\flatnet\backups\nebula-* | Sort-Object -Descending | Select-Object -First 1
        Copy-Item "$($backupDir.FullName)\*.exe" F:\flatnet\nebula\
        Start-Service Nebula
        Write-Host "Done. Test with: ping 10.100.0.1"
    }
}
```

---

## メンテナンスチェックリスト

### 事前チェックリスト

- [ ] メンテナンス日時が決定されている
- [ ] 影響範囲が確認されている
- [ ] 関係者への告知が完了している
- [ ] バックアップが取得されている
- [ ] ロールバック手順が確認されている
- [ ] 必要なファイル/バイナリが準備されている
- [ ] テスト環境での検証が完了している（可能な場合）

### 実施中チェックリスト

- [ ] 監視アラートを一時停止した
- [ ] 作業ログを記録している
- [ ] 各ステップで動作確認を行っている
- [ ] 問題発生時はすぐにロールバックを判断

### 事後チェックリスト

- [ ] 全サービスの動作確認が完了
- [ ] ログにエラーがないことを確認
- [ ] 監視アラートを再開した
- [ ] 完了通知を送信した
- [ ] 作業報告書を作成した
- [ ] 古いバックアップ/バイナリの整理

---

## 関連ドキュメント

- [Daily Operations](daily-operations.md) - 日常運用ガイド
- [Runbook](runbook.md) - 障害対応手順
- [Backup/Restore](backup-restore.md) - バックアップ・リストア手順
- [Troubleshooting](troubleshooting.md) - トラブルシューティング
