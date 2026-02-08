# Flatnet インシデント対応ランブック

このドキュメントでは、Flatnet システムで発生しうる障害パターンとその対応手順を説明します。

## 目次

1. [障害対応の基本フロー](#障害対応の基本フロー)
2. [障害パターン一覧](#障害パターン一覧)
3. [エスカレーション基準](#エスカレーション基準)
4. [連絡先一覧](#連絡先一覧)

---

## 障害対応の基本フロー

1. **検知**: アラート通知またはユーザー報告
2. **初期調査**: 症状の確認と影響範囲の把握
3. **対応**: 本ランブックに従った対処
4. **復旧確認**: サービス正常性の確認
5. **記録**: インシデントレポートの作成

---

## 障害パターン一覧

### 障害 1: Gateway が応答しない

#### 症状

- ブラウザからアクセスできない
- `http://<Windows IP>/` がタイムアウト
- curl でコネクションが確立できない

#### 影響

- 全ての外部アクセスが不可
- 重大度: **高**

#### 確認手順

**Windows PowerShell:**

```powershell
# 1. nginx プロセスが起動しているか確認
Get-Process nginx -ErrorAction SilentlyContinue

# 2. ポート 80/8080 がリッスンしているか確認
netstat -an | findstr ":80 "
netstat -an | findstr ":8080 "

# 3. エラーログを確認
Get-Content F:\flatnet\openresty\logs\error.log -Tail 50

# 4. Windows Firewall の状態確認
Get-NetFirewallRule -DisplayName "*nginx*" -ErrorAction SilentlyContinue
Get-NetFirewallRule -DisplayName "*OpenResty*" -ErrorAction SilentlyContinue
```

#### 対処手順

**プロセスが起動していない場合:**

```powershell
# 設定テスト
cd F:\flatnet\openresty
.\nginx.exe -t

# 問題なければ起動
.\nginx.exe

# サービスの場合
Start-Service OpenResty
```

**ポートがリッスンしていない場合:**

```powershell
# 他のプロセスがポートを使用していないか確認
netstat -an | findstr ":80.*LISTENING"

# ポート競合がある場合、該当プロセスを停止
# または nginx.conf でポートを変更
```

**エラーログに問題がある場合:**

- 設定ファイルエラー: `nginx.exe -t` で詳細確認後、設定修正
- パーミッションエラー: 管理者権限で実行
- SSL 証明書エラー: 証明書パスと有効期限を確認

#### 復旧確認

```powershell
# プロセス確認
Get-Process nginx

# HTTP アクセス確認
curl http://localhost/

# API ヘルスチェック
curl http://localhost:8080/api/health
```

---

### 障害 2: WSL2 内サービスに到達できない (502 Bad Gateway)

#### 症状

- Gateway は動作しているが、502 Bad Gateway が返る
- 特定のサービスのみアクセス不可

#### 影響

- 該当サービスへのアクセス不可
- 重大度: **中〜高**

#### 確認手順

**Windows PowerShell:**

```powershell
# 1. WSL2 が起動しているか確認
wsl --status

# 2. WSL2 の IP アドレスを取得
$wslIp = (wsl hostname -I).Trim().Split(" ")[0]
Write-Host "WSL2 IP: $wslIp"

# 3. WSL2 への疎通確認
ping $wslIp
```

**WSL2:**

```bash
# 4. 対象サービスのコンテナ確認
podman ps -a | grep <service-name>

# 5. コンテナのログ確認
podman logs <container-name> --tail 50

# 6. コンテナの IP 確認
podman inspect <container-name> | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress'

# 7. コンテナへの疎通確認
curl http://<container-ip>:<port>/
```

#### 対処手順

**WSL2 が停止している場合:**

```powershell
# WSL2 起動
wsl

# または特定のディストリビューション
wsl -d Ubuntu-24.04
```

**コンテナが停止している場合:**

```bash
# コンテナ起動
podman start <container-name>

# コンテナのログで起動エラー確認
podman logs <container-name>
```

**IP アドレスが変更されている場合:**

```powershell
# 新しい WSL2 IP を取得
$wslIp = (wsl hostname -I).Trim().Split(" ")[0]

# nginx.conf の proxy_pass を更新（手動または自動スクリプト）
# その後リロード
cd F:\flatnet\openresty
.\nginx.exe -s reload
```

**コンテナ内のサービスが応答しない場合:**

```bash
# コンテナ内で確認
podman exec -it <container-name> /bin/sh

# プロセス確認
ps aux

# ログ確認
cat /var/log/<service>.log
```

#### 復旧確認

```bash
# コンテナ状態
podman ps | grep <container-name>

# サービスへのアクセス
curl http://<container-ip>:<port>/

# Gateway 経由でのアクセス
curl http://<windows-ip>/<service-path>/
```

---

### 障害 3: コンテナが起動しない

#### 症状

- `podman run` がエラーになる
- コンテナが Exited 状態になる
- CrashLoopBackOff 的な動作

#### 影響

- 該当サービスが利用不可
- 重大度: **中**

#### 確認手順

```bash
# 1. コンテナの状態を確認
podman ps -a --filter "name=<container-name>"

# 2. コンテナのログを確認
podman logs <container-name>

# 3. コンテナの詳細情報
podman inspect <container-name>

# 4. リソース使用状況を確認
df -h
free -h
podman system df
```

#### 対処手順

**ディスク容量不足の場合:**

```bash
# 不要なイメージ削除
podman image prune -a -f

# 不要なコンテナ削除
podman container prune -f

# 不要なボリューム削除
podman volume prune -f
```

**メモリ不足の場合:**

```bash
# 不要なコンテナを停止
podman stop <unused-container>

# メモリ使用量確認
podman stats --no-stream
```

**設定エラーの場合:**

```bash
# コンテナを削除して再作成
podman rm <container-name>

# 設定を確認して再起動
podman run -d --name <container-name> --network flatnet <image>
```

**イメージの問題の場合:**

```bash
# イメージを再取得
podman pull <image>

# コンテナ再作成
podman rm <container-name>
podman run -d --name <container-name> --network flatnet <image>
```

#### 復旧確認

```bash
# コンテナ状態
podman ps | grep <container-name>

# コンテナ内のプロセス
podman top <container-name>

# サービスへのアクセス
podman exec <container-name> curl localhost:<port>
```

---

### 障害 4: 監視システムが動作しない

#### 症状

- Grafana にアクセスできない
- アラートが発報されない
- メトリクスが収集されない

#### 影響

- 監視機能の喪失
- 重大度: **中**

#### 確認手順

```bash
# 1. 監視コンテナの状態を確認
cd ~/prj/flatnet/monitoring
podman-compose ps

# 2. 各コンテナのログ確認
podman-compose logs prometheus --tail 50
podman-compose logs grafana --tail 50
podman-compose logs alertmanager --tail 50

# 3. Prometheus ターゲットの状態確認
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# 4. ディスク使用量確認
df -h
podman system df
```

#### 対処手順

**コンテナが停止している場合:**

```bash
cd ~/prj/flatnet/monitoring

# 全サービス再起動
podman-compose down
podman-compose up -d

# 特定サービスのみ再起動
podman-compose restart prometheus
```

**設定エラーの場合:**

```bash
# Prometheus 設定確認
podman exec flatnet-prometheus promtool check config /etc/prometheus/prometheus.yml

# Alertmanager 設定確認
podman exec flatnet-alertmanager amtool check-config /etc/alertmanager/alertmanager.yml
```

**ディスク容量不足の場合:**

```bash
# 古いデータ削除（Prometheus）
# retention.time の調整を検討

# ボリューム確認
podman volume ls
podman volume inspect prometheus_data
```

#### 復旧確認

```bash
# サービス状態
podman-compose ps

# ヘルスチェック
curl -s http://localhost:9090/-/ready    # Prometheus
curl -s http://localhost:3000/api/health  # Grafana
curl -s http://localhost:9093/-/ready    # Alertmanager
curl -s http://localhost:3100/ready      # Loki
```

---

### 障害 5: WSL2 の IP アドレスが変更された

#### 症状

- Gateway は動作しているが、502 Bad Gateway が返る
- WSL2 再起動後に発生
- Windows ホストからの接続がタイムアウト

#### 影響

- 全ての WSL2 内サービスへのアクセス不可
- 重大度: **高**

#### 確認手順

```powershell
# 1. WSL2 の現在の IP を取得
$wslIp = (wsl hostname -I).Trim().Split(" ")[0]
Write-Host "Current WSL2 IP: $wslIp"

# 2. nginx.conf の設定を確認
Get-Content F:\flatnet\openresty\conf\nginx.conf | Select-String "proxy_pass"

# 3. Windows ルートテーブル確認
route print | Select-String "10.87"
```

#### 対処手順

**手動での対処:**

```powershell
# 1. WSL2 の IP を取得
$wslIp = (wsl hostname -I).Trim().Split(" ")[0]
Write-Host "WSL2 IP: $wslIp"

# 2. nginx.conf の proxy_pass を更新（テキストエディタで編集）
# 例: proxy_pass http://172.x.x.x:8080 → proxy_pass http://$wslIp:8080

# 3. Windows ルートを更新
route delete 10.87.0.0
route add 10.87.0.0 mask 255.255.0.0 $wslIp

# 4. 設定リロード
cd F:\flatnet\openresty
.\nginx.exe -s reload
```

**自動スクリプトでの対処:**

```powershell
# IP 更新スクリプトの実行
F:\flatnet\scripts\update-wsl2-ip.ps1
```

#### 恒久対策

1. Windows 起動時に IP 更新スクリプトを自動実行するタスクを設定
2. または Lua による動的解決を実装（Phase 1 参照）

```powershell
# タスクスケジューラへの登録
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File F:\flatnet\scripts\update-wsl2-ip.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "Flatnet-UpdateWSL2IP" -Action $action -Trigger $trigger -RunLevel Highest
```

#### 復旧確認

```powershell
# Gateway 経由でアクセス
curl http://localhost/api/health

# ルーティング確認
route print | Select-String "10.87"
```

---

### 障害 6: ディスク容量不足

#### 症状

- コンテナが起動できない
- ログ書き込みエラー
- Prometheus/Loki がデータを保存できない

#### 影響

- サービス全体に影響の可能性
- 重大度: **高**

#### 確認手順

**WSL2:**

```bash
# ディスク使用量確認
df -h

# 大きなディレクトリを特定
du -sh /* 2>/dev/null | sort -rh | head -20

# Podman ストレージ
podman system df
```

**Windows PowerShell:**

```powershell
# F: ドライブ確認
Get-PSDrive F

# ログディレクトリサイズ
Get-ChildItem F:\flatnet\logs -Recurse | Measure-Object -Property Length -Sum
```

#### 対処手順

**不要なコンテナリソースの削除:**

```bash
# 停止中のコンテナ削除
podman container prune -f

# 未使用イメージ削除
podman image prune -a -f

# 未使用ボリューム削除
podman volume prune -f

# 総合クリーンアップ
podman system prune -a -f --volumes
```

**ログファイルの削除:**

```bash
# 古いログ削除（7日以上前）
find /var/log/flatnet -type f -mtime +7 -delete

# ログローテーション実行
logrotate -f /etc/logrotate.d/flatnet
```

**Windows ログの削除:**

```powershell
# 古いログファイルのアーカイブ/削除
Get-ChildItem F:\flatnet\logs\*.log |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
    Remove-Item -Force
```

**Prometheus データの削除:**

```bash
# Prometheus コンテナ停止
cd ~/prj/flatnet/monitoring
podman-compose stop prometheus

# 古いデータ削除（または retention 調整）
# ボリュームを削除して再作成する場合
podman volume rm monitoring_prometheus_data
podman-compose up -d prometheus
```

#### 復旧確認

```bash
# ディスク使用量確認
df -h

# サービス状態確認
podman ps
```

---

### 障害 7: Nebula トンネルが確立できない

#### 症状

- 他ホストへの ping がタイムアウト
- Nebula ログに handshake エラー

#### 影響

- マルチホスト間通信の不可
- 重大度: **高**（マルチホスト環境）

#### 確認手順

**Windows PowerShell:**

```powershell
# 1. Nebula サービス状態
Get-Service Nebula

# 2. Nebula ログ確認
Get-Content F:\flatnet\logs\nebula.log -Tail 100

# 3. ファイアウォール確認
Get-NetFirewallRule -DisplayName "*Nebula*"

# 4. ポート確認
netstat -an | findstr ":4242"

# 5. Lighthouse への疎通確認
ping <lighthouse-lan-ip>
```

#### 対処手順

**サービスが停止している場合:**

```powershell
Start-Service Nebula
```

**証明書エラーの場合:**

```powershell
# 証明書の確認
cd F:\flatnet\nebula
.\nebula-cert.exe print -path F:\flatnet\config\nebula\host.crt

# 期限切れの場合、新しい証明書を Lighthouse から取得
```

**ファイアウォールの問題:**

```powershell
# ルール追加
New-NetFirewallRule -DisplayName "Nebula UDP" `
    -Direction Inbound `
    -Protocol UDP `
    -LocalPort 4242 `
    -Action Allow
```

**設定エラーの場合:**

```powershell
# 設定確認
Get-Content F:\flatnet\config\nebula\config.yaml

# Lighthouse の IP が正しいか確認
# static_host_map と lighthouse.hosts を確認
```

#### 復旧確認

```powershell
# サービス状態
Get-Service Nebula

# Lighthouse への ping
ping 10.100.0.1

# ログで handshake 成功確認
Get-Content F:\flatnet\logs\nebula.log | Select-String "handshake"
```

---

### 障害 8: バックアップ/リストアスクリプトが失敗

#### 症状

- バックアップスクリプトがエラーで終了
- cron ジョブからのバックアップが実行されない
- リストアが途中で失敗

#### 影響

- データ保護の欠如
- 重大度: **中**（即座のサービス影響はないが、DR 能力に影響）

#### 確認手順

```bash
# 1. スクリプトの手動実行
~/prj/flatnet/scripts/backup.sh --dry-run

# 2. cron ログの確認
grep backup /var/log/syslog | tail -20

# 3. バックアップディレクトリの確認
ls -la /backup/flatnet/
df -h /backup
```

#### 対処手順

**ディスク容量不足:**

```bash
# 古いバックアップを手動削除
ls -lt /backup/flatnet/ | tail -5
rm -rf /backup/flatnet/古いバックアップ

# または retention を短く
./backup.sh --retention 3
```

**Grafana 認証エラー:**

```bash
# 認証情報を確認
curl -u admin:flatnet http://localhost:3000/api/org

# API キーを使用
export GRAFANA_API_KEY="your-api-key"
./backup.sh
```

**権限エラー:**

```bash
# バックアップディレクトリの権限確認
ls -la /backup/flatnet
sudo chown -R $(whoami) /backup/flatnet
```

#### 復旧確認

```bash
# バックアップの実行
./backup.sh

# バックアップの確認
ls -la /backup/flatnet/$(date +%Y%m%d)*
```

---

### 障害 9: Grafana 認証失敗

#### 症状

- Grafana にログインできない
- API アクセスが認証エラー
- バックアップスクリプトで Grafana エクスポートが失敗

#### 影響

- ダッシュボードアクセス不可
- 重大度: **中**

#### 確認手順

```bash
# 1. Grafana の状態確認
curl http://localhost:3000/api/health

# 2. 認証テスト
curl -u admin:flatnet http://localhost:3000/api/org

# 3. ログ確認
podman logs flatnet-grafana --tail 50
```

#### 対処手順

**パスワードを忘れた場合:**

```bash
# Grafana CLI でパスワードリセット
podman exec -it flatnet-grafana grafana-cli admin reset-admin-password newpassword

# または環境変数で初期パスワード設定
# podman-compose.yml に GF_SECURITY_ADMIN_PASSWORD を設定
```

**データベース破損の場合:**

```bash
# Grafana を停止
cd ~/prj/flatnet/monitoring
podman-compose stop grafana

# データベースをバックアップから復元（またはリセット）
# ボリュームを削除して再初期化
podman volume rm monitoring_grafana_data
podman-compose up -d grafana
```

#### 復旧確認

```bash
# ログイン確認
curl -u admin:newpassword http://localhost:3000/api/org
```

---

## エスカレーション基準

| 状況 | エスカレーション先 | 時間目安 |
|------|-------------------|----------|
| 上記手順で復旧しない | 開発チーム | 30分 |
| 同一障害の再発 | 開発チーム | 即時 |
| データ損失の可能性 | 開発チーム + マネージャー | 即時 |
| セキュリティインシデント | セキュリティ担当 | 即時 |
| 複数サービス同時障害 | 開発チーム | 即時 |

---

## 連絡先一覧

> **重要**: 以下の連絡先は本番運用開始前に必ず更新してください。

| 役割 | 担当者 | 連絡先 | 備考 |
|------|--------|--------|------|
| 開発チーム | TBD（要更新） | TBD（要更新） | 技術的問題のエスカレーション先 |
| インフラ担当 | TBD（要更新） | TBD（要更新） | ネットワーク・サーバー問題 |
| セキュリティ担当 | TBD（要更新） | TBD（要更新） | セキュリティインシデント |
| マネージャー | TBD（要更新） | TBD（要更新） | 重大障害時の報告先 |

**連絡先更新手順:**
1. 各担当者の名前と連絡先（メール、電話、Slack等）を確認
2. このセクションを更新
3. 関係者に周知

---

## インシデントレポートテンプレート

```markdown
## インシデントレポート

**日時:** YYYY-MM-DD HH:MM
**報告者:**
**重大度:** 高/中/低

### 概要
（障害の概要を 1-2 文で）

### 影響
- 影響を受けたサービス:
- 影響を受けたユーザー数:
- ダウンタイム:

### タイムライン
- HH:MM - 検知
- HH:MM - 対応開始
- HH:MM - 復旧

### 根本原因
（原因の詳細）

### 対応内容
（実施した対応）

### 再発防止策
（今後の対策）
```

---

## 関連ドキュメント

- [Daily Operations](daily-operations.md) - 日常運用ガイド
- [Troubleshooting](troubleshooting.md) - トラブルシューティング詳細
- [Backup/Restore](backup-restore.md) - バックアップ・リストア手順
- [Maintenance](maintenance.md) - メンテナンス手順
