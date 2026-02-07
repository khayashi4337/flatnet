# Stage 4: 運用手順書作成

## 概要

日常運用、障害対応、バックアップ・リストアの各手順書を作成する。運用者が迷わずシステムを管理できる状態を目指す。

## ブランチ戦略

- ブランチ名: `phase4/stage-4-operations`
- マージ先: `master`

## インプット（前提条件）

- Stage 1-3（監視・ログ・セキュリティ）が完了している
- システムが安定稼働している
- 運用で必要な作業が明確になっている

## 目標

- 日常運用手順書を作成する
- 障害対応手順書（ランブック）を作成する
- バックアップ・リストア手順を作成し、テストする
- 運用者が独力でシステムを管理できる状態にする

## 手段

- 既存の運用知識を文書化
- 障害パターンの洗い出しと対処手順の整理
- バックアップ・リストア手順の作成とテスト
- 運用チェックリストの作成

---

## Sub-stages

### Sub-stage 4.1: 日常運用手順書

**内容:**
- 定期確認事項の文書化
- メンテナンス作業手順
- アップデート手順

**日常運用チェックリスト:**

毎日:
- [ ] Grafana ダッシュボードでシステム状態を確認
- [ ] アラートが発生していないか確認
- [ ] エラーログを確認

毎週:
- [ ] ディスク使用量の確認
- [ ] バックアップの成功確認
- [ ] 不要なログ・データの削除

毎月:
- [ ] セキュリティアップデートの確認
- [ ] コンテナイメージの更新
- [ ] 脆弱性スキャンの実施

**起動・停止手順:**

```bash
# Gateway 起動 (Windows)
cd C:\openresty
nginx.exe

# Gateway 停止 (Windows)
nginx.exe -s stop

# Gateway 設定リロード
nginx.exe -s reload

# CNI Plugin は Podman 起動時に自動で呼び出される

# 監視スタック起動 (WSL2)
cd /path/to/monitoring
podman-compose up -d

# 監視スタック停止
podman-compose down
```

**ログ確認手順:**

```bash
# Gateway ログ (Windows)
Get-Content C:\openresty\logs\error.log -Tail 100

# Gateway ログ (PowerShell でリアルタイム)
Get-Content C:\openresty\logs\access.log -Wait

# Grafana でログ検索
# 1. Explore を開く
# 2. Loki データソースを選択
# 3. LogQL クエリを入力
```

**完了条件:**
- [ ] 日常運用チェックリストが作成されている
- [ ] 起動・停止手順が文書化されている
- [ ] ログ確認手順が文書化されている

---

### Sub-stage 4.2: 障害対応手順書（ランブック）

**内容:**
- よくある障害パターンの洗い出し
- 各障害に対する対処手順
- エスカレーション基準

**障害パターンと対処手順:**

#### 障害 1: Gateway が応答しない

**症状:**
- ブラウザからアクセスできない
- `http://<Windows IP>/` がタイムアウト

**確認手順:**
1. nginx.exe プロセスが起動しているか確認
   ```powershell
   Get-Process nginx -ErrorAction SilentlyContinue
   ```
2. ポート 80 がリッスンしているか確認
   ```powershell
   netstat -an | findstr :80
   ```
3. エラーログを確認
   ```powershell
   Get-Content C:\openresty\logs\error.log -Tail 50
   ```

**対処:**
- プロセスがない場合: nginx.exe を起動
- ポートがリッスンしていない場合: 設定ファイルを確認、再起動
- エラーがある場合: エラー内容に応じて対処

---

#### 障害 2: WSL2 内サービスに到達できない

**症状:**
- Gateway は動作しているが、502 Bad Gateway が返る

**確認手順:**
1. WSL2 が起動しているか確認
   ```powershell
   wsl --status
   ```
2. WSL2 内でサービスが起動しているか確認
   ```bash
   podman ps
   ```
3. WSL2 の IP アドレスを確認
   ```bash
   hostname -I
   ```
4. nginx.conf の proxy_pass 設定を確認

**対処:**
- WSL2 が停止: `wsl` で起動
- サービスが停止: `podman start <container>` で起動
- IP が変更: nginx.conf を更新して reload

---

#### 障害 3: コンテナが起動しない

