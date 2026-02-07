# Stage 1: 監視基盤構築

## 概要

Prometheus と Grafana を使用した監視基盤を構築する。Gateway と CNI Plugin の状態をリアルタイムで可視化し、異常時にアラートを発報する仕組みを整備する。

## ブランチ戦略

- ブランチ名: `phase4/stage-1-monitoring`
- マージ先: `master`

## インプット（前提条件）

- Phase 1-3 が完了し、Gateway と CNI Plugin が稼働している
- WSL2 環境で Podman が利用可能
- 監視用のリソース（メモリ 2GB 以上推奨）が確保されている

## 目標

- Gateway と CNI Plugin の主要メトリクスを収集する
- Grafana ダッシュボードでシステム状態を可視化する
- 異常検知時にアラートが発報される仕組みを構築する

## 手段

- Prometheus をコンテナとして WSL2 上に構築
- Gateway（OpenResty）に Prometheus exporter を追加
- CNI Plugin にメトリクスエンドポイントを実装
- Grafana でダッシュボードを構築
- Alertmanager でアラート通知を設定

---

## Sub-stages

### Sub-stage 1.1: Prometheus 構築

**内容:**
- Prometheus コンテナの構築
- prometheus.yml の設定（スクレイプターゲット定義）
- データ永続化の設定（volume マウント）

**設定ファイル例:**
```yaml
# prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

rule_files:
  - "alerts/*.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'gateway'
    static_configs:
      - targets: ['host.containers.internal:9145']

  - job_name: 'cni-plugin'
    static_configs:
      - targets: ['host.containers.internal:9146']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
```

**完了条件:**
- [ ] Prometheus コンテナが起動している
- [ ] Prometheus UI（:9090）にアクセスできる
- [ ] 設定されたターゲットがスクレイプされている

---

### Sub-stage 1.2: Gateway メトリクス公開

**内容:**
- OpenResty に nginx-prometheus-exporter を追加
- または Lua による独自メトリクスエンドポイント実装
- 収集するメトリクス:
  - リクエスト数（総数、ステータスコード別）
  - レスポンスタイム（平均、p50、p95、p99）
  - アクティブコネクション数
  - アップストリーム（WSL2）の状態

**完了条件:**
- [ ] Gateway のメトリクスエンドポイント（:9145/metrics）が動作する
- [ ] Prometheus でメトリクスが収集されている

---

### Sub-stage 1.3: CNI Plugin メトリクス公開

**内容:**
- CNI Plugin に Prometheus メトリクスエンドポイントを追加（Rust: prometheus クレート使用）
- 収集するメトリクス:
  - コンテナ数（アクティブ、総作成数）
  - IP アドレス割り当て状況
  - Gateway 登録成功/失敗数
  - 処理時間

**完了条件:**
- [ ] CNI Plugin のメトリクスエンドポイント（:9146/metrics）が動作する
- [ ] Prometheus でメトリクスが収集されている

---

### Sub-stage 1.4: Node Exporter 追加

**内容:**
- Node Exporter コンテナの構築
- ホストシステムのメトリクス収集:
  - CPU 使用率
  - メモリ使用率
  - ディスク使用率
  - ネットワーク I/O

**完了条件:**
- [ ] Node Exporter コンテナが起動している
- [ ] ホストメトリクスが Prometheus で収集されている

---

### Sub-stage 1.5: Grafana ダッシュボード構築

**内容:**
- Grafana コンテナの構築
- Prometheus データソースの設定
- ダッシュボードの作成:
  - システム概要ダッシュボード
  - Gateway 詳細ダッシュボード
  - CNI Plugin 詳細ダッシュボード

**ダッシュボードに含めるパネル:**

システム概要:
- サービス稼働状態（Up/Down）
- リクエスト数の推移
- エラーレート
- リソース使用率

Gateway 詳細:
- リクエスト数（ステータスコード別）
- レスポンスタイム分布
- アップストリーム状態
- アクティブコネクション

