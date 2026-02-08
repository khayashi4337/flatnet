# Phase 3 Nebula Lighthouse セットアップガイド

## 概要

Nebula Lighthouse をセットアップし、マルチホスト環境のノード管理基盤を構築する手順を説明します。

**重要:** Lighthouse はサーバー側のインフラであり、クライアントには見せません（設計原則）。

## 環境要件

| 項目 | 要件 |
|------|------|
| OS | Windows 10/11 (21H2 以降) |
| メモリ | 4GB 以上 |
| ディスク | F: ドライブに 100MB 以上の空き |
| ネットワーク | UDP 4242 を開放可能 |
| 依存 | Phase 1 (OpenResty) 完了 |

## 前提条件

- Phase 1 が完了している
- WSL2 で Git リポジトリにアクセス可能
- 管理者権限で PowerShell を実行可能

## 1. Nebula バイナリの取得

### 1.1 ダウンロード

1. https://github.com/slackhq/nebula/releases にアクセス
2. `nebula-windows-amd64.zip` をダウンロード（推奨: v1.9.x 以降）
3. ダウンロードフォルダに保存

### 1.2 配置

```powershell
# ディレクトリ作成
New-Item -ItemType Directory -Path F:\flatnet\nebula -Force

# ZIP を展開
Expand-Archive -Path $env:USERPROFILE\Downloads\nebula-windows-amd64.zip -DestinationPath F:\flatnet\nebula\

# バージョン確認
F:\flatnet\nebula\nebula.exe -version
F:\flatnet\nebula\nebula-cert.exe -version
```

期待される出力:
```
Nebula version X.X.X
```

## 2. CA 証明書の生成

CA (Certificate Authority) は Flatnet ネットワーク内の全ホストに署名するための証明書インフラです。

### 2.1 スクリプトを使用（推奨）

WSL2 から Git リポジトリの最新版を Windows に同期後、PowerShell で実行:

```powershell
# スクリプトを Windows 側にコピー（既にデプロイ済みの場合はスキップ）
# WSL2 側で: ./scripts/deploy-config.sh

# CA 生成スクリプトを実行
cd F:\flatnet\scripts\nebula
.\gen-ca.ps1
```

### 2.2 手動で実行（代替）

```powershell
# ディレクトリ作成
New-Item -ItemType Directory -Path F:\flatnet\pki -Force
New-Item -ItemType Directory -Path F:\flatnet\config\nebula -Force

# CA 証明書の生成（有効期限 1年）
cd F:\flatnet\pki
F:\flatnet\nebula\nebula-cert.exe ca -name "Flatnet CA" -duration 8760h

# ca.crt を config にコピー
Copy-Item F:\flatnet\pki\ca.crt F:\flatnet\config\nebula\
```

### 2.3 確認

```powershell
# CA 証明書の内容を確認
F:\flatnet\nebula\nebula-cert.exe print -path F:\flatnet\config\nebula\ca.crt
```

期待される出力:
```
NebulaCertificate {
    Details {
        Name: Flatnet CA
        Groups: []
        ...
        IsCA: true
        ...
    }
    ...
}
```

**重要:** `F:\flatnet\pki\ca.key` は CA 秘密鍵です。この鍵が漏洩すると、ネットワーク全体のセキュリティが損なわれます。厳重に保管し、証明書発行時のみ使用してください。

## 3. Lighthouse 証明書の生成

### 3.1 スクリプトを使用（推奨）

```powershell
cd F:\flatnet\scripts\nebula
.\gen-host-cert.ps1 -Name lighthouse -Ip 10.100.0.1/16
```

### 3.2 手動で実行（代替）

```powershell
cd F:\flatnet\pki

# Lighthouse 用証明書を生成
F:\flatnet\nebula\nebula-cert.exe sign `
  -name "lighthouse" `
  -ip "10.100.0.1/16" `
  -ca-crt F:\flatnet\config\nebula\ca.crt `
  -ca-key F:\flatnet\pki\ca.key

# 証明書を config に配置
Move-Item lighthouse.crt F:\flatnet\config\nebula\
Move-Item lighthouse.key F:\flatnet\config\nebula\
```

