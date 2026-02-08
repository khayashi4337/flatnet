# WSL2 + Podman 環境を快適にする Flatnet CLI を公開しました

WSL2 で Podman を使っていて、こんな悩みはありませんか？

- 社内 LAN からコンテナにアクセスできない
- NAT が何重にもなっていて、ポートフォワードが面倒
- コンテナの IP アドレスを毎回調べるのが大変
- 複数のコンポーネントの状態を一目で確認したい

これらの問題を解決するために、**Flatnet** というプロジェクトを開発しています。そして今回、その管理ツールである **Flatnet CLI** を公開しました。

## Flatnet とは

Flatnet は、WSL2 + Podman 環境の「NAT 地獄」を解消するためのツールセットです。

```
従来の構成:
社内LAN → Windows → WSL2 → コンテナ（3段NAT）

Flatnet を使った構成:
社内LAN → Gateway → コンテナ（フラットに到達）
```

Windows 上で動作する Gateway が、社内 LAN からのリクエストを WSL2 内のコンテナに直接ルーティングします。クライアント側は HTTP でアクセスするだけ。特別なソフトウェアのインストールは不要です。

## Flatnet CLI でできること

Flatnet CLI は、この Flatnet システムを管理するためのコマンドラインツールです。

### システム状態の確認

```bash
$ flatnet status
╭─────────────────────────────────────────────────────╮
│ Flatnet System Status                               │
├─────────────────────────────────────────────────────┤
│ Gateway      ● Running    10.100.1.1:8080           │
│ CNI Plugin   ● Ready      10.100.x.0/24 (5 IPs)     │
│ Healthcheck  ● Running    5 healthy, 0 unhealthy    │
│ Prometheus   ● Running    :9090                     │
│ Grafana      ● Running    :3000                     │
│ Loki         ● Running    :3100                     │
╰─────────────────────────────────────────────────────╯

Containers: 5 running
```

一目でシステム全体の状態がわかります。Gateway、CNI Plugin、モニタリングスタック、すべてのステータスを統合表示。

### システム診断

```bash
$ flatnet doctor
Running system diagnostics...

Gateway
  [✓] Gateway Connectivity
  [✓] Gateway API

Network
  [✓] Windows host reachable
  [✓] Container network connectivity

Monitoring
  [✓] Prometheus
  [!] Grafana (port 3000 not responding)
      → Start Grafana: podman start grafana
  [✓] Loki

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Summary: 7 passed, 1 warnings, 0 failed
```

問題があれば、解決方法まで提案してくれます。「動かない」で終わらず、「どうすれば動くか」がわかる。

### コンテナ一覧

```bash
$ flatnet ps
CONTAINER ID  NAME      IMAGE                 FLATNET IP      STATUS
a1b2c3d4e5f6  web       nginx:latest          10.100.1.10     Up 2 hours
b2c3d4e5f6a7  api       myapp:v1              10.100.1.11     Up 1 hour
c3d4e5f6a7b8  forgejo   codeberg/forgejo:9    10.100.1.12     Up 3 hours
```

Podman の `ps` コマンドとの違いは、**Flatnet IP** が表示されること。このIPアドレスを使えば、社内LANから直接アクセスできます。

### 統合ログビューア

```bash
# Gateway のログを確認
$ flatnet logs gateway --since 1h

# コンテナのログを確認
$ flatnet logs myapp --follow

# エラーだけ抽出
$ flatnet logs gateway --grep error
```

Gateway、CNI Plugin、各コンテナのログを統一されたインターフェースで確認できます。Loki が動いていればそこから取得し、なければ Podman にフォールバック。

### セルフアップグレード

```bash
$ flatnet upgrade
Current version: 0.1.0
Latest version:  0.2.0

Downloading flatnet v0.2.0...
[########################################] 100%
Download complete.

Upgraded successfully to v0.2.0!
```

GitHub Releases から最新版をダウンロードして自動更新。パッケージマネージャ不要。

## インストール

ワンライナーでインストールできます。

```bash
curl -fsSL https://raw.githubusercontent.com/khayashi4337/flatnet/master/scripts/install-cli.sh | bash
```

これだけで `~/.local/bin/flatnet` にインストールされます。

## 実装について

Flatnet CLI は Rust で書かれています。

- **clap**: コマンドライン引数のパース
- **tokio**: 非同期ランタイム
- **reqwest**: HTTP クライアント
- **serde**: JSON シリアライズ
- **colored + tabled**: ターミナル出力の装飾

シングルバイナリで配布されるため、依存関係のインストールは不要です。

## CI/CD との連携

`flatnet doctor` は CI/CD パイプラインでも使えます。

```bash
# エラーがあれば非ゼロで終了
flatnet doctor --quiet

# JSON 出力でスクリプトから利用
flatnet doctor --json | jq '.summary.failed'
```

デプロイ前のヘルスチェックや、デプロイ後の検証に便利です。

## 実装済みの機能

Flatnet プロジェクトは全フェーズの開発が完了しています。

- **Phase 1**: Gateway 基盤 - NAT 越えの基本機能
- **Phase 2**: CNI Plugin - コンテナの自動 IP 割り当て
- **Phase 3**: マルチホスト - 複数の WSL2 ホスト間通信
- **Phase 4**: 本番運用準備 - 監視・ログ・セキュリティ
- **Phase 5**: CLI Tool - システム管理ツール

## まとめ

Flatnet CLI を使えば、WSL2 + Podman 環境の管理が格段に楽になります。

- **一目でわかる**: システム全体の状態を統合表示
- **問題解決**: 診断機能で問題を特定し、解決策を提案
- **統一インターフェース**: ログ、コンテナ、アップグレードを一つのツールで

ぜひ試してみてください。

```bash
curl -fsSL https://raw.githubusercontent.com/khayashi4337/flatnet/master/scripts/install-cli.sh | bash
flatnet status
```

## リンク

- [GitHub リポジトリ](https://github.com/khayashi4337/flatnet)
- [ドキュメント](https://github.com/khayashi4337/flatnet/tree/master/docs/cli)
- [チュートリアル](https://github.com/khayashi4337/flatnet/blob/master/docs/cli/getting-started.md)

フィードバックや Issue は GitHub でお待ちしています。
