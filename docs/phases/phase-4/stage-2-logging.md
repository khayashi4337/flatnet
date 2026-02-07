# Stage 2: ログ収集・分析

## 概要

Gateway、CNI Plugin、コンテナからのログを集約し、検索・分析可能な基盤を構築する。Loki + Grafana による軽量なログスタックを採用し、トラブルシューティングと監査を効率化する。

## ブランチ戦略

- ブランチ名: `phase4/stage-2-logging`
- マージ先: `master`

## インプット（前提条件）

- Stage 1（監視基盤）が完了している
- Grafana が稼働している（Stage 1 で構築済み）
- 各コンポーネントがログを出力している

## 目標

- Gateway、CNI Plugin、コンテナのログを集約する
- ログの検索・フィルタリングができる状態にする
- ログローテーションとリテンション（保持期間）を適切に設定する
- Grafana でログの可視化・分析ができる

## 手段

- Loki をログ集約サーバーとして構築
- Promtail でログを収集し Loki へ送信
- Grafana で Loki をデータソースとして追加
- ログローテーションポリシーを設定

---

## Sub-stages

### Sub-stage 2.1: Loki 構築

**内容:**
- Loki コンテナの構築
- ストレージ設定（ローカルファイルシステム）
- リテンションポリシーの設定

**設定ファイル例:**
```yaml
# loki-config.yml
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2024-01-01
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/cache
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h  # 7 days

chunk_store_config:
  max_look_back_period: 168h  # 7 days

table_manager:
  retention_deletes_enabled: true
  retention_period: 336h  # 14 days
```

**完了条件:**
- [ ] Loki コンテナが起動している
- [ ] Loki API（:3100）が応答する
- [ ] リテンションポリシーが設定されている

---

### Sub-stage 2.2: Promtail 構築

**内容:**
- Promtail コンテナの構築
- ログソースの設定:
  - Gateway（OpenResty）ログ
  - CNI Plugin ログ
  - Podman コンテナログ
  - システムログ（オプション）
- ラベル設定によるログ分類

**設定ファイル例:**
```yaml
# promtail-config.yml
server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  # Gateway (OpenResty on Windows) logs
  # WSL2 から Windows のログを読むには共有フォルダ経由
  - job_name: gateway
    static_configs:
      - targets:
          - localhost
        labels:
          job: gateway
          component: openresty
          # Windows のパスを WSL2 からマウント
          # 例: /mnt/f/flatnet/logs/*.log
          __path__: /mnt/f/flatnet/logs/*.log

  # CNI Plugin logs (WSL2 ネイティブ)
  - job_name: cni-plugin
    static_configs:
      - targets:
          - localhost
        labels:
          job: cni-plugin
          component: flatnet-cni
          __path__: /var/log/flatnet/*.log

  # Podman container logs
  - job_name: containers
    static_configs:
      - targets:
          - localhost
        labels:
          job: containers
          __path__: /var/lib/containers/storage/overlay-containers/*/userdata/ctr.log
    pipeline_stages:
      - json:
          expressions:
            stream: stream
            log: log
            time: time
      - labels:
          stream:
      - output:
          source: log
```

**注意: Windows ログへのアクセス**

WSL2 から Windows 上のログファイルを読み取るには:
1. `/mnt/f/` 経由でアクセス（デフォルトでマウント済み）
2. または Windows 側で Promtail を起動し、Loki に送信

推奨: WSL2 の Promtail で `/mnt/f/flatnet/logs/` を監視

**完了条件:**
- [ ] Promtail コンテナが起動している
- [ ] Gateway ログが収集されている
- [ ] CNI Plugin ログが収集されている
- [ ] コンテナログが収集されている

---

### Sub-stage 2.3: Grafana ログ統合

**内容:**
- Grafana に Loki データソースを追加
- ログ探索用ダッシュボードの作成
- LogQL クエリのテンプレート作成

**ダッシュボードに含めるパネル:**

ログ概要:
- コンポーネント別ログ件数
- エラーログの推移
- 最新のエラーログ一覧

詳細検索:
- ログストリーム表示
- フィルタリング機能
- 時間範囲指定

**便利な LogQL クエリ例:**
```logql
# Gateway のエラーログ
{job="gateway"} |= "error"

# 特定コンテナのログ
{job="containers"} | json | container_name="forgejo"

# 直近1時間のエラー件数
count_over_time({job=~".+"} |= "error" [1h])

# レスポンスタイムが1秒以上のリクエスト
{job="gateway"} | regexp `request_time=(?P<rt>\d+\.\d+)` | rt > 1
```

**完了条件:**
- [ ] Grafana で Loki データソースが設定されている
- [ ] Explore でログ検索ができる
- [ ] ログダッシュボードが作成されている

