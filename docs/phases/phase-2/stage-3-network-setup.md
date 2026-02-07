# Stage 3: ネットワーク設定

## 概要

実際のネットワーク設定を実装する。vethペアの作成、IPアドレスの割り当て、ルーティング設定を行い、コンテナがFlatnet IPで通信可能な状態を作る。

## ブランチ戦略

- ブランチ名: `phase2/stage-3-network-setup`
- マージ先: `master`

## インプット（前提条件）

- Stage 2 完了（最小CNIプラグインが動作）
- CNI プロトコルが正しく実装済み
- Podman から呼び出し可能な状態

**前提条件の確認:**
```bash
# バイナリ確認
test -x /opt/cni/bin/flatnet && echo "[OK] Binary"

# CNI 設定確認
test -f /etc/cni/net.d/flatnet.conflist && echo "[OK] CNI config"

# Podman ネットワーク認識
podman network ls | grep -q flatnet && echo "[OK] Network"

# スタブ動作確認
echo '{"cniVersion":"1.0.0","name":"flatnet","type":"flatnet"}' | \
  CNI_COMMAND=VERSION CNI_PATH=/opt/cni/bin /opt/cni/bin/flatnet | \
  jq -e '.cniVersion' >/dev/null && echo "[OK] Plugin responds"
```

## 目標

1. veth ペアを作成しコンテナとホストを接続
2. コンテナに Flatnet IP を割り当て
3. ホスト側にブリッジまたはルーティングを設定
4. コンテナ削除時のクリーンアップ
5. IP アドレス管理（IPAM）の実装

## 手段

### ネットワーク構成

```
[Host Network Namespace]
    │
    │ flatnet-br0 (bridge) or routing
    │
    ├── veth-<container-id-short>-h ──┐
    │                                  │ veth pair
    └──────────────────────────────────┘
                                       │
[Container Network Namespace]          │
    │                                  │
    └── eth0 ←─────────────────────────┘
        IP: 10.87.1.x/24
```

### 実装アプローチ

1. **シンプルなブリッジ方式**を採用（Phase 2）
2. 各コンテナは同一ブリッジに接続
3. WSL2 ホストからブリッジ経由でアクセス可能
4. Phase 3 でオーバーレイに拡張可能な設計

---

## Sub-stages

### Sub-stage 3.1: Network Namespace 操作

**内容:**
- `nix` クレートを使用した netns 操作
- コンテナの network namespace に入る
- namespace 間でのファイルディスクリプタ操作

**実装ポイント:**
```rust
use nix::sched::{setns, CloneFlags};
use std::fs::File;
use std::os::unix::io::AsRawFd;

fn enter_netns(netns_path: &str) -> Result<(), Error> {
    let file = File::open(netns_path)?;
    setns(file.as_raw_fd(), CloneFlags::CLONE_NEWNET)?;
    Ok(())
}
```

**完了条件:**
- [ ] 指定した network namespace に入れる
- [ ] 元の namespace に戻れる
- [ ] エラー時に適切にハンドリングできる

---

### Sub-stage 3.2: veth ペア作成

**内容:**
- `rtnetlink` クレートを使用
- veth ペアの作成（host側 + container側）
- container 側 veth を container netns に移動
- インターフェースの UP

**実装ポイント:**
```rust
// veth ペア作成
// - fn-<container-id-8chars>: host namespace に残る
// - eth0: container namespace に移動

use rtnetlink::Handle;
use tokio::runtime::Runtime;

fn create_veth_pair(
    container_id: &str,
    netns_path: &str,
    ifname: &str,
) -> Result<(), Error> {
    // tokio ランタイムを作成（CNI プラグインは同期的に呼び出されるため）
    let rt = Runtime::new()?;
    rt.block_on(async {
        let (connection, handle, _) = rtnetlink::new_connection()?;
        tokio::spawn(connection);

        // 1. veth ペア作成
        // 2. container 側を netns に移動
        // 3. 両方を UP
        create_veth_pair_async(&handle, container_id, netns_path, ifname).await
    })
}

async fn create_veth_pair_async(
    handle: &Handle,
    container_id: &str,
    netns_path: &str,
    ifname: &str,
) -> Result<(), Error> {
    let host_veth = format!("fn-{}", &container_id[..8]);
    // ... 実装
    Ok(())
}
```

