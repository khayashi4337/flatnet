# Stage 1: Nebula Lighthouse 導入

## 概要

Nebula Lighthouse をセットアップし、マルチホスト環境のノード管理基盤を構築する。Lighthouse は各ホストの位置情報を管理し、NAT 越えを支援する中央コーディネーターとして機能する。

**重要:** Lighthouse は Phase 3 で導入されるが、クライアントには見せない（設計原則）。

## ブランチ戦略

- ブランチ名: `phase3/stage-1-lighthouse-setup`
- マージ先: `master`

## インプット（前提条件）

- Phase 2 が完了している（CNI Plugin が単一ホストで動作）
- Lighthouse を稼働させるサーバーまたはホストが決定している
  - 推奨: Host A（最初の Windows ホスト）に同居
- Nebula バイナリのダウンロードが可能
- Lighthouse 用の固定 IP または DNS 名が利用可能

## 目標

- Nebula Lighthouse を Windows 上で稼働させる
- 証明書インフラ（CA）を構築する
- 最初のホスト（Host A）を Lighthouse に登録する
- Lighthouse と Gateway の連携方式を設計する（実装は Stage 3 以降）

## ディレクトリ構成

```
[Windows] F:\flatnet\
          ├── openresty\           ← Phase 1 で配置済み
          ├── nebula\              ← Nebula バイナリ
          │   ├── nebula.exe
          │   └── nebula-cert.exe
          ├── config\
          │   ├── nginx.conf       ← Phase 1 で配置済み
          │   └── nebula\          ← Nebula 設定
          │       ├── config.yaml
          │       ├── ca.crt
          │       └── host.crt / host.key
          ├── pki\                 ← CA 秘密鍵（厳重管理）
          │   └── ca.key
          └── logs\
              └── nebula.log

[WSL2] /home/kh/prj/flatnet/
       └── config/
           └── nebula/             ← Git 管理（テンプレート）
               ├── lighthouse.yaml.template
               └── host.yaml.template
```

## 手段

- Nebula 公式バイナリのダウンロード
- nebula-cert による CA 証明書の生成
- Lighthouse 用 config.yaml の作成
- Windows サービスとしての登録（NSSM 使用）

## Sub-stages

### Sub-stage 1.1: Nebula バイナリ取得と CA 構築

**内容:**
- Nebula 公式リリースから Windows バイナリをダウンロード
  - 推奨バージョン: v1.9.x 以降（安定版）
  - ダウンロード先: https://github.com/slackhq/nebula/releases
  - ファイル: `nebula-windows-amd64.zip`
- `nebula-cert ca` で CA 証明書を生成
- CA 秘密鍵の安全な保管場所を決定

**手順 (PowerShell 管理者):**

```powershell
# ディレクトリ作成
New-Item -ItemType Directory -Path F:\flatnet\nebula -Force
New-Item -ItemType Directory -Path F:\flatnet\config\nebula -Force
New-Item -ItemType Directory -Path F:\flatnet\pki -Force

# ダウンロードと展開
cd $env:USERPROFILE\Downloads
# nebula-windows-amd64.zip をダウンロード後
Expand-Archive -Path nebula-windows-amd64.zip -DestinationPath F:\flatnet\nebula\

# バージョン確認
F:\flatnet\nebula\nebula.exe -version
F:\flatnet\nebula\nebula-cert.exe -version

# CA 証明書の生成（有効期限 1年）
cd F:\flatnet\pki
F:\flatnet\nebula\nebula-cert.exe ca -name "Flatnet CA" -duration 8760h

# ca.crt を config に、ca.key は pki に保持
Copy-Item F:\flatnet\pki\ca.crt F:\flatnet\config\nebula\
```

**生成されるファイル:**
- `F:\flatnet\pki\ca.key` - CA 秘密鍵（厳重に保管、証明書発行時のみ使用）
- `F:\flatnet\config\nebula\ca.crt` - CA 公開証明書（各ホストに配布）

**完了条件:**
- [ ] `F:\flatnet\nebula\nebula.exe -version` でバージョンが表示される
- [ ] `F:\flatnet\nebula\nebula-cert.exe -version` でバージョンが表示される
- [ ] CA 証明書が `F:\flatnet\config\nebula\ca.crt` に配置されている
- [ ] CA 秘密鍵が `F:\flatnet\pki\ca.key` に保管されている
- [ ] Nebula バージョンが記録されている（例: v1.9.0）

### Sub-stage 1.2: Lighthouse 証明書生成

**内容:**
- Lighthouse 用のノード証明書を生成
- Flatnet IP アドレス空間の設計（例: `10.100.0.0/16`）
- Lighthouse に `10.100.0.1` を割り当て

