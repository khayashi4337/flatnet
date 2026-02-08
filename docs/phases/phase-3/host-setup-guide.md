# ホスト追加ガイド

## 概要

このガイドでは、Flatnet Nebula ネットワークに新しいホストを追加する手順を説明します。

## 前提条件

- Lighthouse が稼働中であること（Stage 1 完了）
- 新規ホストで Windows Firewall の設定変更が可能であること
- 管理者権限でコマンドを実行できること

## IP アドレス割り当て

| ホスト | Nebula IP | 用途 |
|--------|-----------|------|
| Lighthouse | 10.100.0.1/16 | 中央ノード |
| Host A | 10.100.1.1/16 | 開発環境 |
| Host B | 10.100.2.1/16 | 開発環境 |
| Host C | 10.100.3.1/16 | 開発環境 |
| ... | 10.100.x.1/16 | 追加ホスト |

## 手順

### Step 1: 証明書の生成（Lighthouse ホストで実行）

```powershell
# Lighthouse ホストの PowerShell で実行
cd F:\flatnet\scripts

# 新規ホスト用の証明書を生成
# 例: Host C (10.100.3.1)
.\gen-host-cert.ps1 -Name "host-c" -Ip "10.100.3.1/16" -Groups "flatnet,gateway"
```

生成されるファイル:
- `F:\flatnet\config\nebula\host-c.crt`
- `F:\flatnet\config\nebula\host-c.key`

### Step 2: ファイルの転送

以下のファイルを新規ホストにセキュアな方法でコピーします:

| ソース (Lighthouse) | コピー先 (新規ホスト) |
|---------------------|----------------------|
| `F:\flatnet\config\nebula\ca.crt` | `F:\flatnet\config\nebula\ca.crt` |
| `F:\flatnet\config\nebula\host-c.crt` | `F:\flatnet\config\nebula\host.crt` |
| `F:\flatnet\config\nebula\host-c.key` | `F:\flatnet\config\nebula\host.key` |

**重要**: 証明書ファイル名は `host.crt` と `host.key` にリネームしてください。

### Step 3: 新規ホストのセットアップ

#### 3.1 ディレクトリ構成の作成

```powershell
# 新規ホストで実行（管理者 PowerShell）
New-Item -ItemType Directory -Path F:\flatnet\nebula -Force
New-Item -ItemType Directory -Path F:\flatnet\config\nebula -Force
New-Item -ItemType Directory -Path F:\flatnet\logs -Force
New-Item -ItemType Directory -Path F:\flatnet\scripts -Force
```

#### 3.2 Nebula バイナリの配置

