# Stage 2: 最小CNIプラグイン実装

## 概要

CNI仕様に準拠した最小限のプラグインを実装する。この Stage では実際のネットワーク設定は行わず、CNIプロトコル（入出力形式、環境変数、終了コード）を正しく実装することに集中する。

## ブランチ戦略

- ブランチ名: `phase2/stage-2-minimal-plugin`
- マージ先: `master`

## インプット（前提条件）

- Stage 1 完了（CNI仕様の理解、Rustプロジェクト初期化済み）
- CNI 入出力形式の知識
- Rust プロジェクトがビルド可能な状態

**前提条件の確認:**
```bash
# Stage 1 成果物の確認
test -f docs/architecture/research/cni-spec.md && echo "[OK] CNI spec doc"
test -f docs/architecture/research/podman-cni.md && echo "[OK] Podman CNI doc"

# Rust プロジェクト確認
cd /home/kh/prj/flatnet/src/flatnet-cni
cargo build --quiet && echo "[OK] Project builds"

# Podman CNI バックエンド
podman info --format '{{.Host.NetworkBackend}}' | grep -q cni && echo "[OK] CNI backend"
```

## 目標

1. CNI プロトコルに準拠した実行ファイルを作成
2. ADD/DEL/CHECK コマンドの骨格を実装
3. 環境変数からの情報取得
4. 正しい JSON 形式での結果出力
5. Podman から呼び出し可能な状態にする

## 手段

### CNI プロトコル実装

CNI プラグインは以下の方式で呼び出される:

```
環境変数:
  CNI_COMMAND=ADD|DEL|CHECK
  CNI_CONTAINERID=<container-id>
  CNI_NETNS=/proc/<pid>/ns/net
  CNI_IFNAME=eth0
  CNI_PATH=/opt/cni/bin

stdin:
  { "cniVersion": "1.0.0", "name": "flatnet", ... }

stdout (成功時):
  { "cniVersion": "1.0.0", "ips": [...], ... }

stderr + exit code (失敗時):
  { "code": 100, "msg": "エラー内容" }
```

---

## Sub-stages

### Sub-stage 2.1: CLI 基盤の実装

**内容:**
- `main.rs` でエントリーポイント作成
- 環境変数 `CNI_COMMAND` の読み取り
- ADD/DEL/CHECK への分岐処理
- 基本的なエラーハンドリング

**実装イメージ:**
```rust
fn main() {
    let result = run();
    match result {
        Ok(output) => {
            println!("{}", serde_json::to_string(&output).unwrap());
            std::process::exit(0);
        }
        Err(e) => {
            eprintln!("{}", serde_json::to_string(&e).unwrap());
            std::process::exit(1);
        }
    }
}
```

**完了条件:**
- [ ] 環境変数 `CNI_COMMAND` を読み取れる
- [ ] ADD/DEL/CHECK で異なる処理パスに分岐する
- [ ] 未知のコマンドでエラーを返す

---

### Sub-stage 2.2: 入力パース（Network Configuration）

**内容:**
- stdin から JSON を読み取り
- Network Configuration の構造体定義
- `serde` によるデシリアライズ
- バリデーション

**データ構造:**
```rust
#[derive(Deserialize)]
struct NetworkConfig {
    cni_version: String,
    name: String,
    #[serde(rename = "type")]
    plugin_type: String,
    // Flatnet 固有の設定
    ipam: Option<IpamConfig>,
}

#[derive(Deserialize)]
struct IpamConfig {
    #[serde(rename = "type")]
    ipam_type: String,
    subnet: String,
}
```

**完了条件:**
- [ ] stdin から JSON を読み取れる
- [ ] Network Configuration をパースできる
- [ ] 不正な JSON でエラーを返す

---

### Sub-stage 2.3: 出力形式（CNI Result）

**内容:**
- CNI Result 構造体の定義
- 成功時の JSON 出力
- エラー時の JSON 出力
- CNI バージョン互換性

**データ構造:**
```rust
#[derive(Serialize)]
struct CniResult {
    cni_version: String,
    interfaces: Vec<Interface>,
    ips: Vec<IpConfig>,
    routes: Vec<Route>,
    dns: DnsConfig,
}

#[derive(Serialize)]
struct CniError {
    code: u32,
    msg: String,
    details: Option<String>,
}
```

**完了条件:**
- [ ] 成功時に正しい JSON を stdout に出力
- [ ] エラー時に正しい JSON を stderr に出力
- [ ] 適切な終了コードを返す

---

### Sub-stage 2.4: Podman 統合テスト（スタブ）

**内容:**
- `/opt/cni/bin/flatnet` にバイナリを配置
- `/etc/cni/net.d/flatnet.conflist` を作成
- `podman network create` で認識されることを確認
- スタブ実装で `podman run --network flatnet` が動作確認

**手順:**

1. **バイナリの配置:**

