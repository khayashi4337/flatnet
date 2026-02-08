# Flatnet 日常運用ガイド

このドキュメントでは、Flatnet システムの日常運用に必要なタスクとその手順を説明します。

## 目次

1. [日次チェックリスト](#日次チェックリスト)
2. [週次チェックリスト](#週次チェックリスト)
3. [月次チェックリスト](#月次チェックリスト)
4. [Gateway 操作](#gateway-操作)
5. [監視スタック操作](#監視スタック操作)
6. [ログ確認手順](#ログ確認手順)
7. [ヘルスチェック手順](#ヘルスチェック手順)

---

## 日次チェックリスト

毎日（業務開始時）に実施する確認項目です。

### チェック項目

- [ ] Grafana ダッシュボードでシステム状態を確認
- [ ] アクティブなアラートがないことを確認
- [ ] エラーログに重大な問題がないことを確認
- [ ] 全サービスが正常に動作していることを確認

### 確認手順

#### 1. Grafana ダッシュボード確認

1. ブラウザで `http://localhost:3000` にアクセス
2. 「Flatnet Overview」ダッシュボードを表示
3. 以下を確認:
   - Gateway のリクエスト成功率が 99% 以上
   - エラーレートが許容範囲内
   - リソース使用率が閾値以下

#### 2. アラート確認

```bash
# Alertmanager でアクティブなアラートを確認
curl -s http://localhost:9093/api/v2/alerts | jq '.[].labels.alertname'
```

#### 3. サービス状態確認

**Windows PowerShell:**

```powershell
# Gateway プロセス確認
Get-Process nginx -ErrorAction SilentlyContinue

# Nebula サービス確認
Get-Service Nebula -ErrorAction SilentlyContinue
```

**WSL2:**

```bash
# 監視スタック確認
cd ~/prj/flatnet/monitoring
podman-compose ps

# 全コンテナ確認
podman ps --format "table {{.Names}}\t{{.Status}}"
```

---

## 週次チェックリスト

毎週（月曜日推奨）に実施する確認項目です。

### チェック項目

- [ ] ディスク使用量が閾値以下であることを確認
- [ ] バックアップが正常に完了していることを確認
- [ ] 不要なログ・データを削除
- [ ] 証明書の有効期限を確認
- [ ] コンテナイメージの更新確認

### 確認手順

#### 1. ディスク使用量確認

**WSL2:**

```bash
# ディスク使用量概要
df -h | grep -E "^/dev|Filesystem"

# Podman ストレージ使用量
podman system df

# Prometheus データサイズ
du -sh /var/lib/flatnet/prometheus 2>/dev/null || echo "N/A"
```

**Windows PowerShell:**

```powershell
# ログディレクトリサイズ
Get-ChildItem F:\flatnet\logs -Recurse |
    Measure-Object -Property Length -Sum |
    Select-Object @{N='SizeMB';E={[math]::Round($_.Sum/1MB,2)}}
```

#### 2. バックアップ確認

```bash
# 最新のバックアップを確認
ls -lt /backup/flatnet/ | head -5

# バックアップのサイズ確認
du -sh /backup/flatnet/*
```

#### 3. ログローテーション・クリーンアップ

```bash
# 古いログファイルの確認（7日以上前）
find /var/log/flatnet -type f -mtime +7 -ls

# 不要なコンテナイメージの削除
podman image prune -f
```

#### 4. 証明書有効期限確認

**Windows PowerShell:**

```powershell
cd F:\flatnet\nebula
.\nebula-cert.exe print -path F:\flatnet\config\nebula\host.crt
```

---

## 月次チェックリスト

毎月（月初推奨）に実施する確認項目です。

### チェック項目

- [ ] セキュリティアップデートの確認と適用
- [ ] コンテナイメージの更新
- [ ] 脆弱性スキャンの実施
- [ ] パフォーマンスレポートの確認
- [ ] バックアップからのリストアテスト
- [ ] ドキュメントの更新確認

### 確認手順

#### 1. セキュリティアップデート確認

**WSL2:**

```bash
# パッケージアップデート確認
sudo apt update
apt list --upgradable

# セキュリティアップデートのみ適用
sudo apt upgrade -y
```

#### 2. コンテナイメージ更新

```bash
# 使用中のイメージのダイジェスト確認
podman images --digests

# 最新イメージの取得
cd ~/prj/flatnet/monitoring
podman-compose pull

# 更新後の再起動
podman-compose up -d
```

#### 3. 脆弱性スキャン

```bash
# Trivy によるイメージスキャン（インストール済みの場合）
trivy image docker.io/grafana/grafana:10.2.3
trivy image docker.io/prom/prometheus:v2.48.1
```

---

## Gateway 操作

### 起動

**Windows PowerShell（管理者）:**

```powershell
cd F:\flatnet\openresty
.\nginx.exe
```

または、サービスとして登録している場合:

```powershell
Start-Service OpenResty
```

### 停止

**Windows PowerShell（管理者）:**

```powershell
cd F:\flatnet\openresty
.\nginx.exe -s stop
```

または:

```powershell
Stop-Service OpenResty
```

### 設定リロード（ダウンタイムなし）

```powershell
# 設定テスト
cd F:\flatnet\openresty
.\nginx.exe -t

# 問題なければリロード
.\nginx.exe -s reload
```

### 再起動

```powershell
# 完全再起動
cd F:\flatnet\openresty
.\nginx.exe -s stop
Start-Sleep -Seconds 2
.\nginx.exe
```

### 設定テスト

```powershell
cd F:\flatnet\openresty
.\nginx.exe -t

# 出力例（正常時）:
# nginx: the configuration file F:\flatnet\openresty\conf\nginx.conf syntax is ok
# nginx: configuration file F:\flatnet\openresty\conf\nginx.conf test is successful
```

---

## 監視スタック操作

### 起動

```bash
cd ~/prj/flatnet/monitoring
podman-compose up -d
```

### 停止

```bash
cd ~/prj/flatnet/monitoring
podman-compose down
```

### 再起動

```bash
cd ~/prj/flatnet/monitoring
podman-compose restart
```

### 特定サービスのみ再起動

```bash
cd ~/prj/flatnet/monitoring

# Prometheus のみ再起動
podman-compose restart prometheus

# Grafana のみ再起動
podman-compose restart grafana
```

### ログ確認

```bash
cd ~/prj/flatnet/monitoring

# 全サービスのログ（リアルタイム）
podman-compose logs -f

# 特定サービスのログ
podman-compose logs -f prometheus

# 最新 100 行のみ
podman-compose logs --tail 100
```

### 状態確認

```bash
cd ~/prj/flatnet/monitoring
podman-compose ps
```

---

## ログ確認手順

### Gateway ログ

**Windows PowerShell:**

```powershell
# エラーログの末尾 100 行
Get-Content F:\flatnet\openresty\logs\error.log -Tail 100

# アクセスログの末尾 100 行
Get-Content F:\flatnet\openresty\logs\access.log -Tail 100

# リアルタイム監視（Ctrl+C で終了）
Get-Content F:\flatnet\openresty\logs\error.log -Wait

# 特定のパターンを検索
Select-String -Path F:\flatnet\openresty\logs\error.log -Pattern "error"
```

### Grafana でログ検索（Loki）

1. Grafana (`http://localhost:3000`) にアクセス
2. 左メニューから「Explore」を選択
3. データソースで「Loki」を選択
4. LogQL クエリを入力:

```logql
# Gateway のエラーログ
{job="gateway"} |= "error"

# 過去 1 時間のエラー
{job="gateway"} |= "error" | json | __error__=""

# 特定の IP からのリクエスト
{job="gateway"} |= "192.168.1.100"

# 502 エラーの検索
{job="gateway"} |~ "502"
```

### CNI Plugin ログ

**WSL2:**

```bash
# syslog から CNI 関連を検索
grep -i cni /var/log/syslog | tail -50

# または journalctl
journalctl -u podman --since "1 hour ago" | grep -i cni
```

### コンテナログ

```bash
# 特定のコンテナのログ
podman logs <container-name>

# 最新 50 行 + リアルタイム追跡
podman logs --tail 50 -f <container-name>

# タイムスタンプ付き
podman logs --timestamps <container-name>
```

---

## ヘルスチェック手順

### 簡易ヘルスチェック

すべてのサービスの状態を一括確認するコマンド:

**WSL2:**

```bash
#!/bin/bash
# quick-health-check.sh

echo "=== Gateway Health ==="
curl -s http://localhost:8080/api/health && echo " OK" || echo " FAILED"

echo ""
echo "=== Prometheus Health ==="
curl -s http://localhost:9090/-/ready && echo " OK" || echo " FAILED"

echo ""
echo "=== Grafana Health ==="
curl -s http://localhost:3000/api/health | jq -r '.database'

echo ""
echo "=== Alertmanager Health ==="
curl -s http://localhost:9093/-/ready && echo " OK" || echo " FAILED"

echo ""
echo "=== Loki Health ==="
curl -s http://localhost:3100/ready && echo " OK" || echo " FAILED"

echo ""
echo "=== Container Status ==="
podman ps --format "table {{.Names}}\t{{.Status}}"
```

### 詳細ヘルスチェック

#### 1. Gateway 詳細チェック

**Windows PowerShell:**

```powershell
# プロセス確認
Get-Process nginx -ErrorAction SilentlyContinue | Format-Table Id, ProcessName, CPU, WorkingSet64

# ポート確認
netstat -an | Select-String ":80 " | Select-String "LISTENING"

# 接続数確認
netstat -an | Select-String ":80 " | Select-String "ESTABLISHED" | Measure-Object
```

#### 2. Prometheus ターゲット確認

```bash
# 全ターゲットの状態
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

#### 3. WSL2 ネットワーク確認

```bash
# ブリッジ状態
ip addr show flatnet-br0 2>/dev/null || echo "Bridge not found"

# IP フォワーディング
sysctl net.ipv4.ip_forward

# iptables ルール
sudo iptables -L FORWARD -n -v | head -10
```

---

## クイックリファレンス

| 操作 | コマンド |
|------|----------|
| Gateway 起動 | `cd F:\flatnet\openresty && .\nginx.exe` |
| Gateway 停止 | `.\nginx.exe -s stop` |
| Gateway リロード | `.\nginx.exe -s reload` |
| 監視スタック起動 | `cd ~/prj/flatnet/monitoring && podman-compose up -d` |
| 監視スタック停止 | `podman-compose down` |
| ログ確認 | `Get-Content F:\flatnet\openresty\logs\error.log -Tail 50` |
| アラート確認 | `curl http://localhost:9093/api/v2/alerts` |
| 簡易ヘルスチェック | `curl http://localhost:8080/api/health` |

---

## 関連ドキュメント

- [Operations Guide](operations-guide.md) - 詳細な運用手順
- [Runbook](runbook.md) - 障害対応手順
- [Backup/Restore](backup-restore.md) - バックアップ・リストア手順
- [Maintenance](maintenance.md) - メンテナンス手順
- [Troubleshooting](troubleshooting.md) - トラブルシューティング
