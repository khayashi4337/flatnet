# Flatnet CNI Operations Guide

このドキュメントでは、Flatnet CNI プラグインの日常運用手順を説明します。

## 目次

1. [基本操作](#基本操作)
2. [コンテナ管理](#コンテナ管理)
3. [IP アドレス管理](#ip-アドレス管理)
4. [ネットワーク管理](#ネットワーク管理)
5. [メンテナンス](#メンテナンス)
6. [監視](#監視)

---

## 基本操作

### Flatnet ネットワークでコンテナを起動

```bash
# 基本的な起動
sudo podman run -d --name myapp --network flatnet myimage:latest

# IP 確認
sudo podman inspect myapp | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress'
```

### コンテナの停止・開始

```bash
# 停止
sudo podman stop myapp

# 開始（IP は再割り当てされる可能性あり）
sudo podman start myapp

# 再起動
sudo podman restart myapp
```

### コンテナの削除

```bash
# 削除（IP は自動的に解放される）
sudo podman rm -f myapp
```

---

## コンテナ管理

### Flatnet コンテナの一覧表示

```bash
# 実行中のコンテナ
sudo podman ps --filter "network=flatnet" --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}"

# 全コンテナ（停止中含む）
sudo podman ps -a --filter "network=flatnet"
```

### コンテナの IP アドレス一覧

```bash
# 全 Flatnet コンテナの IP を表示
for name in $(sudo podman ps --filter "network=flatnet" --format "{{.Names}}"); do
  ip=$(sudo podman inspect "$name" | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress')
  echo "$name: $ip"
done
```

### コンテナへの接続テスト

```bash
# Ping テスト
ping -c 3 10.87.1.X

# HTTP テスト
curl -v http://10.87.1.X/

# コンテナ内からテスト
sudo podman exec myapp wget -O - http://10.87.1.Y/
```

---

## IP アドレス管理

### IP 割り当て状態の確認

```bash
# 現在の割り当て一覧
cat /var/lib/flatnet/ipam/allocations.json | jq .

# 割り当て数
jq '.allocations | length' /var/lib/flatnet/ipam/allocations.json

# 使用可能な IP 数（理論値）
# サブネット 10.87.1.0/24 = 254 個（.1 はブリッジ、.255 はブロードキャスト）
echo "Available: $((253 - $(jq '.allocations | length' /var/lib/flatnet/ipam/allocations.json)))"
```

### 特定のコンテナの IP 確認

```bash
# コンテナ名から IP を取得
sudo podman inspect myapp | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress'

# コンテナ ID から IP を取得
sudo podman inspect abc123 | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress'
```

### IP アドレスの手動解放（緊急時のみ）

孤児になった IP エントリを手動で削除する場合:

```bash
# 1. 現在の状態をバックアップ
sudo cp /var/lib/flatnet/ipam/allocations.json /var/lib/flatnet/ipam/allocations.json.bak

# 2. 実行中のコンテナ ID を確認
sudo podman ps -q

# 3. allocations.json を編集して不要なエントリを削除
sudo vim /var/lib/flatnet/ipam/allocations.json

# 4. 問題があればリストア
sudo cp /var/lib/flatnet/ipam/allocations.json.bak /var/lib/flatnet/ipam/allocations.json
```

---

## ネットワーク管理

### ブリッジの状態確認

```bash
# ブリッジ情報
ip addr show flatnet-br0

# 接続されているインターフェース
bridge link show flatnet-br0

# veth ペアの一覧
ip link show type veth
```

### IP フォワーディングの確認

```bash
# 現在の設定
sysctl net.ipv4.ip_forward

# 有効化（一時的）
sudo sysctl -w net.ipv4.ip_forward=1

# 永続化
sudo ./scripts/wsl2/setup-forwarding.sh --persist
```

### iptables ルールの確認

```bash
# FORWARD チェーン
sudo iptables -L FORWARD -n -v

# flatnet 関連のルール
sudo iptables -L FORWARD -n | grep -E "(flatnet|10\.87\.1)"

# NAT テーブル（外部接続用）
sudo iptables -t nat -L -n -v
```

---

## メンテナンス

### WSL2 再起動後の復旧

WSL2 を再起動した場合、以下の設定を再適用する必要があります:

**WSL2 側:**
```bash
# IP フォワーディングと iptables
sudo ./scripts/wsl2/setup-forwarding.sh
```

**Windows 側（管理者 PowerShell）:**
```powershell
# ルーティング設定
F:\flatnet\scripts\setup-route.ps1
```

### CNI プラグインの更新

```bash
# 1. 既存コンテナをバックアップ（設定をメモ）
sudo podman ps --filter "network=flatnet" --format "{{.Names}}"

# 2. 新しいバイナリをビルド
cd /home/kh/prj/flatnet/src/flatnet-cni
cargo build --release

# 3. バイナリを更新（コンテナ停止は不要）
sudo cp target/release/flatnet /opt/cni/bin/flatnet

# 4. 新しいコンテナで動作確認
sudo podman run --rm --network flatnet alpine ping -c 1 10.87.1.1
```

### IPAM データのリセット

全コンテナを停止してから実行:

```bash
# 1. 全 Flatnet コンテナを停止・削除
sudo podman rm -f $(sudo podman ps -aq --filter "network=flatnet")

# 2. IPAM データを削除
sudo rm -f /var/lib/flatnet/ipam/allocations.json

# 3. ブリッジを再作成（オプション）
sudo ip link delete flatnet-br0 2>/dev/null || true
```

### OpenResty 設定の更新

```bash
# 1. WSL2 で設定を編集
vim /home/kh/prj/flatnet/config/openresty/conf.d/flatnet.conf

# 2. Windows にデプロイ
./scripts/deploy-config.sh
```

Windows 側:
```powershell
# 3. 設定テスト
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t

# 4. リロード
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -s reload
```

---

## 監視

### ヘルスチェック

```bash
# ブリッジの疎通確認
ping -c 1 10.87.1.1

# コンテナへの HTTP 確認
curl -s -o /dev/null -w "%{http_code}" http://10.87.1.2/

# 統合テスト
sudo ./scripts/test-integration.sh --quick
```

### ログ確認

```bash
# CNI 関連のログ（syslog）
sudo grep -i cni /var/log/syslog | tail -20

# Podman のログ
journalctl -u podman --since "1 hour ago"
```

Windows 側:
```powershell
# OpenResty エラーログ
Get-Content F:\flatnet\logs\error.log -Tail 50

# OpenResty アクセスログ
Get-Content F:\flatnet\logs\access.log -Tail 50
```

### リソース使用量

```bash
# Flatnet コンテナのリソース使用量
sudo podman stats --no-stream --filter "network=flatnet"

# ブリッジのトラフィック統計
ip -s link show flatnet-br0
```

---

## クイックリファレンス

### よく使うコマンド

| 操作 | コマンド |
|------|----------|
| コンテナ起動 | `sudo podman run -d --network flatnet --name X image` |
| IP 確認 | `sudo podman inspect X \| jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress'` |
| 一覧表示 | `sudo podman ps --filter "network=flatnet"` |
| テスト実行 | `sudo ./scripts/test-integration.sh` |
| フォワーディング有効化 | `sudo ./scripts/wsl2/setup-forwarding.sh` |
| Windows ルート設定 | `F:\flatnet\scripts\setup-route.ps1` |

### トラブルシューティング

問題が発生した場合は [Troubleshooting Guide](troubleshooting.md) を参照してください。

---

## 関連ドキュメント

- [Phase 2 Setup Guide](../setup/phase-2-setup.md)
- [Troubleshooting Guide](troubleshooting.md)
- [Phase 2 Stage 4 Design](../phases/phase-2/stage-4-integration.md)