**注意:** rtnetlink は非同期 API のため、`tokio::runtime::Runtime` を使って同期的にラップする必要がある。

**完了条件:**
- [ ] veth ペアが作成される
- [ ] container 側 veth が正しい namespace に存在
- [ ] `ip link show` で両方が見える
- [ ] 両インターフェースが UP 状態

---

### Sub-stage 3.3: ブリッジ設定

**内容:**
- `flatnet-br0` ブリッジの作成（存在しなければ）
- host 側 veth をブリッジに接続
- ブリッジに IP を割り当て（ゲートウェイ用）

**設計:**
```
flatnet-br0: 10.87.1.1/24 (gateway)
  ├── fn-abc12345
  ├── fn-def67890
  └── ...
```

**手動でのブリッジ作成（デバッグ用）:**
```bash
# ブリッジ作成
sudo ip link add flatnet-br0 type bridge
sudo ip addr add 10.87.1.1/24 dev flatnet-br0
sudo ip link set flatnet-br0 up

# 確認
ip addr show flatnet-br0
bridge link show
```

**完了条件:**
- [ ] `flatnet-br0` ブリッジが作成される
  ```bash
  ip link show flatnet-br0 && echo "OK"
  ```
- [ ] host 側 veth がブリッジに接続される
  ```bash
  bridge link show | grep flatnet-br0
  ```
- [ ] ブリッジが UP でゲートウェイ IP を持つ
  ```bash
  ip addr show flatnet-br0 | grep "10.87.1.1" && echo "OK"
  ```

---

### Sub-stage 3.4: IP アドレス割り当て（IPAM）

**内容:**
- シンプルなファイルベース IPAM
- 使用中 IP のトラッキング
- 割り当て・解放ロジック
- 重複防止

**IPAM ディレクトリの初期化:**
```bash
# IPAM データディレクトリ作成
sudo mkdir -p /var/lib/flatnet/ipam
sudo chown root:root /var/lib/flatnet/ipam
sudo chmod 700 /var/lib/flatnet/ipam

# 初期データファイル作成
sudo tee /var/lib/flatnet/ipam/allocations.json << 'EOF'
{
  "subnet": "10.87.1.0/24",
  "gateway": "10.87.1.1",
  "range_start": "10.87.1.2",
  "range_end": "10.87.1.254",
  "allocations": {}
}
EOF
sudo chmod 600 /var/lib/flatnet/ipam/allocations.json
```

**IPAM データ構造:**
```
/var/lib/flatnet/ipam/
  ├── .lock                  # ファイルロック用
  └── allocations.json       # 割り当て情報
      {
        "subnet": "10.87.1.0/24",
        "gateway": "10.87.1.1",
        "range_start": "10.87.1.2",
        "range_end": "10.87.1.254",
        "allocations": {
          "container-id-1": "10.87.1.2",
          "container-id-2": "10.87.1.3"
        }
      }
```

**ファイルロック:**
```rust
use std::fs::OpenOptions;
use fs2::FileExt;

fn with_ipam_lock<T>(f: impl FnOnce() -> Result<T, Error>) -> Result<T, Error> {
    let lock_file = OpenOptions::new()
        .create(true)
        .write(true)
        .open("/var/lib/flatnet/ipam/.lock")?;
    lock_file.lock_exclusive()?;
    let result = f();
    lock_file.unlock()?;
    result
}
```

**完了条件:**
- [ ] 新規コンテナに未使用 IP が割り当てられる
- [ ] コンテナ削除時に IP が解放される
- [ ] 同一 IP の重複割り当てが起きない
- [ ] 永続化されリブート後も情報が保持される
- [ ] 同時実行時にファイルロックで競合が防止される

---

### Sub-stage 3.5: コンテナ側ネットワーク設定

**内容:**
- container netns 内で eth0 に IP 割り当て
- デフォルトルートの設定（→ ブリッジゲートウェイ）
- loopback インターフェースの UP

**実装:**
```rust
fn configure_container_network(
    netns_path: &str,
    ifname: &str,
    ip: IpAddr,
    gateway: IpAddr,
) -> Result<(), Error> {
    // 1. netns に入る
    // 2. IP アドレス割り当て
    // 3. デフォルトルート追加
    // 4. lo を UP
}
```

