# Stage 2: doctor コマンド

## 概要

システム診断機能を提供する `flatnet doctor` コマンドを実装する。問題を自動検出し、修正方法を提案することで、トラブルシューティングを効率化する。

## ブランチ戦略

- ブランチ名: `phase5/stage-2-doctor`
- マージ先: `master`

## インプット（前提条件）

- Stage 1 が完了している
- Gateway API が稼働している

## 目標

- `flatnet doctor` コマンドを実装する
- 各コンポーネントの問題を検出する
- 修正方法を提案する

## 手段

- 各コンポーネントへのヘルスチェック
- 設定ファイルの検証
- ネットワーク接続テスト

---

## Sub-stages

### Sub-stage 2.1: チェック項目の定義

**内容:**
- 診断チェック項目の設計
- 重要度レベルの定義
- 推奨アクションの定義

**チェック項目:**

| カテゴリ | チェック | 重要度 | 推奨アクション |
|---------|---------|--------|---------------|
| Gateway | HTTP 応答 | Critical | nginx.exe を起動 |
| Gateway | メトリクス | Warning | ポート 9145 を確認 |
| CNI | ブリッジ存在 | Critical | CNI 設定を確認 |
| CNI | IPAM 状態 | Warning | IPAM ファイルを確認 |
| Nebula | トンネル状態 | Warning | Nebula サービスを確認 |
| Monitoring | Prometheus | Warning | podman-compose up |
| Monitoring | Grafana | Warning | podman-compose up |
| Network | WSL2→Windows | Critical | ファイアウォール確認 |
| Disk | 使用率 | Warning | ログ/イメージ削除 |

**完了条件:**
- [ ] チェック項目が定義されている
- [ ] 重要度レベルが設計されている

---

### Sub-stage 2.2: チェック実装

**内容:**
- 各チェック項目の実装
- 並列実行による高速化
- タイムアウト処理

**実装例:**
```rust
pub struct CheckResult {
    pub name: String,
    pub status: CheckStatus,
    pub message: String,
    pub suggestion: Option<String>,
}

pub enum CheckStatus {
    Pass,
    Warning,
    Fail,
}

pub async fn check_gateway_http(config: &Config) -> CheckResult {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(5))
        .build()
        .unwrap();

    match client.get(&format!("{}/api/health", config.gateway.url)).send().await {
        Ok(resp) if resp.status().is_success() => CheckResult {
            name: "Gateway HTTP".into(),
            status: CheckStatus::Pass,
            message: "Gateway is responding".into(),
            suggestion: None,
        },
        Ok(resp) => CheckResult {
            name: "Gateway HTTP".into(),
            status: CheckStatus::Warning,
            message: format!("Unexpected status: {}", resp.status()),
            suggestion: Some("Check Gateway logs".into()),
        },
        Err(e) => CheckResult {
            name: "Gateway HTTP".into(),
            status: CheckStatus::Fail,
            message: format!("Connection failed: {}", e),
            suggestion: Some("Start Gateway: cd F:\\flatnet\\openresty && nginx.exe".into()),
        },
    }
}
```

**完了条件:**
- [ ] すべてのチェック項目が実装されている
- [ ] チェックが並列実行される
- [ ] タイムアウトが適切に処理される

---

### Sub-stage 2.3: 出力フォーマット

**内容:**
- チェック結果の表示フォーマット
- カラーコーディング
- サマリー表示

**出力例:**
```
$ flatnet doctor

Running system diagnostics...

Gateway
  [✓] HTTP responding (10.100.1.1:80)
  [✓] API available (:8080)
  [!] Metrics endpoint not responding (:9145)
      → Check if metrics server is enabled in nginx.conf

CNI Plugin
  [✓] Bridge exists (flatnet-br0)
  [✓] IPAM state valid (3 IPs allocated)

Nebula
  [✓] Tunnel active
  [✓] 2 peers connected

Monitoring
  [✓] Prometheus running (:9090)
  [✓] Grafana running (:3000)
  [✓] Loki running (:3100)

Network
  [✓] WSL2 → Windows connectivity OK
  [✓] DNS resolution OK

Disk
  [!] Disk usage at 82%
      → Consider cleaning up: podman system prune

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Summary: 10 passed, 2 warnings, 0 failed
```

**完了条件:**
- [ ] 出力フォーマットが実装されている
- [ ] カラーコーディングが適用されている
- [ ] サマリーが表示される

---

### Sub-stage 2.4: オプションと出力形式

**内容:**
- `--json` オプション
- `--quiet` オプション（CI 用）
- `--fix` オプション（自動修復、将来用）

**オプション:**
```
flatnet doctor              # デフォルト表示
flatnet doctor --json       # JSON 出力
flatnet doctor --quiet      # 問題のみ表示
flatnet doctor --verbose    # 詳細表示
```

**完了条件:**
- [ ] `--json` オプションが動作する
- [ ] `--quiet` オプションが動作する
- [ ] 終了コードが適切（0=OK, 1=Warning, 2=Fail）

---

## 成果物

| 種別 | パス | 説明 |
|------|------|------|
| ソースコード | `src/flatnet-cli/src/commands/doctor.rs` | doctor コマンド |
| ソースコード | `src/flatnet-cli/src/checks/` | チェック実装 |

## 完了条件

- [ ] `flatnet doctor` が動作する
- [ ] すべてのチェック項目が実行される
- [ ] 問題が検出された場合に推奨アクションが表示される
- [ ] 終了コードが正しく設定される

## 技術メモ

### 並列チェック実行

```rust
use futures::future::join_all;

pub async fn run_all_checks(config: &Config) -> Vec<CheckResult> {
    let checks = vec![
        check_gateway_http(config),
        check_gateway_metrics(config),
        check_cni_bridge(config),
        check_prometheus(config),
        // ...
    ];

    join_all(checks).await
}
```

### 終了コード

```rust
fn determine_exit_code(results: &[CheckResult]) -> i32 {
    if results.iter().any(|r| r.status == CheckStatus::Fail) {
        2
    } else if results.iter().any(|r| r.status == CheckStatus::Warning) {
        1
    } else {
        0
    }
}
```

## 依存関係

- Stage 1 完了

## リスク

- チェック項目が多すぎると実行時間が長くなる
  - 対策: 並列実行、タイムアウト設定