### 3.3 確認

```powershell
# 証明書の内容を確認
F:\flatnet\nebula\nebula-cert.exe print -path F:\flatnet\config\nebula\lighthouse.crt

# 証明書の検証
F:\flatnet\nebula\nebula-cert.exe verify -ca F:\flatnet\config\nebula\ca.crt -crt F:\flatnet\config\nebula\lighthouse.crt
```

期待される出力:
```
NebulaCertificate {
    Details {
        Name: lighthouse
        Ips: [10.100.0.1/16]
        ...
        IsCA: false
        ...
    }
    ...
}
```

## 4. Lighthouse のセットアップ

### 4.1 スクリプトを使用（推奨）

```powershell
cd F:\flatnet\scripts\nebula

# 設定ファイルを生成してテスト
.\setup-lighthouse.ps1

# サービスとして登録・起動（管理者権限必要）
.\setup-lighthouse.ps1 -Install -Start -SetupFirewall
```

### 4.2 手動で設定（代替）

#### 4.2.1 設定ファイルの作成

ファイル: `F:\flatnet\config\nebula\config.yaml`

```yaml
pki:
  ca: F:/flatnet/config/nebula/ca.crt
  cert: F:/flatnet/config/nebula/lighthouse.crt
  key: F:/flatnet/config/nebula/lighthouse.key

lighthouse:
  am_lighthouse: true

listen:
  host: 0.0.0.0
  port: 4242

logging:
  level: info
  format: text

tun:
  dev: nebula1
  drop_local_broadcast: false
  drop_multicast: false

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
      group: any
```

**注意:** Windows ではパス区切りにスラッシュ（`/`）を使用してください。バックスラッシュ（`\`）は YAML でエスケープが必要になります。

#### 4.2.2 設定テスト

```powershell
F:\flatnet\nebula\nebula.exe -config F:\flatnet\config\nebula\config.yaml -test
```

期待される出力:
```
(設定エラーがなければ何も出力されない)
```

#### 4.2.3 テスト起動

```powershell
# フォアグラウンドで起動（Ctrl+C で停止）
F:\flatnet\nebula\nebula.exe -config F:\flatnet\config\nebula\config.yaml
```

期待されるログ:
```
level=info msg="Handshake manager has no lighthouses..."
level=info msg="Firewall started..."
level=info msg="Main HostMap..."
```

### 4.3 ファイアウォール設定

```powershell
# 管理者権限で実行
New-NetFirewallRule -DisplayName "Nebula UDP" -Direction Inbound -Protocol UDP -LocalPort 4242 -Action Allow
New-NetFirewallRule -DisplayName "Nebula Program In" -Direction Inbound -Program "F:\flatnet\nebula\nebula.exe" -Action Allow
New-NetFirewallRule -DisplayName "Nebula Program Out" -Direction Outbound -Program "F:\flatnet\nebula\nebula.exe" -Action Allow

# 確認
Get-NetFirewallRule -DisplayName "Nebula*" | Format-Table DisplayName, Enabled, Action
```

### 4.4 サービスとして登録（NSSM）

NSSM が未導入の場合は https://nssm.cc/download からダウンロードし、`F:\flatnet\nssm.exe` に配置。

```powershell
# 管理者権限で実行
F:\flatnet\nssm.exe install Nebula F:\flatnet\nebula\nebula.exe
F:\flatnet\nssm.exe set Nebula AppDirectory F:\flatnet\nebula
F:\flatnet\nssm.exe set Nebula AppParameters "-config F:\flatnet\config\nebula\config.yaml"
F:\flatnet\nssm.exe set Nebula Description "Flatnet Nebula (Lighthouse)"
F:\flatnet\nssm.exe set Nebula Start SERVICE_AUTO_START

# ログ設定
F:\flatnet\nssm.exe set Nebula AppStdout F:\flatnet\logs\nebula.log
F:\flatnet\nssm.exe set Nebula AppStderr F:\flatnet\logs\nebula.log
F:\flatnet\nssm.exe set Nebula AppRotateFiles 1
F:\flatnet\nssm.exe set Nebula AppRotateBytes 10485760