**完了条件:**
- [ ] コンテナ内で `ip addr` に割り当て IP が見える
- [ ] コンテナからゲートウェイに ping できる
- [ ] コンテナから外部に通信できる

---

### Sub-stage 3.6: DEL コマンド実装

**内容:**
- veth ペアの削除
- IPAM からの IP 解放
- ブリッジからの切断
- 残留リソースのクリーンアップ

**完了条件:**
- [ ] コンテナ停止時に veth が削除される
- [ ] IP が解放され再利用可能になる
- [ ] `ip link show` に残骸が残らない

---

## 成果物

1. `src/flatnet-cni/src/netns.rs` - Network Namespace 操作
2. `src/flatnet-cni/src/veth.rs` - veth ペア管理
3. `src/flatnet-cni/src/bridge.rs` - ブリッジ管理
4. `src/flatnet-cni/src/ipam.rs` - IP アドレス管理
5. `src/flatnet-cni/src/commands/add.rs` - ADD 実装
6. `src/flatnet-cni/src/commands/del.rs` - DEL 実装

## 完了条件

| 条件 | 確認方法 |
|------|----------|
| veth ペアが作成される | `ip link show` で fn-* が表示 |
| Flatnet IP が割り当てられる | `podman inspect` で 10.87.1.x |
| ホスト→コンテナ ping | `ping 10.87.1.x` |
| コンテナ→ホスト ping | `podman exec ... ping 10.87.1.1` |
| コンテナ停止でクリーンアップ | `ip link show` で veth が消える |
| 複数コンテナ動作 | 3つ以上のコンテナが同時稼働 |

**一括確認スクリプト:**
```bash
#!/bin/bash
echo "=== Stage 3 完了チェック ==="

# 注意: rootful Podman を使用（CNI プラグインが root 権限を必要とするため）

# コンテナ起動
echo "Starting test container..."
sudo podman run -d --name stage3-test --network flatnet nginx:alpine 2>/dev/null

sleep 2

# IP 取得
IP=$(sudo podman inspect stage3-test 2>/dev/null | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress')
echo "Container IP: $IP"

# veth 確認
ip link show | grep -q "fn-" && echo "[OK] veth pair exists" || echo "[NG] veth not found"

# ブリッジ確認
ip addr show flatnet-br0 2>/dev/null | grep -q "10.87.1.1" && echo "[OK] Bridge has gateway IP" || echo "[NG] Bridge IP missing"

# ping テスト
ping -c 1 -W 2 $IP >/dev/null 2>&1 && echo "[OK] Host -> Container ping" || echo "[NG] Ping failed"

# コンテナからホストへ ping
sudo podman exec stage3-test ping -c 1 -W 2 10.87.1.1 >/dev/null 2>&1 && echo "[OK] Container -> Host ping" || echo "[NG] Reverse ping failed"

# クリーンアップ
echo "Cleaning up..."
sudo podman rm -f stage3-test >/dev/null 2>&1

# veth 削除確認
sleep 1
ip link show | grep -q "fn-" && echo "[NG] veth still exists" || echo "[OK] veth cleaned up"

echo "=== Done ==="
```

## テスト方法

### 手動統合テスト

```bash
# 注意: rootful Podman を使用
# コンテナ起動
sudo podman run -d --name test1 --network flatnet nginx:alpine

# IP 確認
sudo podman inspect test1 | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress'
# 期待出力: 10.87.1.2

# veth 確認
ip link show | grep fn-
# 期待出力: fn-xxxxxxxx@... のようなインターフェース

# ブリッジ確認
bridge link show
# 期待出力: fn-xxxxxxxx ... master flatnet-br0

# ホストから疎通確認
ping -c 3 10.87.1.2

# コンテナ内から確認
sudo podman exec test1 ip addr
sudo podman exec test1 ping -c 3 10.87.1.1

# クリーンアップ確認
sudo podman rm -f test1
ip link show | grep fn-
# 期待出力: 何も表示されない（veth が削除されている）
```

### 複数コンテナテスト