**症状:**
- `podman run` がエラーになる
- コンテナが Exited 状態になる

**確認手順:**
1. コンテナの状態を確認
   ```bash
   podman ps -a
   ```
2. コンテナのログを確認
   ```bash
   podman logs <container>
   ```
3. リソース使用状況を確認
   ```bash
   df -h
   free -h
   ```

**対処:**
- ログに応じたエラー対処
- ディスク不足: 不要なイメージ/コンテナを削除
- メモリ不足: 不要なコンテナを停止

---

#### 障害 4: 監視システムが動作しない

**症状:**
- Grafana にアクセスできない
- アラートが発報されない

**確認手順:**
1. 監視コンテナの状態を確認
   ```bash
   podman ps | grep -E "prometheus|grafana|alertmanager|loki"
   ```
2. Prometheus ターゲットの状態を確認
   - `http://prometheus:9090/targets`

**対処:**
- コンテナが停止: `podman-compose up -d` で再起動
- ターゲットがダウン: 対象サービスを確認

---

#### 障害 5: WSL2 の IP アドレスが変更された

**症状:**
- Gateway は動作しているが、502 Bad Gateway が返る
- WSL2 再起動後に発生

**確認手順:**
1. WSL2 の現在の IP を確認
   ```bash
   hostname -I
   ```
2. nginx.conf の proxy_pass 設定を確認
   ```powershell
   Get-Content C:\openresty\conf\nginx.conf | Select-String "proxy_pass"
   ```

**対処:**
```powershell
# 1. WSL2 の IP を取得
$wslIp = (wsl hostname -I).Trim()
Write-Host "WSL2 IP: $wslIp"

# 2. nginx.conf を更新（手動または自動スクリプト）
# 3. 設定リロード
cd C:\openresty
.\nginx.exe -s reload
```

**恒久対策:**
- 起動時に自動で IP を更新するスクリプトを設定（Stage 1 参照）
- または Lua による動的解決を検討

---

**エスカレーション基準:**

| 状況 | エスカレーション先 | 時間 |
|------|-------------------|------|
| 上記手順で復旧しない | 開発チーム | 30分 |
| データ損失の可能性 | 開発チーム + マネージャー | 即時 |
| セキュリティインシデント | セキュリティ担当 | 即時 |

**完了条件:**
- [ ] 主要な障害パターンが洗い出されている
- [ ] 各障害に対する対処手順が文書化されている
- [ ] エスカレーション基準が明確になっている

---

### Sub-stage 4.3: バックアップ・リストア手順

**内容:**
- バックアップ対象の特定
- バックアップスクリプトの作成
- リストア手順の文書化とテスト

**バックアップ対象:**

| 対象 | 場所 | 頻度 | 保持期間 |
|------|------|------|---------|
| Gateway 設定 | C:\openresty\conf\ | 変更時 | 世代管理 |
| CNI Plugin 設定 | /etc/cni/net.d/ | 変更時 | 世代管理 |
| Prometheus データ | /var/lib/prometheus/ | 日次 | 7日 |
| Grafana ダッシュボード | Grafana API 経由 | 日次 | 7日 |
| Loki データ | /var/lib/loki/ | 日次 | 7日 |
| コンテナボリューム | 各コンテナ定義による | 日次 | 7日 |

**バックアップスクリプト例:**

```bash
#!/bin/bash
# backup.sh

BACKUP_DIR="/backup/flatnet/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# 設定ファイルのバックアップ
echo "Backing up configurations..."
cp -r /etc/cni/net.d "$BACKUP_DIR/cni-config"

# Grafana ダッシュボードのエクスポート
echo "Exporting Grafana dashboards..."
mkdir -p "$BACKUP_DIR/grafana-dashboards"
for uid in $(curl -s http://admin:admin@localhost:3000/api/search | jq -r '.[].uid'); do
    curl -s "http://admin:admin@localhost:3000/api/dashboards/uid/$uid" \
        > "$BACKUP_DIR/grafana-dashboards/$uid.json"
done

# Prometheus データのスナップショット
echo "Creating Prometheus snapshot..."
curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot
# スナップショットディレクトリをコピー

# 古いバックアップの削除
echo "Cleaning old backups..."
find /backup/flatnet -type d -mtime +7 -exec rm -rf {} +

echo "Backup completed: $BACKUP_DIR"
```