**手順 (PowerShell):**

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

**完了条件:**
- [ ] `F:\flatnet\config\nebula\lighthouse.crt` が生成されている
- [ ] `F:\flatnet\config\nebula\lighthouse.key` が生成されている
- [ ] 証明書の IP が `10.100.0.1/16` であることを確認
  ```powershell
  F:\flatnet\nebula\nebula-cert.exe print -path F:\flatnet\config\nebula\lighthouse.crt
  ```
- [ ] Flatnet IP アドレス空間が決定・文書化されている

### Sub-stage 1.3: Lighthouse 設定と起動

**内容:**
- `config.yaml` の作成
  - `am_lighthouse: true`
  - `listen` ポートの設定（デフォルト: 4242/udp）
  - ファイアウォール設定（inbound/outbound ルール）
- Windows 上で Lighthouse を起動
- 起動確認とログ確認

**設定ファイル作成:**

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
  # ログファイル出力は NSSM で設定

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

**起動テスト (PowerShell):**

```powershell
# 設定テスト（dry-run）
F:\flatnet\nebula\nebula.exe -config F:\flatnet\config\nebula\config.yaml -test

# フォアグラウンドで起動（テスト用）
F:\flatnet\nebula\nebula.exe -config F:\flatnet\config\nebula\config.yaml
# Ctrl+C で停止
```

**完了条件:**
- [ ] 設定テストが成功する
- [ ] Lighthouse プロセスが起動している
- [ ] ログに `Lighthouse mode enabled` が出力されている
- [ ] UDP 4242 でリッスンしている
  ```powershell
  netstat -an | findstr 4242
  # 期待: UDP 0.0.0.0:4242
  ```

### Sub-stage 1.4: ファイアウォール設定

**内容:**
- Windows Firewall で Nebula ポート（UDP 4242）を開放
- 必要に応じてルーター/VPN の設定

**手順 (PowerShell 管理者):**

```powershell
# Nebula UDP ポートを開放
New-NetFirewallRule -DisplayName "Nebula UDP" -Direction Inbound -Protocol UDP -LocalPort 4242 -Action Allow

# Nebula プログラム自体を許可（TAP アダプタ通信用）
New-NetFirewallRule -DisplayName "Nebula Program" -Direction Inbound -Program "F:\flatnet\nebula\nebula.exe" -Action Allow
New-NetFirewallRule -DisplayName "Nebula Program Out" -Direction Outbound -Program "F:\flatnet\nebula\nebula.exe" -Action Allow

# 確認
Get-NetFirewallRule -DisplayName "Nebula*" | Format-Table DisplayName, Enabled, Action
```

**完了条件:**
- [ ] Firewall ルールが有効になっている
- [ ] 社内 LAN の別端末から Lighthouse の UDP ポートに到達可能
  ```bash
  # Linux/WSL2 から確認
  nc -vzu <Lighthouse IP> 4242
  ```
- [ ] 証明書の検証が成功する
  ```powershell
  F:\flatnet\nebula\nebula-cert.exe verify -ca F:\flatnet\config\nebula\ca.crt -crt F:\flatnet\config\nebula\lighthouse.crt
  ```

### Sub-stage 1.5: 最初のホスト（Host A）登録

**内容:**
- Host A 用の証明書を生成（例: `10.100.1.1`）
- Host A の Nebula クライアント設定
- Lighthouse への接続確認

**注意:** Lighthouse と Host A が同一マシンの場合、両方の役割を1つの設定で担う。

**Host A 証明書生成 (別ホストの場合):**

```powershell
cd F:\flatnet\pki

# Host A 用証明書を生成
F:\flatnet\nebula\nebula-cert.exe sign `
  -name "host-a" `
  -ip "10.100.1.1/16" `
  -groups "flatnet,gateway" `
  -ca-crt F:\flatnet\config\nebula\ca.crt `
  -ca-key F:\flatnet\pki\ca.key

# Host A に配布（別ホストの場合はセキュアな方法で転送）
```

**Lighthouse と同一ホストの場合:**

Lighthouse の config.yaml に Host A の役割も持たせる（IP を `10.100.0.1` と `10.100.1.1` の両方にするか、Lighthouse IP を Gateway IP として使用）。

**完了条件:**
- [ ] Host A の証明書が生成されている（別ホストの場合）
- [ ] Host A が Lighthouse に接続している（Lighthouse ログで確認）
  ```
  [INFO] Handshake received from 10.100.1.1
  ```
- [ ] Host A の Nebula インターフェースに IP が割り当てられている
  ```powershell
  ipconfig /all | findstr "nebula"
  ```

### Sub-stage 1.6: サービス化（NSSM）

**内容:**
- NSSM を使用して Nebula を Windows サービスとして登録
- 自動起動の設定
- ログ出力の設定

**手順 (PowerShell 管理者):**

```powershell
# NSSM が未導入の場合（Phase 1 で導入済みの場合はスキップ）
# https://nssm.cc/download から nssm.exe を F:\flatnet\ に配置

