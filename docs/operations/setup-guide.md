# Flatnet Setup Guide

このドキュメントでは、Flatnet 環境の完全なセットアップ手順を説明します。

## 目次

1. [前提条件](#前提条件)
2. [Lighthouse セットアップ](#lighthouse-セットアップ)
3. [ホストセットアップ](#ホストセットアップ)
4. [CNI Plugin インストール](#cni-plugin-インストール)
5. [Gateway (OpenResty) セットアップ](#gateway-openresty-セットアップ)
6. [動作確認](#動作確認)

---

## 前提条件

### ハードウェア要件

| コンポーネント | 最小要件 | 推奨 |
|----------------|----------|------|
| Lighthouse | 1 CPU, 512MB RAM | 2 CPU, 1GB RAM |
| Host | 2 CPU, 4GB RAM | 4 CPU, 8GB RAM |
| Storage | 10GB | 50GB |

### ソフトウェア要件

**Windows (Host/Lighthouse):**
- Windows 10/11 Pro または Enterprise
- WSL2 (Ubuntu 22.04/24.04 推奨)
- 管理者権限

**WSL2:**
- Podman v4.x 以上
- curl, jq, ip (iproute2)

### ネットワーク要件

| ポート | プロトコル | 用途 |
|--------|------------|------|
| 4242 | UDP | Nebula トンネル |
| 80 | TCP | HTTP Gateway |
| 8080 | TCP | Flatnet API |

---

## Lighthouse セットアップ

Lighthouse は Nebula ネットワークの中央ノードです。ホスト間の接続を仲介します。

### Step 1: ディレクトリ構成の作成

```powershell
# 管理者 PowerShell で実行
New-Item -ItemType Directory -Path F:\flatnet\nebula -Force
New-Item -ItemType Directory -Path F:\flatnet\config\nebula -Force
New-Item -ItemType Directory -Path F:\flatnet\logs -Force
New-Item -ItemType Directory -Path F:\flatnet\scripts -Force
```

### Step 2: Nebula のダウンロード

1. [Nebula Releases](https://github.com/slackhq/nebula/releases) から最新版をダウンロード
2. `nebula-windows-amd64.zip` を展開
3. 以下に配置:
   - `F:\flatnet\nebula\nebula.exe`
   - `F:\flatnet\nebula\nebula-cert.exe`

### Step 3: CA 証明書の生成

```powershell
cd F:\flatnet\nebula

# CA 証明書の生成 (有効期限: 1年)
.\nebula-cert.exe ca -name "flatnet-ca" -duration 8760h

# 生成されるファイル:
#   ca.crt - CA 公開鍵 (全ホストに配布)
#   ca.key - CA 秘密鍵 (Lighthouse のみ保持、厳重に管理)

# config ディレクトリにコピー
Copy-Item ca.crt F:\flatnet\config\nebula\
Copy-Item ca.key F:\flatnet\config\nebula\
```

### Step 4: Lighthouse 証明書の生成

```powershell
cd F:\flatnet\nebula

# Lighthouse 用の証明書を生成
.\nebula-cert.exe sign `
    -name "lighthouse" `
    -ip "10.100.0.1/16" `
    -groups "lighthouse,flatnet" `
    -ca-crt F:\flatnet\config\nebula\ca.crt `
    -ca-key F:\flatnet\config\nebula\ca.key

# 生成されるファイル:
#   lighthouse.crt
#   lighthouse.key

Copy-Item lighthouse.crt F:\flatnet\config\nebula\host.crt
Copy-Item lighthouse.key F:\flatnet\config\nebula\host.key
```

### Step 5: Lighthouse 設定ファイルの作成

`F:\flatnet\config\nebula\config.yaml` を作成:

```yaml
pki:
  ca: F:\flatnet\config\nebula\ca.crt
  cert: F:\flatnet\config\nebula\host.crt
  key: F:\flatnet\config\nebula\host.key

static_host_map: {}

lighthouse:
  am_lighthouse: true
  interval: 60

listen:
  host: 0.0.0.0
  port: 4242

punchy:
  punch: true

tun:
  disabled: false
  dev: nebula1

firewall:
  outbound:
    - port: any
      proto: any
      host: any

  inbound:
    - port: any
      proto: icmp
      host: any

    - port: any
      proto: any
      groups:
        - flatnet
```

### Step 6: Windows Firewall の設定

```powershell
# Nebula UDP ポートを開放
New-NetFirewallRule -DisplayName "Nebula UDP" `
    -Direction Inbound `
    -Protocol UDP `
    -LocalPort 4242 `
    -Action Allow

# ICMP (ping) を許可
New-NetFirewallRule -DisplayName "Nebula ICMP" `
    -Direction Inbound `
    -Protocol ICMPv4 `
    -Action Allow
```

### Step 7: NSSM でサービス登録

1. [NSSM](https://nssm.cc/download) をダウンロード
2. `nssm.exe` を `F:\flatnet\` に配置

```powershell
cd F:\flatnet

# サービスとして登録
.\nssm.exe install Nebula F:\flatnet\nebula\nebula.exe
.\nssm.exe set Nebula AppParameters "-config F:\flatnet\config\nebula\config.yaml"
.\nssm.exe set Nebula AppDirectory F:\flatnet
.\nssm.exe set Nebula AppStdout F:\flatnet\logs\nebula.log
.\nssm.exe set Nebula AppStderr F:\flatnet\logs\nebula.log
.\nssm.exe set Nebula AppRotateFiles 1
.\nssm.exe set Nebula AppRotateBytes 10485760

# サービス開始
Start-Service Nebula
```

### Step 8: 動作確認

```powershell
# サービス状態確認
Get-Service Nebula

# ログ確認
Get-Content F:\flatnet\logs\nebula.log -Tail 20

# Nebula インターフェース確認
Get-NetAdapter | Where-Object { $_.Name -like "*nebula*" -or $_.Name -like "*Wintun*" }

# IP 確認
ipconfig | findstr "10.100"
```

---

## ホストセットアップ

### Step 1: Lighthouse から証明書を取得

Lighthouse ホストで新規ホスト用の証明書を生成:

```powershell
# Lighthouse で実行
cd F:\flatnet\nebula

# Host A 用の証明書
.\nebula-cert.exe sign `
    -name "host-a" `
    -ip "10.100.1.1/16" `
    -groups "flatnet,gateway" `
    -ca-crt F:\flatnet\config\nebula\ca.crt `
    -ca-key F:\flatnet\config\nebula\ca.key
```

### Step 2: ファイルの転送

以下のファイルを新規ホストにコピー:

| ファイル | 転送元 | 転送先 |
|----------|--------|--------|
| ca.crt | Lighthouse | `F:\flatnet\config\nebula\ca.crt` |
| host-a.crt | Lighthouse | `F:\flatnet\config\nebula\host.crt` |
| host-a.key | Lighthouse | `F:\flatnet\config\nebula\host.key` |

### Step 3: ホスト設定ファイルの作成

`F:\flatnet\config\nebula\config.yaml`:

```yaml
pki:
  ca: F:\flatnet\config\nebula\ca.crt
  cert: F:\flatnet\config\nebula\host.crt
  key: F:\flatnet\config\nebula\host.key

static_host_map:
  "10.100.0.1": ["<LIGHTHOUSE_LAN_IP>:4242"]

lighthouse:
  am_lighthouse: false
  interval: 60
  hosts:
    - "10.100.0.1"

listen:
  host: 0.0.0.0
  port: 4242

punchy:
  punch: true

tun:
  disabled: false
  dev: nebula1

firewall:
  outbound:
    - port: any
      proto: any
      host: any

  inbound:
    - port: any
      proto: icmp
      host: any

    - port: any
      proto: any
      groups:
        - flatnet
```

**注意:** `<LIGHTHOUSE_LAN_IP>` を Lighthouse の社内 LAN IP に置き換えてください。

### Step 4: サービス登録と起動

```powershell
# Lighthouse と同様の手順
.\nssm.exe install Nebula F:\flatnet\nebula\nebula.exe
.\nssm.exe set Nebula AppParameters "-config F:\flatnet\config\nebula\config.yaml"
# ... (その他の設定)

Start-Service Nebula
```

### Step 5: 接続確認

```powershell
# Lighthouse への ping
ping 10.100.0.1

# ログで接続確認
Get-Content F:\flatnet\logs\nebula.log | Select-String "handshake"
```

---

## CNI Plugin インストール

### Step 1: ビルド環境の準備

WSL2 で実行:

```bash
# Rust のインストール
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# 依存パッケージ
sudo apt update
sudo apt install -y build-essential pkg-config
```

### Step 2: CNI Plugin のビルド

```bash
cd /home/kh/prj/flatnet/src/flatnet-cni

# ビルド
cargo build --release

# インストール
sudo mkdir -p /opt/cni/bin
sudo cp target/release/flatnet /opt/cni/bin/
sudo chmod +x /opt/cni/bin/flatnet
```

### Step 3: CNI 設定

`/etc/cni/net.d/10-flatnet.conflist` を作成:

```json
{
  "cniVersion": "1.0.0",
  "name": "flatnet",
  "plugins": [
    {
      "type": "flatnet",
      "bridge": "flatnet-br0",
      "isGateway": true,
      "ipMasq": false,
      "ipam": {
        "type": "flatnet",
        "subnet": "10.87.1.0/24",
        "gateway": "10.87.1.1",
        "dataDir": "/var/lib/flatnet/ipam"
      }
    }
  ]
}
```

### Step 4: Podman ネットワーク設定

```bash
# Flatnet ネットワークの作成
sudo podman network create \
    --driver bridge \
    --subnet 10.87.1.0/24 \
    --gateway 10.87.1.1 \
    flatnet

# 確認
sudo podman network inspect flatnet
```

### Step 5: IP フォワーディングの設定

```bash
# 一時的に有効化
sudo sysctl -w net.ipv4.ip_forward=1

# 永続化
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
```

---

## Gateway (OpenResty) セットアップ

### Step 1: OpenResty のダウンロード

1. [OpenResty Windows](https://openresty.org/en/download.html) から最新版をダウンロード
2. 展開して `F:\flatnet\openresty\` に配置

### Step 2: 設定ファイルの配置

```powershell
# WSL2 から設定をコピー
wsl cp /home/kh/prj/flatnet/config/openresty/nginx.conf /mnt/f/flatnet/config/
wsl cp -r /home/kh/prj/flatnet/config/openresty/conf.d /mnt/f/flatnet/config/
wsl cp -r /home/kh/prj/flatnet/config/openresty/lualib /mnt/f/flatnet/config/
```

### Step 3: 設定のカスタマイズ

`F:\flatnet\config\nginx.conf` を編集して環境に合わせる:

```nginx
# ホスト ID の設定
set $flatnet_host_id "1";  # Host A = 1, Host B = 2, etc.

# ローカルサブネットの設定
set $flatnet_local_subnet "10.87.1.0/24";
```

### Step 4: OpenResty の起動

```powershell
# 設定テスト
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t

# 起動
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf

# サービスとして登録する場合
.\nssm.exe install OpenResty F:\flatnet\openresty\nginx.exe
.\nssm.exe set OpenResty AppParameters "-c F:\flatnet\config\nginx.conf"
```

---

## 動作確認

### 1. Nebula トンネル確認

```powershell
# Windows から他のホストへ ping
ping 10.100.2.1  # Host B の Nebula IP
```

### 2. WSL2 ルーティング確認

```bash
# WSL2 から Nebula ネットワークへ
ping 10.100.2.1
```

### 3. コンテナ起動確認

```bash
# テストコンテナの起動
sudo podman run -d --name test --network flatnet alpine sleep infinity

# IP 確認
sudo podman inspect test | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress'
```

### 4. Gateway API 確認

```bash
# API ステータス
curl http://10.100.1.1:8080/api/status

# ヘルスチェック
curl http://10.100.1.1:8080/api/health
```

### 5. 統合テスト

```bash
# 統合テストスクリプトの実行
cd /home/kh/prj/flatnet
./tests/integration/phase3/test_basic.sh
```

---

## チェックリスト

### Lighthouse
- [ ] Nebula バイナリを配置
- [ ] CA 証明書を生成
- [ ] Lighthouse 証明書を生成
- [ ] 設定ファイルを作成
- [ ] Windows Firewall を設定
- [ ] サービスとして登録
- [ ] サービスが起動している

### Host
- [ ] 証明書を Lighthouse から取得
- [ ] 設定ファイルを作成 (Lighthouse IP を設定)
- [ ] サービスとして登録
- [ ] Lighthouse への ping が成功

### CNI Plugin
- [ ] Rust 環境をセットアップ
- [ ] プラグインをビルド
- [ ] /opt/cni/bin/ にインストール
- [ ] CNI 設定ファイルを作成
- [ ] IP フォワーディングを有効化

### Gateway
- [ ] OpenResty をダウンロード
- [ ] 設定ファイルを配置
- [ ] ホスト ID を設定
- [ ] 起動確認

---

## 次のステップ

- [Operations Guide](operations-guide.md) - 日常運用手順
- [Troubleshooting](troubleshooting.md) - 問題解決ガイド

## 関連ドキュメント

- [Phase 3 Stage 1: Lighthouse Setup](../phases/phase-3/stage-1-lighthouse-setup.md)
- [Phase 3 Stage 2: Host Tunnel](../phases/phase-3/stage-2-host-tunnel.md)
- [Host Setup Guide](../phases/phase-3/host-setup-guide.md)