CNI Plugin 詳細:
- コンテナ数推移
- IP 割り当て状況
- 処理成功/失敗率

**完了条件:**
- [ ] Grafana コンテナが起動している
- [ ] Grafana UI にアクセスできる
- [ ] 3つのダッシュボードが作成されている
- [ ] メトリクスがリアルタイムで表示される

---

### Sub-stage 1.6: アラート設定

**内容:**
- Alertmanager コンテナの構築
- アラートルールの定義
- 通知先の設定（Slack/Email）

**アラートルール例:**
```yaml
# alerts/gateway.yml
groups:
  - name: gateway
    rules:
      - alert: GatewayDown
        expr: up{job="gateway"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Gateway is down"
          description: "Gateway has been down for more than 1 minute."

      - alert: HighErrorRate
        expr: rate(nginx_http_requests_total{status=~"5.."}[5m]) / rate(nginx_http_requests_total[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected"
          description: "Error rate is above 5% for 5 minutes."

      - alert: HighLatency
        expr: histogram_quantile(0.95, rate(nginx_http_request_duration_seconds_bucket[5m])) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High latency detected"
          description: "95th percentile latency is above 1 second."
```

**必須アラート:**
- Gateway ダウン（critical）
- CNI Plugin ダウン（critical）
- 高エラーレート（warning）
- 高レイテンシ（warning）
- ディスク使用率 80% 超過（warning）
- ディスク使用率 90% 超過（critical）

**完了条件:**
- [ ] Alertmanager コンテナが起動している
- [ ] アラートルールが設定されている
- [ ] テストアラートが通知先に届く
- [ ] Grafana でアラート状態が確認できる

---

## 成果物

- `monitoring/podman-compose.yml` - 監視スタック構成（Podman Compose 形式）
- `monitoring/prometheus/prometheus.yml` - Prometheus 設定
- `monitoring/prometheus/alerts/` - アラートルール
- `monitoring/alertmanager/alertmanager.yml` - Alertmanager 設定
- `monitoring/grafana/dashboards/` - Grafana ダッシュボード JSON
- `monitoring/grafana/provisioning/` - Grafana プロビジョニング設定

## 環境固有の考慮事項

### Windows 上の Gateway への接続

WSL2 から Windows 上の Gateway（OpenResty）にアクセスするには:

```yaml
# prometheus.yml での Gateway ターゲット設定
scrape_configs:
  - job_name: 'gateway'
    static_configs:
      # WSL2 から Windows ホストへのアクセス
      # host.docker.internal または $(hostname).local を使用
      - targets: ['host.docker.internal:9145']
```

WSL2 から Windows IP を取得する方法:
```bash
# /etc/resolv.conf の nameserver が Windows IP
cat /etc/resolv.conf | grep nameserver | awk '{print $2}'
```

## 完了条件

- [ ] Prometheus がすべてのターゲットからメトリクスを収集している
- [ ] Grafana ダッシュボードでシステム状態が可視化されている
- [ ] アラートが設定され、テスト通知が成功している
- [ ] 監視スタックが `podman-compose up -d` で起動できる

## 参考情報

### ポート一覧

| サービス | ポート | 用途 |
|---------|--------|------|
| Prometheus | 9090 | UI、API |
| Grafana | 3000 | UI |
| Alertmanager | 9093 | UI、API |
| Node Exporter | 9100 | メトリクス |
| Gateway Exporter | 9145 | メトリクス |
| CNI Exporter | 9146 | メトリクス |

### 推奨リソース

| サービス | CPU | メモリ | ストレージ |
|---------|-----|--------|-----------|
| Prometheus | 0.5 core | 512MB | 10GB（2週間保持） |
| Grafana | 0.5 core | 256MB | 1GB |
| Alertmanager | 0.1 core | 64MB | 100MB |
| Node Exporter | 0.1 core | 32MB | - |
