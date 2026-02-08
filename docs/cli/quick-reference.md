# クイックリファレンス

Flatnet CLI コマンドの早見表です。

## コマンド一覧

| コマンド | 説明 |
|----------|------|
| `flatnet status` | システム状態を表示 |
| `flatnet doctor` | システム診断を実行 |
| `flatnet ps` | コンテナ一覧を表示 |
| `flatnet logs <target>` | ログを表示 |
| `flatnet upgrade` | CLI をアップグレード |

## status - システム状態

```bash
flatnet status              # 基本的な状態表示
flatnet status --watch      # リアルタイム監視
flatnet status --json       # JSON 出力
```

## doctor - システム診断

```bash
flatnet doctor              # 全診断を実行
flatnet doctor --verbose    # 詳細情報を表示
flatnet doctor --quiet      # 問題のみ表示（CI向け）
flatnet doctor --json       # JSON 出力
```

### 終了コード

| コード | 意味 |
|--------|------|
| 0 | 全て正常 |
| 1 | 警告あり |
| 2 | エラーあり |

## ps - コンテナ一覧

```bash
flatnet ps                  # 実行中のコンテナを表示
flatnet ps -a               # 全コンテナを表示（停止中含む）
flatnet ps --filter name=x  # 名前でフィルタリング
flatnet ps -q               # ID のみ表示
flatnet ps --json           # JSON 出力
```

## logs - ログ表示

```bash
flatnet logs gateway        # Gateway のログ
flatnet logs <container>    # コンテナのログ
flatnet logs gateway -n 50  # 最新 50 行
flatnet logs gateway -f     # リアルタイム追跡
flatnet logs gateway --since 1h    # 過去 1 時間
flatnet logs gateway --grep error  # パターン検索
```

### コンポーネント名

| 名前 | 対象 |
|------|------|
| `gateway` | Flatnet Gateway |
| `cni` | CNI Plugin |
| `prometheus` | Prometheus |
| `grafana` | Grafana |
| `loki` | Loki |

## upgrade - アップグレード

```bash
flatnet upgrade             # 最新版にアップグレード
flatnet upgrade --check     # 更新確認のみ
flatnet upgrade --version 0.2.0  # 特定バージョンに
```

## 共通オプション

```bash
flatnet --version           # バージョン表示
flatnet --help              # ヘルプ表示
flatnet <command> --help    # コマンドのヘルプ
```

## 環境変数

| 変数 | 説明 |
|------|------|
| `FLATNET_GATEWAY_URL` | Gateway の URL |
| `FLATNET_LOKI_URL` | Loki の URL |
| `NO_COLOR=1` | 色を無効化 |

## よく使うワンライナー

```bash
# 毎朝の確認
flatnet status && flatnet doctor

# 問題の調査
flatnet doctor -v && flatnet logs gateway --since 30m

# CI でのヘルスチェック
flatnet doctor -q || exit 1

# エラーログの確認
flatnet logs gateway --grep -i error --since 1h

# JSON でコンテナ情報を取得
flatnet ps --json | jq '.[] | {name, ip: .flatnet_ip}'
```

## トラブルシューティング

| 問題 | 対処 |
|------|------|
| `command not found` | `export PATH="$PATH:$HOME/.local/bin"` |
| Gateway 接続エラー | Windows 側で Gateway が起動しているか確認 |
| Flatnet IP が `-` | `--network=flatnet` でコンテナを作成 |
| ログが表示されない | Loki が起動しているか確認、Podman にフォールバック |

詳細は [トラブルシューティングガイド](troubleshooting.md) を参照してください。
