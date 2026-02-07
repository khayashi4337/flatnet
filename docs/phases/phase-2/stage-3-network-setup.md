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
// - flatnet-<short-id>-h: host namespace に残る
// - eth0: container namespace に移動

async fn create_veth_pair(
    container_id: &str,
    netns_path: &str,
    ifname: &str,
) -> Result<(), Error> {
    // 1. veth ペア作成
    // 2. container 側を netns に移動
    // 3. 両方を UP
}
```

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
  ├── veth-abc123-h
  ├── veth-def456-h
  └── ...
```

**完了条件:**
- [ ] `flatnet-br0` ブリッジが作成される
- [ ] host 側 veth がブリッジに接続される
- [ ] ブリッジが UP でゲートウェイ IP を持つ

---

### Sub-stage 3.4: IP アドレス割り当て（IPAM）

**内容:**
- シンプルなファイルベース IPAM
- 使用中 IP のトラッキング
- 割り当て・解放ロジック
- 重複防止

**IPAM データ構造:**
```
/var/lib/flatnet/ipam/
  └── allocations.json
      {
        "subnet": "10.87.1.0/24",
        "gateway": "10.87.1.1",
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

- [ ] コンテナ起動時に veth ペアが作成される
- [ ] コンテナに Flatnet IP（10.87.1.x）が割り当てられる
- [ ] ホストからコンテナに ping できる
- [ ] コンテナからホストに ping できる
- [ ] コンテナ停止時にリソースがクリーンアップされる
- [ ] 複数コンテナが同時に動作できる

## テスト方法

### 手動統合テスト

```bash
# コンテナ起動
podman run -d --name test1 --network flatnet nginx

# IP 確認
podman inspect test1 | jq '.[0].NetworkSettings.Networks.flatnet.IPAddress'

# ホストから疎通確認
ping -c 3 10.87.1.2

# コンテナ内から確認
podman exec test1 ip addr
podman exec test1 ping -c 3 10.87.1.1

# クリーンアップ確認
podman rm -f test1
ip link show  # veth が消えていることを確認
```

## 注意事項

- root 権限が必要（netns 操作、ブリッジ作成）
- WSL2 の仮想ネットワークとの干渉に注意
- ファイアウォール設定（iptables）は次の Stage で対応

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