# サービス登録
F:\flatnet\nssm.exe install Nebula F:\flatnet\nebula\nebula.exe
F:\flatnet\nssm.exe set Nebula AppDirectory F:\flatnet\nebula
F:\flatnet\nssm.exe set Nebula AppParameters "-config F:\flatnet\config\nebula\config.yaml"
F:\flatnet\nssm.exe set Nebula Description "Flatnet Nebula (Lighthouse/Node)"
F:\flatnet\nssm.exe set Nebula Start SERVICE_AUTO_START

# ログ出力設定
F:\flatnet\nssm.exe set Nebula AppStdout F:\flatnet\logs\nebula.log
F:\flatnet\nssm.exe set Nebula AppStderr F:\flatnet\logs\nebula.log
F:\flatnet\nssm.exe set Nebula AppRotateFiles 1
F:\flatnet\nssm.exe set Nebula AppRotateBytes 10485760

# サービス開始
Start-Service Nebula

# 状態確認
Get-Service Nebula
```

**完了条件:**
- [ ] Nebula サービスが Running 状態
- [ ] Windows 再起動後も自動起動する
- [ ] `F:\flatnet\logs\nebula.log` にログが出力される

## 成果物

| 種別 | パス | 説明 |
|------|------|------|
| バイナリ | `F:\flatnet\nebula\nebula.exe` | Nebula 本体 |
| バイナリ | `F:\flatnet\nebula\nebula-cert.exe` | 証明書ツール |
| CA 秘密鍵 | `F:\flatnet\pki\ca.key` | 厳重管理（証明書発行時のみ使用）|
| CA 証明書 | `F:\flatnet\config\nebula\ca.crt` | 各ホストに配布 |
| Lighthouse 証明書 | `F:\flatnet\config\nebula\lighthouse.crt` | Lighthouse 用 |
| Lighthouse 秘密鍵 | `F:\flatnet\config\nebula\lighthouse.key` | Lighthouse 用 |
| 設定ファイル | `F:\flatnet\config\nebula\config.yaml` | Lighthouse/ノード設定 |
| ログ | `F:\flatnet\logs\nebula.log` | Nebula ログ |
| Windows サービス | `Nebula` | NSSM で登録 |

**ドキュメント成果物:**
- IP アドレス空間設計書（本ドキュメントの技術メモに記載）
- ホスト証明書生成手順（Sub-stage 1.5 に記載）

## 完了条件

- [ ] Nebula Lighthouse が稼働している
- [ ] CA インフラが構築されている
- [ ] 最初のホスト（Host A）が Lighthouse に接続している
- [ ] 証明書生成手順が文書化されている

## 技術メモ

### Flatnet IP アドレス空間設計（案）

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
    10.100.1.11   - Container A2
  10.100.2.0/24   - Host B（ホスト ID = 2）
    10.100.2.1    - Host B Gateway
    10.100.2.10   - Container B1
```

### Lighthouse 設定例（Windows）

```yaml
# F:\flatnet\config\nebula\config.yaml
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

**注意:** Windows ではパス区切りにスラッシュ（`/`）を使用。バックスラッシュ（`\`）は YAML でエスケープが必要になるため避ける。

## 依存関係

- なし（Phase 3 の最初の Stage）

## 設計メモ: Lighthouse と Gateway の連携

Phase 3 では、Gateway が直接 Lighthouse に問い合わせるのではなく、以下の方式を採用:

1. **Nebula は純粋にトンネル提供**: ホスト間通信の暗号化と NAT 越え
2. **コンテナ情報は Gateway 間で同期**: Stage 3 で実装する HTTP API
3. **Lighthouse はノード管理に専念**: 新規ホストの参加、ホールパンチ支援

これにより、Nebula の設計を変更せずに Flatnet の機能を追加できる。

## リスク

- Lighthouse のダウンにより新規接続ができなくなる
  - 対策: 複数 Lighthouse の冗長化は Phase 4 で検討

## 次のステップ

Stage 1 完了後は [Stage 2: ホスト間トンネル構築](./stage-2-host-tunnel.md) に進み、複数ホスト間の Nebula トンネルを確立する。