```bash
# 3つのコンテナを起動
sudo podman run -d --name multi1 --network flatnet nginx:alpine
sudo podman run -d --name multi2 --network flatnet nginx:alpine
sudo podman run -d --name multi3 --network flatnet nginx:alpine

# IP を確認（すべて異なる IP が割り当てられていること）
for c in multi1 multi2 multi3; do
  echo -n "$c: "
  sudo podman inspect $c | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress'
done
# 期待出力:
# multi1: 10.87.1.2
# multi2: 10.87.1.3
# multi3: 10.87.1.4

# コンテナ間通信テスト
sudo podman exec multi1 ping -c 1 10.87.1.3
sudo podman exec multi2 ping -c 1 10.87.1.4

# クリーンアップ
sudo podman rm -f multi1 multi2 multi3
```

## 注意事項

- root 権限が必要（netns 操作、ブリッジ作成）
- WSL2 の仮想ネットワークとの干渉に注意
- ファイアウォール設定（iptables）は次の Stage で対応
- IPAM データディレクトリ `/var/lib/flatnet/ipam/` は root 所有

## トラブルシューティング

### veth ペアが作成されない

**症状:** コンテナ起動時に veth が見えない

**対処:**
```bash
# プラグインのエラーを確認
podman run --rm --network flatnet alpine echo test 2>&1

# netns が正しく渡されているか確認
# main.rs でデバッグ出力を追加して CNI_NETNS を確認

# 権限確認（rootful Podman が必要な場合あり）
sudo podman run --rm --network flatnet alpine echo test
```

### ブリッジに IP がない

**症状:** `flatnet-br0` が作成されるが IP がない

**対処:**
```bash
# 手動で IP を割り当て（デバッグ用）
sudo ip addr add 10.87.1.1/24 dev flatnet-br0
sudo ip link set flatnet-br0 up

# プラグインのブリッジ作成ロジックを確認
```

### ping が通らない

**症状:** veth と IP は設定されているが ping が失敗

**対処:**
```bash
# IP フォワーディング確認
cat /proc/sys/net/ipv4/ip_forward
# 0 の場合は有効化
sudo sysctl -w net.ipv4.ip_forward=1

# iptables 確認（FORWARD チェーンがブロックしている可能性）
sudo iptables -L FORWARD -n
# DROP がデフォルトの場合は許可ルールを追加
sudo iptables -A FORWARD -i flatnet-br0 -j ACCEPT
sudo iptables -A FORWARD -o flatnet-br0 -j ACCEPT

# ルーティングテーブル確認
ip route
# 10.87.1.0/24 へのルートがあることを確認
```

### IPAM で IP が枯渇

**症状:** 新しいコンテナに IP が割り当てられない

**対処:**
```bash
# IPAM データ確認
cat /var/lib/flatnet/ipam/allocations.json

# 孤立した割り当てを削除（停止済みコンテナの IP）
# 実行中コンテナの確認
podman ps -q

# allocations.json を手動で編集して解放
sudo vi /var/lib/flatnet/ipam/allocations.json
```

### コンテナ削除後も veth が残る

**症状:** `podman rm` 後も `fn-*` インターフェースが残る

**対処:**
```bash
# 手動削除
sudo ip link delete fn-xxxxxxxx

# すべての残留 veth を削除
for iface in $(ip link show | grep "fn-" | cut -d: -f2 | tr -d ' '); do
  sudo ip link delete $iface 2>/dev/null
done
```

### ファイルロックでデッドロック

**症状:** IPAM 操作がハングする

**対処:**
```bash
# ロックファイル確認
ls -la /var/lib/flatnet/ipam/.lock

# ロックを強制解除（注意: 他のプロセスが使用中でないことを確認）
sudo rm /var/lib/flatnet/ipam/.lock
```

## veth インターフェース命名規則

Linux のインターフェース名は15文字制限があるため:

```
ホスト側:  fn-<container-id-8chars>  例: fn-a1b2c3d4
コンテナ側: eth0（CNI_IFNAME で指定される）
```

## CHECK コマンドの実装方針

Stage 3 では CHECK コマンドも実装する:

```rust
fn check(config: &NetworkConfig, env: &CniEnv) -> Result<(), CniError> {
    // 1. veth ペアが存在するか確認
    // 2. IP アドレスが割り当てられているか確認
    // 3. ブリッジに接続されているか確認
    // 問題があれば CniError を返す
}
```

## 次の Stage への引き継ぎ事項

- ネットワーク設定のモジュール構成（netns, veth, bridge, ipam）
- ブリッジ名・サブネット等の設定値
- IPAM データファイルの場所とフォーマット