# サービス開始
Start-Service Nebula
```

## 5. 動作確認

### 5.1 サービス状態

```powershell
Get-Service Nebula
```

期待される出力:
```
Status   Name               DisplayName
------   ----               -----------
Running  Nebula             Nebula
```

### 5.2 ポート確認

```powershell
netstat -an | findstr 4242
```

期待される出力:
```
UDP    0.0.0.0:4242           *:*
```

### 5.3 ログ確認

```powershell
Get-Content F:\flatnet\logs\nebula.log -Tail 20
```

確認すべき内容:
- `Firewall started` が出力されていること
- エラーログがないこと

## 6. Host A 証明書の生成（Lighthouse と同一ホストの場合）

Lighthouse と Gateway（Host A）が同一マシンの場合、Lighthouse の IP をそのまま Gateway IP として使用します。別途 Host A の証明書は不要です。

別ホストの場合は以下を実行:

```powershell
cd F:\flatnet\scripts\nebula
.\gen-host-cert.ps1 -Name host-a -Ip 10.100.1.1/16 -Groups "flatnet,gateway"
```

生成された証明書を安全な方法で Host A に転送してください。

## IP アドレス空間設計

```
10.100.0.0/16 - Flatnet 全体
  10.100.0.0/24   - インフラ用
    10.100.0.1    - Lighthouse
    10.100.0.2-10 - 予約（将来の拡張用）

  10.100.X.0/24   - Host X（ホスト ID = X）用
    10.100.X.1    - Host X の Windows (Gateway/Nebula)
    10.100.X.2    - Host X の WSL2（オプション）
    10.100.X.10-254 - Host X 上のコンテナ用

例:
  10.100.1.0/24   - Host A（ホスト ID = 1）
    10.100.1.1    - Host A Gateway
    10.100.1.10   - Container A1
  10.100.2.0/24   - Host B（ホスト ID = 2）
    10.100.2.1    - Host B Gateway
    10.100.2.10   - Container B1
```

## トラブルシューティング

### Nebula が起動しない

**症状:** サービスが Running にならない

**対処:**

```powershell
# ログを確認
Get-Content F:\flatnet\logs\nebula.log -Tail 50

# 設定テストを実行
F:\flatnet\nebula\nebula.exe -config F:\flatnet\config\nebula\config.yaml -test
```

よくある原因:
- 証明書ファイルのパスが間違っている
- YAML の構文エラー（インデント、パス区切り）
- CA 証明書と署名証明書のミスマッチ

### UDP ポートがリッスンされていない

**症状:** `netstat -an | findstr 4242` で何も表示されない

**対処:**

1. Nebula プロセスが起動しているか確認:
   ```powershell
   Get-Process nebula -ErrorAction SilentlyContinue
   ```

2. ファイアウォールがブロックしていないか確認:
   ```powershell
   Get-NetFirewallRule -DisplayName "Nebula*"
   ```

### 証明書の検証エラー

**症状:** `nebula-cert verify` でエラー

**対処:**

```powershell
# CA 証明書を確認
F:\flatnet\nebula\nebula-cert.exe print -path F:\flatnet\config\nebula\ca.crt

# ホスト証明書を確認
F:\flatnet\nebula\nebula-cert.exe print -path F:\flatnet\config\nebula\lighthouse.crt
```

確認ポイント:
- CA 証明書の `IsCA: true` になっているか
- ホスト証明書の有効期限が切れていないか
- CA と署名証明書が同じ CA から発行されているか

### Windows 再起動後に接続できない

**症状:** Windows 再起動後、他のホストから Lighthouse に接続できない

**対処:**

1. サービスが自動起動しているか確認:
   ```powershell
   Get-Service Nebula
   ```

2. Firewall ルールが有効か確認:
   ```powershell
   Get-NetFirewallRule -DisplayName "Nebula*" | Format-Table DisplayName, Enabled
   ```

## 次のステップ

Stage 1 完了後は [Stage 2: ホスト間トンネル構築](../phases/phase-3/stage-2-host-tunnel.md) に進み、複数ホスト間の Nebula トンネルを確立します。
