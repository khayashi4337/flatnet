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

**CNI 設定ファイル例:**
```json
{
  "cniVersion": "1.0.0",
  "name": "flatnet",
  "plugins": [
    {
      "type": "flatnet",
      "ipam": {
        "type": "flatnet-ipam",
        "subnet": "10.87.1.0/24"
      }
    }
  ]
}
```

**完了条件:**
- [ ] `podman network ls` で flatnet が表示される
- [ ] `podman run --network flatnet` で CNI プラグインが呼び出される
- [ ] プラグインのログ出力で呼び出しを確認できる

---

## 成果物

1. `src/flatnet-cni/src/main.rs` - エントリーポイント
2. `src/flatnet-cni/src/config.rs` - 設定パース
3. `src/flatnet-cni/src/result.rs` - 結果出力
4. `src/flatnet-cni/src/error.rs` - エラーハンドリング
5. `configs/flatnet.conflist` - CNI 設定ファイルサンプル

## 完了条件

- [ ] `cargo build --release` でバイナリが生成される
- [ ] 環境変数とstdinから入力を読み取れる
- [ ] CNI仕様に準拠したJSON出力ができる
- [ ] Podman から呼び出されることを確認（実際のネットワーク設定はまだ不要）
- [ ] 単体テストが存在する

## テスト方法

### 手動テスト

```bash
# ビルド
cd src/flatnet-cni
cargo build --release

# 配置
sudo cp target/release/flatnet /opt/cni/bin/

# 手動呼び出しテスト
echo '{"cniVersion":"1.0.0","name":"test","type":"flatnet"}' | \
  CNI_COMMAND=ADD \
  CNI_CONTAINERID=test123 \
  CNI_NETNS=/proc/self/ns/net \
  CNI_IFNAME=eth0 \
  CNI_PATH=/opt/cni/bin \
  /opt/cni/bin/flatnet
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

## 次の Stage への引き継ぎ事項

- CNI プロトコルのデータ構造（config.rs, result.rs）
- エラーハンドリングパターン（error.rs）
- 環境変数読み取りロジック（main.rs）
