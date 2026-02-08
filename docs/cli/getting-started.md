# はじめに - Flatnet CLI チュートリアル

このチュートリアルでは、Flatnet CLI を使ってシステムを管理する方法を学びます。

## 前提条件

- WSL2 (Ubuntu) がインストールされていること
- Podman がインストールされていること
- Windows 側で Flatnet Gateway が動作していること

## ステップ 1: インストール

まず、Flatnet CLI をインストールします。

```bash
curl -fsSL https://raw.githubusercontent.com/khayashi4337/flatnet/master/scripts/install-cli.sh | bash
```

インストールが完了したら、バージョンを確認します。

```bash
flatnet --version
```

出力例:
```
flatnet 0.1.0
```

### PATH の設定

もし `flatnet: command not found` と表示された場合は、PATH を設定します。

```bash
echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
source ~/.bashrc
```

## ステップ 2: システム状態の確認

### 基本的な状態確認

まず、システム全体の状態を確認しましょう。

```bash
flatnet status
```

出力例:
```
╭─────────────────────────────────────────────────────╮
│ Flatnet System Status                               │
├─────────────────────────────────────────────────────┤
│ Gateway      ● Running    10.100.1.1:8080           │
│ CNI Plugin   ● Ready      10.100.x.0/24 (3 IPs)     │
│ Healthcheck  ● Running    3 healthy, 0 unhealthy    │
│ Prometheus   ● Running    :9090                     │
│ Grafana      ● Running    :3000                     │
│ Loki         ● Running    :3100                     │
╰─────────────────────────────────────────────────────╯

Containers: 3 running
```

### 状態インジケータの読み方

| シンボル | 色 | 意味 |
|---------|-----|------|
| ● | 緑 | 正常動作中 |
| ● | 黄色 | 注意が必要 |
| ○ | 赤 | 停止またはエラー |

### リアルタイム監視

`--watch` オプションでリアルタイム監視ができます。

```bash
flatnet status --watch
```

`Ctrl+C` で終了します。

## ステップ 3: システム診断

問題がある場合は、`doctor` コマンドで診断を実行します。

```bash
flatnet doctor
```

出力例:
```
Running system diagnostics...

Gateway
  [✓] Gateway Connectivity
  [✓] Gateway API

CNI Plugin
  [✓] CNI Plugin installed
  [✓] CNI configuration valid

Network
  [✓] Windows host reachable
  [✓] Container network connectivity

Monitoring
  [✓] Prometheus
  [✓] Grafana
  [✓] Loki

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Summary: 8 passed, 0 warnings, 0 failed
```

### 診断結果の読み方

| シンボル | 意味 | 対応 |
|---------|------|------|
| ✓ | 正常 | 対応不要 |
| ! | 警告 | 確認推奨 |
| ✗ | エラー | 対応必須 |

警告やエラーがある場合は、提案されるコマンドで対処できます。

```
Monitoring
  [!] Grafana (port 3000 not responding)
      → Start Grafana: podman start grafana
```

### 詳細情報の表示

より詳しい情報が必要な場合は `--verbose` オプションを使います。

```bash
flatnet doctor --verbose
```

## ステップ 4: コンテナの確認

Flatnet ネットワーク上のコンテナを確認します。

```bash
flatnet ps
```

出力例:
```
CONTAINER ID  NAME      IMAGE                 FLATNET IP      STATUS
a1b2c3d4e5f6  web       nginx:latest          10.100.1.10     Up 2 hours
b2c3d4e5f6a7  api       myapp:v1              10.100.1.11     Up 1 hour
c3d4e5f6a7b8  forgejo   codeberg/forgejo:9    10.100.1.12     Up 3 hours
```

### 全コンテナの表示

停止中のコンテナも含めて表示するには `-a` オプションを使います。

```bash
flatnet ps -a
```

### コンテナのフィルタリング

名前でフィルタリングできます。

```bash
flatnet ps --filter name=web
```

## ステップ 5: ログの確認

### コンポーネントのログ

Gateway のログを確認します。

```bash
flatnet logs gateway
```

その他のコンポーネント:
- `gateway` - Flatnet Gateway
- `cni` - CNI Plugin
- `prometheus` - Prometheus
- `grafana` - Grafana
- `loki` - Loki

### コンテナのログ

特定のコンテナのログを確認します。

```bash
flatnet logs forgejo
```

### 便利なオプション

```bash
# 最新 50 行だけ表示
flatnet logs gateway -n 50

# リアルタイムでログを追跡
flatnet logs gateway --follow

# 過去 1 時間のログを表示
flatnet logs gateway --since 1h

# パターンでフィルタリング
flatnet logs gateway --grep error
```

## ステップ 6: CLI のアップグレード

新しいバージョンがあるか確認します。

```bash
flatnet upgrade --check
```

出力例:
```
Current version: 0.1.0
Latest version:  0.2.0

Update available: v0.1.0 -> v0.2.0

Run 'flatnet upgrade' to upgrade.
```

最新版にアップグレードします。

```bash
flatnet upgrade
```

## よくある使い方

### 朝の確認作業

毎朝、システムの状態を確認するルーチン:

```bash
# 1. システム状態を確認
flatnet status

# 2. 問題がないか診断
flatnet doctor

# 3. コンテナが動いているか確認
flatnet ps
```

### 問題発生時の調査

サービスに問題が発生した場合:

```bash
# 1. まず診断を実行
flatnet doctor --verbose

# 2. 問題のあるコンポーネントのログを確認
flatnet logs gateway --since 30m

# 3. 関連するコンテナのログを確認
flatnet logs myservice --grep error
```

### CI/CD での利用

```bash
# ヘルスチェック（エラーがあれば非ゼロで終了）
flatnet doctor --quiet
```

```bash
# JSON 出力でスクリプトから利用
FAILURES=$(flatnet doctor --json | jq '.summary.failed')
if [ "$FAILURES" -gt 0 ]; then
    echo "Health check failed!"
    exit 1
fi
```

## ヘルプの確認

いつでもヘルプを確認できます。

```bash
# 全コマンドの一覧
flatnet --help

# 特定のコマンドのヘルプ
flatnet status --help
flatnet doctor --help
flatnet ps --help
flatnet logs --help
flatnet upgrade --help
```

## 次のステップ

- [コマンドリファレンス](README.md) - 全コマンドの詳細
- [設定ガイド](configuration.md) - 詳細な設定方法
- [トラブルシューティング](troubleshooting.md) - 問題の解決方法