**重要:** Cargo.toml でバイナリ名を設定するか、コピー時にリネームする。

```bash
# ビルド
cd /home/kh/prj/flatnet/src/flatnet-cni
cargo build --release

# バイナリ名の確認
ls -la target/release/flatnet*
# 出力例: target/release/flatnet-cni（デフォルト名）

# CNI プラグインディレクトリに配置
# 注意: CNI 設定の "type": "flatnet" に合わせてバイナリ名を "flatnet" にする
sudo mkdir -p /opt/cni/bin
sudo cp target/release/flatnet-cni /opt/cni/bin/flatnet
sudo chmod +x /opt/cni/bin/flatnet

# 確認
ls -la /opt/cni/bin/flatnet
# 期待出力: -rwxr-xr-x ... /opt/cni/bin/flatnet
```

**オプション: Cargo.toml でバイナリ名を変更:**
```toml
[[bin]]
name = "flatnet"
path = "src/main.rs"
```

この設定を追加すると、`cargo build --release` で `target/release/flatnet` が生成される。

2. **CNI 設定ファイルの作成:**

ファイル: `/etc/cni/net.d/flatnet.conflist`
```json
{
  "cniVersion": "1.0.0",
  "name": "flatnet",
  "plugins": [
    {
      "type": "flatnet",
      "ipam": {
        "type": "flatnet-ipam",
        "subnet": "10.87.1.0/24",
        "gateway": "10.87.1.1"
      }
    }
  ]
}
```

```bash
# 設定ファイル配置
sudo mkdir -p /etc/cni/net.d
sudo tee /etc/cni/net.d/flatnet.conflist << 'EOF'
{
  "cniVersion": "1.0.0",
  "name": "flatnet",
  "plugins": [
    {
      "type": "flatnet",
      "ipam": {
        "type": "flatnet-ipam",
        "subnet": "10.87.1.0/24",
        "gateway": "10.87.1.1"
      }
    }
  ]
}
EOF
```

3. **動作確認:**
```bash
# ネットワーク一覧に表示されることを確認
podman network ls
# 期待出力: flatnet が一覧に表示される

# テスト実行（スタブ段階ではエラーになるが、呼び出されることを確認）
podman run --rm --network flatnet alpine echo "test" 2>&1 | head -20
```

**完了条件:**
- [ ] `podman network ls` で flatnet が表示される
  ```bash
  podman network ls | grep -q flatnet && echo "OK"
  ```
- [ ] `podman run --network flatnet` で CNI プラグインが呼び出される
- [ ] プラグインのログ出力で呼び出しを確認できる
  ```bash
  # デバッグログの確認（journalctl または syslog）
  journalctl -t flatnet --since "1 hour ago" 2>/dev/null || \
    grep flatnet /var/log/syslog 2>/dev/null || \
    echo "Check plugin's stderr output"
  ```

---

## 成果物

1. `src/flatnet-cni/src/main.rs` - エントリーポイント
2. `src/flatnet-cni/src/config.rs` - 設定パース
3. `src/flatnet-cni/src/result.rs` - 結果出力
4. `src/flatnet-cni/src/error.rs` - エラーハンドリング
5. `configs/flatnet.conflist` - CNI 設定ファイルサンプル

## 完了条件

| 条件 | 確認方法 |
|------|----------|
| バイナリが生成される | `cargo build --release` 成功 |
| 環境変数を読み取れる | 手動テストで CNI_COMMAND を認識 |
| JSON 出力ができる | stdout/stderr に正しい JSON |
| Podman から呼び出される | `podman run --network flatnet` で実行 |
| 単体テストが存在する | `cargo test` で 1 件以上のテスト |

**一括確認スクリプト:**
```bash
#!/bin/bash
echo "=== Stage 2 完了チェック ==="

cd /home/kh/prj/flatnet/src/flatnet-cni

# ビルド確認
cargo build --release --quiet && echo "[OK] Build" || echo "[NG] Build"

# バイナリ配置確認
test -x /opt/cni/bin/flatnet && echo "[OK] Binary installed" || echo "[NG] Binary not installed"

# CNI 設定確認
test -f /etc/cni/net.d/flatnet.conflist && echo "[OK] CNI config" || echo "[NG] CNI config"

# Podman ネットワーク認識
podman network ls 2>/dev/null | grep -q flatnet && echo "[OK] Network visible" || echo "[NG] Network not visible"

# 手動テスト（ADD コマンド）
echo '{"cniVersion":"1.0.0","name":"flatnet","type":"flatnet"}' | \
  CNI_COMMAND=ADD \
  CNI_CONTAINERID=test123 \
  CNI_NETNS=/proc/self/ns/net \
  CNI_IFNAME=eth0 \
  CNI_PATH=/opt/cni/bin \
  /opt/cni/bin/flatnet 2>&1 | head -5
```

## テスト方法