1. [Nebula Releases](https://github.com/slackhq/nebula/releases) から `nebula-windows-amd64.zip` をダウンロード
2. 展開して以下に配置:
   - `F:\flatnet\nebula\nebula.exe`
   - `F:\flatnet\nebula\nebula-cert.exe`

#### 3.3 NSSM の配置

1. [NSSM](https://nssm.cc/download) から nssm.exe をダウンロード
2. `F:\flatnet\nssm.exe` に配置

#### 3.4 スクリプトのコピー

Flatnet リポジトリから以下のスクリプトをコピー:
- `scripts/nebula/setup-host.ps1` -> `F:\flatnet\scripts\`
- `scripts/nebula/setup-routing.ps1` -> `F:\flatnet\scripts\`
- `scripts/nebula/test-tunnel.ps1` -> `F:\flatnet\scripts\`

### Step 4: Nebula のセットアップと起動

```powershell
# 管理者 PowerShell で実行
cd F:\flatnet\scripts

# セットアップ（Lighthouse の IP を指定）
.\setup-host.ps1 `
    -HostName "host-c" `
    -LighthouseAddr "192.168.1.10:4242" `
    -Install `
    -Start `
    -SetupFirewall

# 接続確認
.\test-tunnel.ps1
```

**LighthouseAddr の確認方法**:
```powershell
# Lighthouse ホストで実行
ipconfig | findstr "IPv4"
# 社内 LAN の IP アドレスに :4242 を付加
# 例: 192.168.1.10:4242
```

### Step 5: 接続確認

#### Lighthouse ログで確認

```powershell
# Lighthouse ホストで実行
Get-Content F:\flatnet\logs\nebula.log -Tail 20 | Select-String "host-c"
# 期待: "Handshake received from 10.100.3.1" のようなログ
```

#### 相互 ping テスト

```powershell
# 新規ホストから Lighthouse へ
ping 10.100.0.1

# 新規ホストから他ホストへ
ping 10.100.1.1  # Host A
ping 10.100.2.1  # Host B

# 他ホストから新規ホストへ
ping 10.100.3.1  # Host C
```

### Step 6: WSL2 ルーティング設定（オプション）

WSL2 から他ホストにアクセスする場合:

#### Windows 側（管理者 PowerShell）

```powershell
cd F:\flatnet\scripts
.\setup-routing.ps1 -EnableForwarding -Persistent
```

#### WSL2 側

```bash
# スクリプトを WSL2 にコピー
cp /mnt/f/flatnet/scripts/wsl-routing.sh ~/

# 実行権限を付与
chmod +x ~/wsl-routing.sh

# ルートを追加
~/wsl-routing.sh add

# テスト
~/wsl-routing.sh test
```

## チェックリスト

新規ホスト追加時のチェックリスト:

### Lighthouse での作業
- [ ] `gen-host-cert.ps1` で証明書を生成
- [ ] 生成された証明書と CA 証明書を新規ホストに転送

### 新規ホストでの作業
- [ ] ディレクトリ構成を作成 (`F:\flatnet\...`)
- [ ] Nebula バイナリを配置 (`nebula.exe`, `nebula-cert.exe`)
- [ ] NSSM を配置 (`nssm.exe`)
- [ ] 証明書を配置 (`ca.crt`, `host.crt`, `host.key`)
- [ ] スクリプトを配置
- [ ] `setup-host.ps1` を実行
- [ ] Firewall ルールが追加されていることを確認
- [ ] Nebula サービスが起動していることを確認

### 接続確認
- [ ] Lighthouse への ping が成功
- [ ] 他ホストへの ping が成功
- [ ] Lighthouse ログで接続が確認できる

### WSL2 ルーティング（オプション）
- [ ] Windows 側で IP Forwarding を有効化
- [ ] WSL2 側でルートを追加
- [ ] WSL2 から他ホストへの ping が成功

## トラブルシューティング

### Nebula サービスが起動しない

```powershell
# ログを確認
Get-Content F:\flatnet\logs\nebula.log -Tail 50

# 設定テスト
F:\flatnet\nebula\nebula.exe -config F:\flatnet\config\nebula\config.yaml -test
```

よくある原因:
- 証明書ファイルのパスが間違っている
- 証明書が CA で署名されていない
- Lighthouse の IP/ポートが間違っている

### ping が通らない

```powershell
# Nebula インターフェースを確認
Get-NetAdapter | Where-Object { $_.Name -like "*nebula*" -or $_.Name -like "*Wintun*" }

# Windows Firewall を確認
Get-NetFirewallRule -DisplayName "Nebula*"

# ICMP が許可されているか確認
Get-NetFirewallRule -DisplayName "*ICMP*" | Where-Object { $_.Enabled -eq "True" }
```

### WSL2 からの接続が失敗

```powershell
# IP Forwarding が有効か確認
.\setup-routing.ps1 -ShowStatus

# Nebula インターフェースの Forwarding を確認
Get-NetIPInterface -AddressFamily IPv4 |
    Where-Object { $_.Forwarding -eq "Enabled" } |
    Format-Table InterfaceAlias, Forwarding
```

### ホールパンチが失敗する

NAT が厳しい環境では、直接通信ができず Lighthouse 経由のリレーになることがあります。

```powershell
# ログで確認
Get-Content F:\flatnet\logs\nebula.log | Select-String "relay"
```

リレー経由でも通信は可能ですが、遅延が増加します。

## 参考

- [Nebula 公式ドキュメント](https://nebula.defined.net/docs/)
- [Stage 2 設計ドキュメント](./stage-2-host-tunnel.md)
- [Stage 1 設計ドキュメント](./stage-1-nebula-lighthouse.md)
