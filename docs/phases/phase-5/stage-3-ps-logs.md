# Stage 3: ps と logs コマンド

## 概要

コンテナ管理を支援する `flatnet ps` と `flatnet logs` コマンドを実装する。Flatnet IP を含むコンテナ一覧と、各コンポーネントのログを簡単に確認できるようにする。

## ブランチ戦略

- ブランチ名: `phase5/stage-3-ps-logs`
- マージ先: `master`

## インプット（前提条件）

- Stage 1-2 が完了している
- Podman が稼働している
- Gateway API が利用可能

## 目標

- `flatnet ps` でコンテナと Flatnet IP を一覧表示する
- `flatnet logs` でコンポーネントのログを表示する

## 手段

- Podman CLI/API との連携
- Gateway registry からの IP 情報取得
- Loki API によるログ取得

---

## Sub-stages

### Sub-stage 3.1: Podman クライアント

**内容:**
- Podman CLI または API との連携
- コンテナ情報の取得
- ネットワーク情報の取得

**実装オプション:**

1. **Podman CLI 経由（推奨）:**
```rust
use std::process::Command;

pub fn list_containers() -> Result<Vec<Container>> {
    let output = Command::new("podman")
        .args(["ps", "--format", "json"])
        .output()?;

    let containers: Vec<PodmanContainer> = serde_json::from_slice(&output.stdout)?;
    Ok(containers.into_iter().map(Container::from).collect())
}
```

2. **Podman API 経由:**
```rust
// Unix socket: /run/user/1000/podman/podman.sock
let client = PodmanClient::new("/run/user/1000/podman/podman.sock");
let containers = client.list_containers().await?;
```

**完了条件:**
- [ ] Podman からコンテナ一覧を取得できる
- [ ] コンテナのネットワーク情報を取得できる

---

### Sub-stage 3.2: ps コマンド実装

**内容:**
- `flatnet ps` コマンドの実装
- Flatnet IP の表示
- フィルタリングオプション

**出力例:**
```
$ flatnet ps

CONTAINER ID   NAME       IMAGE              FLATNET IP    STATUS
abc123def456   forgejo    forgejo:1.21       10.87.1.10    Up 5 days
789ghi012jkl   nginx      nginx:alpine       10.87.1.11    Up 2 hours
345mno678pqr   postgres   postgres:16        10.87.1.12    Up 5 days

Total: 3 containers, 3 Flatnet IPs allocated
```

**オプション:**
```
flatnet ps                    # すべてのコンテナ
flatnet ps --all              # 停止中も含む
flatnet ps --filter name=foo  # フィルタリング
flatnet ps --json             # JSON 出力
flatnet ps --quiet            # ID のみ
```

**完了条件:**
- [ ] `flatnet ps` が動作する
- [ ] Flatnet IP が表示される
- [ ] フィルタリングが動作する

---

### Sub-stage 3.3: logs コマンド実装

**内容:**
- `flatnet logs` コマンドの実装
- コンポーネント別ログ表示
- Loki/Podman からのログ取得

**対象コンポーネント:**
```
flatnet logs gateway    # Gateway (OpenResty) ログ
flatnet logs cni        # CNI Plugin ログ
flatnet logs prometheus # Prometheus ログ
flatnet logs grafana    # Grafana ログ
flatnet logs loki       # Loki ログ
flatnet logs <container> # 特定コンテナのログ
```

**出力例:**
```
$ flatnet logs gateway --tail 10

2024-01-15T10:30:00Z [INFO] Request: GET /api/status 200 45ms
2024-01-15T10:30:01Z [INFO] Request: GET /api/containers 200 12ms
2024-01-15T10:30:05Z [WARN] Upstream timeout: 10.87.1.10:80
...

$ flatnet logs gateway --follow
(リアルタイム表示)
```

**オプション:**
```
flatnet logs <component>           # 最新ログ
flatnet logs <component> --tail N  # 末尾 N 行
flatnet logs <component> --follow  # リアルタイム
flatnet logs <component> --since 1h # 過去1時間
flatnet logs <component> --grep "error" # フィルタ
```

**完了条件:**
- [ ] `flatnet logs <component>` が動作する
- [ ] `--tail` オプションが動作する
- [ ] `--follow` オプションが動作する

---

### Sub-stage 3.4: Loki 連携

**内容:**
- Loki API クライアントの実装
- LogQL クエリの構築
- ストリーミング対応

**Loki API:**
```
GET /loki/api/v1/query_range
  ?query={job="gateway"}
  &start=<timestamp>
  &end=<timestamp>
  &limit=100
```

**実装例:**
```rust
pub struct LokiClient {
    base_url: String,
    client: reqwest::Client,
}

impl LokiClient {
    pub async fn query_logs(&self, job: &str, limit: u32) -> Result<Vec<LogEntry>> {
        let query = format!("{{job=\"{}\"}}", job);
        let url = format!(
            "{}/loki/api/v1/query_range?query={}&limit={}",
            self.base_url,
            urlencoding::encode(&query),
            limit
        );
        // ...
    }
}
```

**完了条件:**
- [ ] Loki API に接続できる
- [ ] ログを取得して表示できる
- [ ] ストリーミング（--follow）が動作する

---

## 成果物

| 種別 | パス | 説明 |
|------|------|------|
| ソースコード | `src/flatnet-cli/src/commands/ps.rs` | ps コマンド |
| ソースコード | `src/flatnet-cli/src/commands/logs.rs` | logs コマンド |
| ソースコード | `src/flatnet-cli/src/clients/podman.rs` | Podman クライアント |
| ソースコード | `src/flatnet-cli/src/clients/loki.rs` | Loki クライアント |

## 完了条件

- [ ] `flatnet ps` でコンテナ一覧が表示される
- [ ] Flatnet IP が正しく表示される
- [ ] `flatnet logs` で各コンポーネントのログが表示される
- [ ] `--follow` でリアルタイム表示ができる

## 技術メモ

### Flatnet IP の取得

Gateway registry または CNI IPAM から取得:

```rust
// Option 1: Gateway registry API
let containers = gateway_client.get_containers().await?;

// Option 2: IPAM ファイルから直接読み取り
let ipam_state = std::fs::read_to_string("/var/lib/cni/flatnet/ipam.json")?;
```

### ログストリーミング

```rust
use tokio::io::{AsyncBufReadExt, BufReader};

pub async fn follow_logs(container: &str) -> Result<()> {
    let mut child = Command::new("podman")
        .args(["logs", "--follow", container])
        .stdout(Stdio::piped())
        .spawn()?;

    let stdout = child.stdout.take().unwrap();
    let reader = BufReader::new(stdout);
    let mut lines = reader.lines();

    while let Some(line) = lines.next_line().await? {
        println!("{}", line);
    }

    Ok(())
}
```

## 依存関係

- Stage 1-2 完了

## リスク

- Podman バージョンによる出力フォーマットの違い
  - 対策: JSON 出力を使用
- Loki が起動していない場合
  - 対策: フォールバックで Podman logs を使用