### 手動テスト

```bash
# ビルド
cd /home/kh/prj/flatnet/src/flatnet-cni
cargo build --release

# 配置
sudo cp target/release/flatnet-cni /opt/cni/bin/flatnet
sudo chmod +x /opt/cni/bin/flatnet

# ADD コマンドテスト
echo '{"cniVersion":"1.0.0","name":"flatnet","type":"flatnet"}' | \
  CNI_COMMAND=ADD \
  CNI_CONTAINERID=test123 \
  CNI_NETNS=/proc/self/ns/net \
  CNI_IFNAME=eth0 \
  CNI_PATH=/opt/cni/bin \
  /opt/cni/bin/flatnet
# 期待出力: JSON（スタブ段階では空の Result または固定値）

# DEL コマンドテスト
echo '{"cniVersion":"1.0.0","name":"flatnet","type":"flatnet"}' | \
  CNI_COMMAND=DEL \
  CNI_CONTAINERID=test123 \
  CNI_NETNS=/proc/self/ns/net \
  CNI_IFNAME=eth0 \
  CNI_PATH=/opt/cni/bin \
  /opt/cni/bin/flatnet
# 期待出力: 空（DEL は成功時に出力なし）

# VERSION コマンドテスト
echo '{"cniVersion":"1.0.0","name":"flatnet","type":"flatnet"}' | \
  CNI_COMMAND=VERSION \
  CNI_PATH=/opt/cni/bin \
  /opt/cni/bin/flatnet
# 期待出力: {"cniVersion":"1.0.0","supportedVersions":["1.0.0"]}

# 不正コマンドテスト（エラーが返ることを確認）
echo '{"cniVersion":"1.0.0","name":"flatnet","type":"flatnet"}' | \
  CNI_COMMAND=INVALID \
  CNI_PATH=/opt/cni/bin \
  /opt/cni/bin/flatnet
# 期待出力: stderr に {"code":...,"msg":...} 形式のエラー
```

### 単体テスト

```bash
cd /home/kh/prj/flatnet/src/flatnet-cni
cargo test

# 特定のテストのみ実行
cargo test config::tests

# 詳細出力
cargo test -- --nocapture
```

## 注意事項

- この Stage では実際のネットワーク設定（veth作成、IP割り当て等）は行わない
- 「CNIプロトコルが正しく動作する」ことがゴール
- 実際のネットワーク設定は Stage 3 で実装

## Podman の CNI モード設定

Podman v4 以降は netavark がデフォルトのため、CNI を使用するには明示的な設定が必要:

```bash
# /etc/containers/containers.conf
[network]
network_backend = "cni"
```

または環境変数:
```bash
export CONTAINERS_NETWORK_BACKEND=cni
```

## トラブルシューティング

### `/opt/cni/bin/flatnet` に配置できない

**症状:** Permission denied

**対処:**
```bash
# sudo で配置
sudo cp target/release/flatnet-cni /opt/cni/bin/flatnet
sudo chmod +x /opt/cni/bin/flatnet

# ディレクトリがない場合
sudo mkdir -p /opt/cni/bin
```

### `podman network ls` で flatnet が表示されない

**症状:** CNI 設定ファイルがあるのに認識されない

**対処:**
```bash
# Podman のネットワークバックエンドを確認
podman info --format '{{.Host.NetworkBackend}}'
# "netavark" の場合は Stage 1 の CNI 切り替え手順を参照

# 設定ファイルのパーミッション確認
ls -la /etc/cni/net.d/flatnet.conflist

# 設定ファイルの JSON 構文確認
cat /etc/cni/net.d/flatnet.conflist | jq .
```

### CNI プラグインが呼び出されない

**症状:** `podman run --network flatnet` でプラグインが実行されない

**対処:**
```bash
# バイナリの実行権限確認
ls -la /opt/cni/bin/flatnet

# バイナリを直接実行してエラー確認
/opt/cni/bin/flatnet 2>&1
# 期待: CNI_COMMAND 未設定のエラー

# Podman のデバッグログ
PODMAN_LOG_LEVEL=debug podman run --rm --network flatnet alpine echo test 2>&1 | grep -i cni
```

### JSON パースエラー

**症状:** `serde_json` でデシリアライズに失敗

**対処:**
```bash
# stdin の内容をファイルに出力してデバッグ
# main.rs に以下を一時追加:
# std::fs::write("/tmp/cni-input.json", &input)?;

# 入力を確認
cat /tmp/cni-input.json | jq .
```

## 次の Stage への引き継ぎ事項

- CNI プロトコルのデータ構造（config.rs, result.rs）
- エラーハンドリングパターン（error.rs）
- 環境変数読み取りロジック（main.rs）
- バイナリ配置パス（`/opt/cni/bin/flatnet`）
- CNI 設定ファイルパス（`/etc/cni/net.d/flatnet.conflist`）
