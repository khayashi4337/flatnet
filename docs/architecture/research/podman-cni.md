# Podman CNI 連携調査

## 概要

Podman v4 以降はデフォルトで netavark をネットワークバックエンドとして使用する。
Flatnet CNI プラグインを使用するには、CNI バックエンドを明示的に有効化する必要がある。

## ネットワークバックエンド

### netavark vs CNI

| 項目 | netavark | CNI |
|------|----------|-----|
| デフォルト | Podman v4+ | Podman v3以前 |
| 実装言語 | Rust | シェル/Go（プラグインによる） |
| 設定形式 | JSON (podman独自) | JSON (CNI標準) |
| プラグイン機構 | なし（モノリシック） | あり（チェーン可能） |
| 利点 | 高速、Podman統合 | 標準規格、拡張性 |

### バックエンド確認

```bash
# 現在のバックエンド確認
podman info --format '{{.Host.NetworkBackend}}'
# 期待出力: netavark または cni

# rootful Podman の場合
sudo podman info --format '{{.Host.NetworkBackend}}'
```

## CNI バックエンドへの切り替え

### rootful Podman（推奨）

Flatnet は veth やブリッジ操作に root 権限が必要なため、rootful Podman を推奨。

```bash
# 設定ファイル作成
sudo mkdir -p /etc/containers
sudo tee /etc/containers/containers.conf << 'EOF'
[network]
network_backend = "cni"
EOF

# 既存の Podman データをリセット（注意: コンテナ・イメージ削除）
sudo podman system reset --force

# 確認
sudo podman info --format '{{.Host.NetworkBackend}}'
# 期待出力: cni
```

### rootless Podman

```bash
# ユーザー設定ファイル作成
mkdir -p ~/.config/containers
tee ~/.config/containers/containers.conf << 'EOF'
[network]
network_backend = "cni"
EOF

# リセット
podman system reset --force

# 確認
podman info --format '{{.Host.NetworkBackend}}'
```

## ファイル配置場所

### CNI 設定ファイル

```
rootful:
  /etc/cni/net.d/              # 設定ファイル（*.conflist, *.conf）

rootless:
  ~/.config/cni/net.d/         # ユーザー設定
  /etc/cni/net.d/              # システム設定（フォールバック）
```

**設定ファイル例: `/etc/cni/net.d/87-flatnet.conflist`**

```json
{
  "cniVersion": "1.0.0",
  "name": "flatnet",
  "plugins": [
    {
      "type": "flatnet",
      "bridge": "flatnet0",
      "ipam": {
        "type": "host-local",
        "subnet": "10.42.0.0/16",
        "gateway": "10.42.0.1"
      }
    }
  ]
}
```

**ファイル名規則:**
- 数字プレフィックス（例: `87-`）でソート順を制御
- Podman のデフォルトは `87-podman.conflist`

### CNI プラグインバイナリ

```
/opt/cni/bin/                  # 標準パス
/usr/lib/cni/                  # ディストリビューションによる
/usr/libexec/cni/              # RHEL/CentOS 系
```

**パス確認:**
```bash
podman info --format '{{.Host.CniPath}}'
# 出力例: [/usr/lib/cni /opt/cni/bin]
```

**インストール先:**
```bash
# Flatnet プラグインの配置
sudo cp flatnet /opt/cni/bin/
sudo chmod 755 /opt/cni/bin/flatnet
```

## Podman ネットワーク操作

### ネットワーク一覧

```bash
podman network ls
# NAME        DRIVER
# podman      bridge
```

### ネットワーク詳細

```bash
podman network inspect podman
```

**CNI バックエンド時の出力例:**
```json
[
  {
    "name": "podman",
    "id": "2f259bab93aaaa...",
    "driver": "bridge",
    "network_interface": "cni-podman0",
    "created": "2024-01-01T00:00:00Z",
    "subnets": [
      {
        "subnet": "10.88.0.0/16",
        "gateway": "10.88.0.1"
      }
    ],
    "ipv6_enabled": false,
    "internal": false,
    "dns_enabled": true
  }
]
```

### カスタムネットワーク作成

```bash
# CNI バックエンドでカスタムネットワーク作成
podman network create \
  --driver bridge \
  --subnet 10.42.0.0/16 \
  --gateway 10.42.0.1 \
  flatnet-test

# 確認
podman network inspect flatnet-test

# 削除
podman network rm flatnet-test
```

## CNI プラグイン呼び出しフロー

### コンテナ起動時（podman run）