**リストア手順:**

1. バックアップの確認
   ```bash
   ls -la /backup/flatnet/
   ```

2. 設定ファイルのリストア
   ```bash
   cp -r /backup/flatnet/YYYYMMDD/cni-config/* /etc/cni/net.d/
   ```

3. Grafana ダッシュボードのインポート
   ```bash
   for file in /backup/flatnet/YYYYMMDD/grafana-dashboards/*.json; do
       curl -X POST -H "Content-Type: application/json" \
            -d @"$file" \
            http://admin:admin@localhost:3000/api/dashboards/db
   done
   ```

4. サービスの再起動
   ```bash
   podman-compose restart
   ```

**リストアテスト手順:**
1. テスト環境を用意
2. バックアップからリストアを実行
3. 動作確認:
   - Gateway にアクセスできるか
   - Grafana ダッシュボードが表示されるか
   - ログが検索できるか

**完了条件:**
- [ ] バックアップ対象が特定されている
- [ ] バックアップスクリプトが作成されている
- [ ] リストア手順が文書化されている
- [ ] リストアテストが成功している

---

### Sub-stage 4.4: メンテナンス手順

**内容:**
- 計画メンテナンスの手順
- アップデート手順
- ロールバック手順

**計画メンテナンス手順:**

1. メンテナンス告知
   - 日時、影響範囲、所要時間を通知

2. 事前準備
   - バックアップの取得
   - ロールバック手順の確認

3. メンテナンス実施
   - 監視アラートの一時停止
   - 作業実施
   - 動作確認

4. メンテナンス完了
   - 監視アラートの再開
   - 完了通知

**Gateway アップデート手順:**

```powershell
# 1. バックアップ
Copy-Item -Recurse C:\openresty\conf C:\openresty\conf.bak

# 2. 新しい OpenResty をダウンロード・展開
# 3. 設定ファイルをコピー
Copy-Item -Recurse C:\openresty\conf.bak\* C:\openresty-new\conf\

# 4. 設定テスト
cd C:\openresty-new
.\nginx.exe -t

# 5. 切り替え
.\nginx.exe -s stop  # 旧バージョン
cd C:\openresty-new
.\nginx.exe

# 6. 動作確認
curl http://localhost/

# 問題があれば旧バージョンに戻す
```

**CNI Plugin アップデート手順:**

```bash
# 1. バックアップ
cp /opt/cni/bin/flatnet-cni /opt/cni/bin/flatnet-cni.bak

# 2. 新しいバイナリを配置
cp /path/to/new/flatnet-cni /opt/cni/bin/flatnet-cni
chmod +x /opt/cni/bin/flatnet-cni

# 3. 新しいコンテナで動作確認
podman run --network flatnet test-container

# 問題があればロールバック
cp /opt/cni/bin/flatnet-cni.bak /opt/cni/bin/flatnet-cni
```

**完了条件:**
- [ ] 計画メンテナンス手順が文書化されている
- [ ] 各コンポーネントのアップデート手順が文書化されている
- [ ] ロールバック手順が文書化されている

---

## 成果物

- `docs/operations/daily-operations.md` - 日常運用手順書
- `docs/operations/runbook.md` - 障害対応手順書
- `docs/operations/backup-restore.md` - バックアップ・リストア手順
- `docs/operations/maintenance.md` - メンテナンス手順
- `scripts/backup.sh` - バックアップスクリプト
- 運用チェックリスト

## 完了条件

- [ ] 日常運用手順書が完成している
- [ ] 障害対応手順書が完成している
- [ ] バックアップ・リストア手順が完成し、テスト済み
- [ ] メンテナンス手順が完成している
- [ ] 運用者が手順書を見て作業できることを確認

## 参考情報

### 連絡先一覧

| 役割 | 担当者 | 連絡先 |
|------|--------|--------|
| 開発チーム | TBD | TBD |
| インフラ担当 | TBD | TBD |
| セキュリティ担当 | TBD | TBD |

### 関連ドキュメント

- [監視ダッシュボードガイド](../phase-4/stage-1-monitoring.md)
- [ログ検索ガイド](../phase-4/stage-2-logging.md)
- [セキュリティポリシー](../phase-4/stage-3-security.md)