---

### Sub-stage 2.4: ログローテーション設定

**内容:**
- 各コンポーネントのログローテーション設定
- ディスク使用量の監視設定
- 古いログの自動削除

**Gateway（OpenResty on Windows）のログローテーション:**

Windows ではネイティブな logrotate がないため、以下の方法を検討:

1. PowerShell スクリプトによる定期削除（タスクスケジューラ）
```powershell
# rotate-logs.ps1
$logPath = "F:\flatnet\logs"
$retentionDays = 14

# 古いログファイルを削除
Get-ChildItem -Path $logPath -Filter "*.log.*" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$retentionDays) } |
    Remove-Item -Force

# 現在のログをローテート（日付付きでコピー）
$date = Get-Date -Format "yyyyMMdd"
Copy-Item "$logPath\access.log" "$logPath\access.log.$date"
Copy-Item "$logPath\error.log" "$logPath\error.log.$date"

# nginx にログ再オープンを指示
& F:\flatnet\openresty\nginx.exe -s reopen
```

2. OpenResty の設定でサイズ制限を設定（推奨）
```nginx
# nginx.conf
http {
    # アクセスログをバッファリング
    access_log logs/access.log combined buffer=32k flush=5s;

    # map を使用した日付別ログ（オプション）
    map $time_iso8601 $logdate {
        ~^(?<ymd>\d{4}-\d{2}-\d{2}) $ymd;
        default                       'unknown';
    }
    access_log logs/access-$logdate.log combined;
}
```

**ログ保持ポリシー:**

| ログ種別 | 保持期間 | ローテーション |
|---------|---------|---------------|
| Gateway アクセスログ | 14日 | 日次 |
| Gateway エラーログ | 30日 | 日次 |
| CNI Plugin ログ | 14日 | 日次 |
| コンテナログ | 7日 | サイズベース（100MB） |
| システムログ | 7日 | 日次 |

**完了条件:**
- [ ] 各コンポーネントのログローテーションが設定されている
- [ ] ディスク使用量アラートが設定されている
- [ ] 古いログが自動削除されることを確認

---

### Sub-stage 2.5: ログ出力形式の標準化

**内容:**
- 構造化ログ形式（JSON）の導入
- 共通フィールドの定義
- タイムスタンプ形式の統一

**共通ログフィールド:**
```json
{
  "timestamp": "2024-01-15T10:30:00.123Z",
  "level": "INFO",
  "component": "gateway",
  "message": "Request processed",
  "request_id": "abc-123",
  "duration_ms": 45,
  "extra": {}
}
```

**必須フィールド:**
- `timestamp`: ISO 8601 形式
- `level`: DEBUG, INFO, WARN, ERROR, FATAL
- `component`: コンポーネント名
- `message`: ログメッセージ

**推奨フィールド:**
- `request_id`: リクエスト追跡用 ID
- `duration_ms`: 処理時間
- `error`: エラー詳細（エラー時）

**完了条件:**
- [ ] Gateway のログが JSON 形式で出力される
- [ ] CNI Plugin のログが JSON 形式で出力される
- [ ] 共通フィールドが統一されている

---

## 成果物

- `logging/podman-compose.yml` - ログスタック構成（または monitoring/ に統合）
- `logging/loki/loki-config.yml` - Loki 設定
- `logging/promtail/promtail-config.yml` - Promtail 設定
- `logging/logrotate/` - ログローテーション設定
- `monitoring/grafana/dashboards/logs.json` - ログダッシュボード
- ログ出力形式仕様書

## 完了条件

- [ ] すべてのコンポーネントのログが Loki に集約されている
- [ ] Grafana でログの検索・フィルタリングができる
- [ ] ログローテーションが適切に動作している
- [ ] ログ保持期間が設定通りに機能している
- [ ] ログ形式が標準化されている

## 参考情報

### ポート一覧

| サービス | ポート | 用途 |
|---------|--------|------|
| Loki | 3100 | HTTP API |
| Promtail | 9080 | HTTP（ヘルスチェック） |

### 推奨リソース

| サービス | CPU | メモリ | ストレージ |
|---------|-----|--------|-----------|
| Loki | 0.5 core | 512MB | 20GB（14日保持） |
| Promtail | 0.1 core | 64MB | - |

### トラブルシューティング

**ログが収集されない場合:**
1. Promtail のログを確認: `podman logs promtail`
2. ログファイルのパーミッションを確認
3. ラベル設定が正しいか確認

**Loki のメモリ使用量が高い場合:**
1. `chunk_idle_period` を短くする
2. `max_look_back_period` を短くする
3. リテンション期間を短縮する
