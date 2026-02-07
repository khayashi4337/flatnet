# Phase 1: CNI Plugin 実装

## ゴール
Rust製 CNI プラグインの全コンポーネントを実装し、コンテナ間でトンネル通信ができる状態を作る。

## 対象コンポーネント（component.puml より）

```
package "Flatnet CNI Plugin (Rust)" {
  FlatnetCNI
  NetworkNamespace
  TunnelManager
  IPAddressManager
  LighthouseClient (モック実装)
}
```

## Phase 1 完了条件
- [ ] Podman で起動した2つのコンテナが Flatnet トンネル経由で相互に通信できる
- [ ] コンテナの起動・停止時に CNI プラグインが正しく動作し、リソースがリークしない
- [ ] Forgejo + Runner が Flatnet 上で動作し、CI ジョブが実行できる

---

## Stages

### Stage 1: FlatnetCNI スケルトン

**対象クラス:** `FlatnetCNI`

**実装内容**
- `add(container_id, netns)` → CNIResult
- `del(container_id, netns)` → CNIResult
- `check(container_id, netns)` → CNIResult
- `read_config(stdin)` → FlatnetConfig
- `write_result(stdout)`

**完了条件**
- [ ] `cargo build --release` でビルド成功
- [ ] CNI_COMMAND=ADD → 有効な CNI Result JSON を stdout に出力
- [ ] CNI_COMMAND=DEL → exit 0
- [ ] CNI_COMMAND=CHECK → exit 0
- [ ] `podman run --network flatnet alpine echo hello` が成功

---

### Stage 2: NetworkNamespace 操作

**対象クラス:** `NetworkNamespace`

**実装内容**
- `create_interface(netns_path)` → TunDevice
- `assign_ip(device, ip)`
- `setup_routes(device, routes)`
- `teardown(netns_path)`

**完了条件**
- [ ] コンテナ内にネットワークインターフェースが作成される
- [ ] 指定したサブネットから IP が割り当てられる
- [ ] コンテナ内から `ip addr` で割り当てられた IP を確認できる
- [ ] コンテナ停止時にインターフェースが正しくクリーンアップされる

---

### Stage 3: IPAddressManager 実装

**対象クラス:** `IPAddressManager`, `LighthouseClient`（モック）

**実装内容**
- `allocate_ip(container_id)` → FlatnetIP
- `release_ip(container_id)`
- `resolve_ip(container_id)` → FlatnetIP
- `register_with_lighthouse(ip)` → モック実装（ローカルファイル or メモリ）

**完了条件**
- [ ] コンテナ起動時に一意の Flatnet IP が割り当てられる
- [ ] 複数コンテナで IP が重複しない
- [ ] コンテナ停止時に IP が解放される
- [ ] container_id から Flatnet IP を解決できる

---

### Stage 4: TunnelManager 実装

**対象クラス:** `TunnelManager`

**実装内容**
- `create_tunnel(local_ip, remote_ip)` → Tunnel
- `encrypt_packet(packet)` → EncryptedPacket
- `decrypt_packet(packet)` → Packet
- `close_tunnel()`

**完了条件**
- [ ] コンテナ間でトンネルが確立される
- [ ] パケットが暗号化されて送受信される
- [ ] 2つのコンテナ間で ping が通る
- [ ] TCP 通信ができる（nc でメッセージ送受信）

---

### Stage 5: Forgejo 統合テスト

**検証内容**
- Forgejo + Runner を Flatnet CNI 上で起動
- git push → CI 実行の一連のフローを検証

**完了条件**
- [ ] Forgejo が Flatnet 上で起動する
- [ ] Forgejo Runner が Forgejo に接続し、オンライン状態になる
- [ ] テストリポジトリに push すると、Forgejo Actions ワークフローが実行される
- [ ] ワークフロー内で `echo "Hello from Flatnet"` が成功する
- [ ] 動作検証手順書が作成されている

---

## 成果物
- `flatnet-cni` バイナリ（Rust）
- Podman用ネットワーク設定ファイル
- Phase 1 動作検証手順書
