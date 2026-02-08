# Phase 2 Setup Guide

Phase 2 では、Flatnet CNI プラグインを使用して Podman コンテナにフラットなネットワークアドレスを割り当て、Gateway 経由で社内 LAN からアクセスできるようにします。

## 前提条件

- Phase 1 完了（OpenResty Gateway が動作している）
- Windows 11 + WSL2 (Ubuntu 24.04)
- Podman v4 系がインストール済み
- 管理者権限（Windows）と root 権限（WSL2）

## セットアップ手順

### Step 1: CNI プラグインのビルドとインストール

WSL2 側で実行:

```bash
# リポジトリのディレクトリに移動
cd /home/kh/prj/flatnet

# CNI プラグインをビルド
cd src/flatnet-cni
cargo build --release

# CNI バイナリをインストール
sudo cp target/release/flatnet /opt/cni/bin/
sudo chmod +x /opt/cni/bin/flatnet

# インストール確認
ls -la /opt/cni/bin/flatnet
```

### Step 2: Flatnet ネットワークの作成

WSL2 側で実行:

```bash
# Podman ネットワーク設定ファイルを作成
sudo mkdir -p /etc/cni/net.d

# Flatnet ネットワーク設定
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

# Podman でネットワークを確認
sudo podman network ls
```

### Step 3: WSL2 IP フォワーディングの設定

WSL2 側で実行:

```bash
# フォワーディング設定スクリプトを実行
sudo ./scripts/wsl2/setup-forwarding.sh --persist

# 状態確認
sudo ./scripts/wsl2/setup-forwarding.sh --status
```

期待される出力:
```
[OK] IP forwarding: enabled
[OK] Bridge flatnet-br0: exists (IP: 10.87.1.1)
```

### Step 4: Windows ルーティングの設定

まず WSL2 側でスクリプトを Windows にデプロイ:

```bash
# scripts ディレクトリを作成（初回のみ）
mkdir -p /mnt/f/flatnet/scripts

# スクリプトをコピー
cp /home/kh/prj/flatnet/scripts/windows/setup-route.ps1 /mnt/f/flatnet/scripts/
```

Windows 側で PowerShell を管理者として実行:

```powershell
# WSL2 が起動していることを確認
wsl hostname -I

# ルーティング設定スクリプトを実行
F:\flatnet\scripts\setup-route.ps1 -Verify
```

期待される出力:
```
[INFO] WSL2 IP: 172.x.x.x
[OK] Route added successfully
[OK] Ping to bridge (10.87.1.1) successful
```

### Step 5: OpenResty 設定の更新

WSL2 側で設定をデプロイ:

```bash
# 設定ファイルをコピー
./scripts/deploy-config.sh

# または手動でコピー
cp -r config/openresty/* /mnt/f/flatnet/config/
```

Windows 側で OpenResty をリロード:

```powershell
# 設定テスト
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t

# リロード
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -s reload
```

### Step 6: 動作確認

#### 6.1 コンテナの起動

WSL2 側で実行:

```bash
# テストコンテナを起動
sudo podman run -d --name test-web --network flatnet nginx:alpine

# IP アドレスを確認
sudo podman inspect test-web | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress'
# 期待出力: 10.87.1.2
```

#### 6.2 WSL2 からの疎通確認

```bash
# Ping
ping -c 3 10.87.1.2

# HTTP
curl http://10.87.1.2/
```

#### 6.3 Windows からの疎通確認

PowerShell で実行:

```powershell
# Ping
ping 10.87.1.2

# HTTP
Invoke-WebRequest -Uri http://10.87.1.2/ -UseBasicParsing
```

#### 6.4 統合テストの実行

WSL2 側で実行:

```bash
sudo ./scripts/test-integration.sh
```

### Step 7: Forgejo の Flatnet 移行（オプション）

Forgejo を Flatnet ネットワークで起動:

```bash
# 既存のコンテナを停止
sudo podman stop forgejo

# Flatnet で起動
sudo podman run -d \
  --name forgejo-flatnet \
  --network flatnet \
  -v forgejo-data:/var/lib/gitea \
  -e USER_UID=1000 \
  -e USER_GID=1000 \
  codeberg.org/forgejo/forgejo:latest

# IP 確認
FORGEJO_IP=$(sudo podman inspect forgejo-flatnet | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress')
echo "Forgejo IP: $FORGEJO_IP"
```

OpenResty の upstream を更新:

```bash
# config/openresty/conf.d/flatnet.conf の upstream を編集
# server 10.87.1.2:3000; を実際の IP に更新
```

## 設定ファイル一覧

| ファイル | 説明 |
|----------|------|
| `/opt/cni/bin/flatnet` | CNI プラグインバイナリ |
| `/etc/cni/net.d/flatnet.conflist` | CNI 設定 |
| `/etc/sysctl.d/99-flatnet.conf` | IP フォワーディング設定 |
| `/var/lib/flatnet/ipam/allocations.json` | IP 割り当て状態 |
| `F:\flatnet\config\conf.d\flatnet.conf` | OpenResty プロキシ設定 |
| `F:\flatnet\scripts\setup-route.ps1` | Windows ルーティングスクリプト（デプロイ元: `scripts/windows/setup-route.ps1`）|

## トラブルシューティング

問題が発生した場合は [Troubleshooting Guide](../operations/troubleshooting.md) を参照してください。

## 次のステップ

- [CNI Operations Guide](../operations/cni-operations.md) - 日常運用手順
- Phase 3 - マルチホスト対応

## 関連ドキュメント

- [Phase 1 Setup Guide](../guides/phase1-setup-guide.md)
- [Phase 2 Stage 4 Design](../phases/phase-2/stage-4-integration.md)
