# ユースケース集

Flatnet CLI を使った実践的なシナリオと解決方法を紹介します。

## 日常運用

### 毎朝のシステムチェック

システムが正常に動作しているか確認します。

```bash
# 1. システム状態の概要を確認
flatnet status

# 2. 問題がないか診断
flatnet doctor

# 3. コンテナが全て動いているか確認
flatnet ps
```

スクリプト化する場合:

```bash
#!/bin/bash
echo "=== Flatnet Morning Check ==="
echo ""
echo "--- System Status ---"
flatnet status
echo ""
echo "--- Diagnostics ---"
flatnet doctor
echo ""
echo "--- Containers ---"
flatnet ps
```

### リアルタイム監視

デプロイ中やトラブル対応中に状態を監視します。

```bash
# ターミナル 1: システム状態を監視
flatnet status --watch

# ターミナル 2: Gateway ログをリアルタイムで確認
flatnet logs gateway --follow
```

## トラブルシューティング

### サービスにアクセスできない

外部からサービスにアクセスできない場合の調査手順:

```bash
# 1. システム全体の状態を確認
flatnet status

# 2. Gateway が動いているか確認
flatnet doctor --verbose | grep -A5 Gateway

# 3. 対象のコンテナが動いているか確認
flatnet ps | grep myservice

# 4. コンテナのログを確認
flatnet logs myservice --since 30m

# 5. Gateway のログでエラーを探す
flatnet logs gateway --since 30m --grep error
```

### コンテナが起動しない

コンテナが起動しない、または再起動を繰り返す場合:

```bash
# 1. 全コンテナ（停止中含む）を表示
flatnet ps -a

# 2. コンテナのログを確認
flatnet logs <container-name>

# 3. CNI プラグインの状態を確認
flatnet doctor --verbose | grep -A5 "CNI Plugin"
```

### ネットワーク接続の問題

コンテナ間の通信ができない場合:

```bash
# 1. ネットワーク診断を実行
flatnet doctor --verbose | grep -A10 Network

# 2. 両方のコンテナの Flatnet IP を確認
flatnet ps --json | jq '.[] | {name, flatnet_ip}'

# 3. Gateway のログでルーティングエラーを確認
flatnet logs gateway --grep routing
```

### ディスク容量の問題

ディスク容量が不足している場合:

```bash
# 1. ディスク診断を確認
flatnet doctor | grep -A5 Disk

# 2. コンテナのログサイズを確認
flatnet logs --json | jq 'length'

# 3. 古いログを削除（Podman の場合）
podman system prune --volumes
```

## モニタリング

### Prometheus メトリクスの確認

```bash
# Prometheus が動作しているか確認
flatnet status | grep Prometheus

# Prometheus のログを確認
flatnet logs prometheus --since 1h
```

### Grafana ダッシュボードへのアクセス

```bash
# Grafana が動作しているか確認
flatnet status | grep Grafana

# Grafana の URL を確認
flatnet status --json | jq '.components[] | select(.name == "Grafana")'
```

### ログ集約の確認

```bash
# Loki が動作しているか確認
flatnet status | grep Loki

# Loki 経由でログを検索
flatnet logs gateway --grep "status=500"
```

## CI/CD 連携

### デプロイ前のヘルスチェック

```bash
#!/bin/bash
# deploy.sh

echo "Running pre-deploy health check..."
if ! flatnet doctor --quiet; then
    echo "Health check failed! Aborting deployment."
    exit 1
fi

echo "Health check passed. Starting deployment..."
# デプロイ処理
```

### デプロイ後の検証

```bash
#!/bin/bash
# verify.sh

echo "Waiting for services to start..."
sleep 10

echo "Checking system status..."
flatnet status --json > /tmp/status.json

CONTAINERS=$(jq '.containers' /tmp/status.json)
if [ "$CONTAINERS" -lt 1 ]; then
    echo "No containers running!"
    exit 1
fi

echo "Running diagnostics..."
FAILURES=$(flatnet doctor --json | jq '.summary.failed')
if [ "$FAILURES" -gt 0 ]; then
    echo "Diagnostics found $FAILURES failures!"
    flatnet doctor
    exit 1
fi

echo "Deployment verification successful!"
```

### GitHub Actions での利用

```yaml
# .github/workflows/deploy.yml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Install Flatnet CLI
        run: |
          curl -fsSL https://raw.githubusercontent.com/khayashi4337/flatnet/master/scripts/install-cli.sh | bash
          echo "$HOME/.local/bin" >> $GITHUB_PATH

      - name: Health Check
        run: flatnet doctor --quiet

      - name: Deploy
        run: ./deploy.sh

      - name: Verify Deployment
        run: |
          flatnet status
          flatnet ps
```

## 自動化スクリプト

### 定期ヘルスチェック（cron）

```bash
# /etc/cron.d/flatnet-healthcheck
# 5分ごとにヘルスチェック
*/5 * * * * user /home/user/.local/bin/flatnet doctor --quiet >> /var/log/flatnet-health.log 2>&1
```

### Slack 通知連携

```bash
#!/bin/bash
# healthcheck-slack.sh

RESULT=$(flatnet doctor --json)
FAILURES=$(echo "$RESULT" | jq '.summary.failed')
WARNINGS=$(echo "$RESULT" | jq '.summary.warnings')

if [ "$FAILURES" -gt 0 ]; then
    curl -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\":x: Flatnet health check failed! $FAILURES failures, $WARNINGS warnings\"}" \
        "$SLACK_WEBHOOK_URL"
fi
```

### ログローテーション監視

```bash
#!/bin/bash
# check-logs.sh

# 過去 1 時間のエラーログをカウント
ERRORS=$(flatnet logs gateway --since 1h --grep -i error | wc -l)

if [ "$ERRORS" -gt 100 ]; then
    echo "Warning: $ERRORS errors in the last hour"
    # アラートを送信
fi
```

## Tips

### JSON 出力の活用

```bash
# コンテナ名と IP の一覧
flatnet ps --json | jq -r '.[] | "\(.name)\t\(.flatnet_ip)"'

# 実行中のコンテナ数
flatnet status --json | jq '.containers'

# 失敗したチェック項目
flatnet doctor --json | jq '.checks[] | select(.status == "Fail")'
```

### シェルエイリアス

`~/.bashrc` に追加:

```bash
alias fns='flatnet status'
alias fnd='flatnet doctor'
alias fnp='flatnet ps'
alias fnl='flatnet logs'
alias fnw='flatnet status --watch'
```

### 複数コンテナのログを同時に見る

```bash
# tmux を使って複数のログを同時表示
tmux new-session -d -s logs 'flatnet logs gateway -f'
tmux split-window -h 'flatnet logs myservice -f'
tmux attach -t logs
```