```
1. podman run --network=flatnet myimage
       |
2. Podman が /etc/cni/net.d/ から flatnet.conflist を読み込み
       |
3. Network namespace 作成
       |
4. CNI プラグイン実行:
   CNI_COMMAND=ADD
   CNI_CONTAINERID=xxx
   CNI_NETNS=/var/run/netns/cni-xxx
   CNI_IFNAME=eth0
   stdin: { "cniVersion": "1.0.0", "name": "flatnet", ... }
       |
5. プラグインが veth 作成、IP 割り当て
       |
6. Result を stdout に出力
       |
7. Podman がコンテナ起動
```

### コンテナ停止時（podman stop/rm）

```
1. podman rm mycontainer
       |
2. CNI プラグイン実行:
   CNI_COMMAND=DEL
   CNI_CONTAINERID=xxx
   CNI_NETNS=/var/run/netns/cni-xxx
   CNI_IFNAME=eth0
   stdin: { "cniVersion": "1.0.0", "name": "flatnet", "prevResult": {...} }
       |
3. プラグインが veth 削除、IP 解放
       |
4. Network namespace 削除
```

## デバッグ方法

### CNI ログ確認

```bash
# Podman のデバッグログ
podman --log-level debug run --rm --network=flatnet alpine ip addr
```

### 手動でプラグイン実行

```bash
# 環境変数設定
export CNI_COMMAND=VERSION
export CNI_PATH=/opt/cni/bin

# プラグイン実行
echo '{"cniVersion":"1.0.0"}' | /opt/cni/bin/flatnet

# ADD 操作のテスト（要 root、要 netns）
sudo ip netns add test-ns
export CNI_COMMAND=ADD
export CNI_CONTAINERID=test-container
export CNI_NETNS=/var/run/netns/test-ns
export CNI_IFNAME=eth0
echo '{"cniVersion":"1.0.0","name":"test","type":"flatnet"}' | sudo /opt/cni/bin/flatnet
sudo ip netns del test-ns
```

### ネットワーク状態確認

```bash
# ブリッジ一覧
ip link show type bridge

# veth ペア一覧
ip link show type veth

# コンテナの network namespace 確認
sudo ls -la /var/run/netns/

# 特定 namespace 内のインターフェース
sudo ip netns exec <ns-name> ip addr
```

## 既存 CNI プラグイン

Podman/CNI で利用可能な標準プラグイン:

| プラグイン | 機能 |
|-----------|------|
| `bridge` | Linux ブリッジを作成・接続 |
| `loopback` | loopback インターフェース設定 |
| `host-local` | IPAM（ローカルファイルで IP 管理） |
| `portmap` | ポートマッピング（DNAT） |
| `firewall` | iptables ルール管理 |
| `tuning` | sysctl 設定 |

**プラグインチェーン例:**
```json
{
  "cniVersion": "1.0.0",
  "name": "mynet",
  "plugins": [
    {"type": "bridge", "bridge": "mybridge"},
    {"type": "portmap", "capabilities": {"portMappings": true}}
  ]
}
```

## Flatnet 統合計画

### 配置

```
/opt/cni/bin/flatnet           # CNI プラグイン本体
/etc/cni/net.d/90-flatnet.conflist  # 設定ファイル
```

### 設定ファイル

```json
{
  "cniVersion": "1.0.0",
  "name": "flatnet",
  "plugins": [
    {
      "type": "flatnet",
      "bridge": "flatnet0",
      "mtu": 1500,
      "ipam": {
        "type": "host-local",
        "subnet": "10.42.0.0/16",
        "gateway": "10.42.0.1",
        "routes": [
          {"dst": "0.0.0.0/0"}
        ]
      }
    }
  ]
}
```

### 使用方法

```bash
# Flatnet ネットワークでコンテナ起動
sudo podman run --network=flatnet --name myapp myimage

# コンテナの IP 確認
sudo podman inspect myapp --format '{{.NetworkSettings.Networks.flatnet.IPAddress}}'
```

## トラブルシューティング

### CNI バックエンドに切り替わらない

```bash
# 設定ファイルの確認
cat /etc/containers/containers.conf

# Podman のキャッシュクリア
sudo podman system reset --force
```

### プラグインが見つからない

```bash
# パス確認
podman info --format '{{.Host.CniPath}}'

# プラグイン存在確認
ls -la /opt/cni/bin/

# パーミッション確認（実行可能か）
file /opt/cni/bin/flatnet
```

### ネットワーク作成エラー

```bash
# ログ確認
sudo journalctl -u podman --since "5 minutes ago"

# 手動で設定ファイル検証
cat /etc/cni/net.d/*.conflist | jq .
```

## 参考リンク

- [Podman Networking](https://docs.podman.io/en/latest/markdown/podman-network.1.html)
- [Podman CNI vs Netavark](https://www.redhat.com/sysadmin/podman-new-network-stack)
- [CNI Plugins](https://github.com/containernetworking/plugins)
- [containers.conf](https://github.com/containers/common/blob/main/docs/containers.conf.5.md)
