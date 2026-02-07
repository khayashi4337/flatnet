# Stage 2: ホスト間トンネル構築

## 概要

複数の Windows ホスト間で Nebula トンネルを確立する。これにより、各ホストの WSL2 環境が相互に通信できるネットワーク基盤を構築する。

## ブランチ戦略

- ブランチ名: `phase3/stage-2-host-tunnel`
- マージ先: `master`

## インプット（前提条件）

- Stage 1 完了（Lighthouse が稼働中、Host A が接続済み）
- 2台目以降のホスト（Host B, C...）が利用可能
- 各ホストで Windows Firewall の設定変更が可能

## 目標

- 複数ホスト間で Nebula トンネルを確立する
- ホスト間で ping が通ることを確認する
- WSL2 から Nebula ネットワークにアクセスできるようにする

## ディレクトリ構成（各ホスト共通）

```
[Windows] F:\flatnet\
          ├── openresty\           ← Phase 1 で配置済み
          ├── nebula\              ← Nebula バイナリ
          │   ├── nebula.exe
          │   └── nebula-cert.exe
          ├── config\
          │   ├── nginx.conf
          │   └── nebula\
          │       ├── config.yaml  ← ホスト固有の設定
          │       ├── ca.crt       ← 共通（Lighthouse から配布）
          │       ├── host.crt     ← ホスト固有
          │       └── host.key     ← ホスト固有
          └── logs\
              └── nebula.log
```

## 手段

- 各ホスト用の証明書を生成（Lighthouse の CA で署名）
- 各ホストに Nebula をインストール・設定
- WSL2 へのルーティング設定
- IP フォワーディングの有効化

## Sub-stages

### Sub-stage 2.1: Host B 証明書生成と接続

**内容:**
- Host B 用の証明書を生成（例: `10.100.2.1`）
- Host B に Nebula をインストール
- `config.yaml` を設定して Lighthouse に接続

**Host B 証明書生成（Lighthouse ホストで実行）:**

```powershell
cd F:\flatnet\pki

# Host B 用証明書を生成
F:\flatnet\nebula\nebula-cert.exe sign `
  -name "host-b" `
  -ip "10.100.2.1/16" `
  -groups "flatnet,gateway" `
  -ca-crt F:\flatnet\config\nebula\ca.crt `
  -ca-key F:\flatnet\pki\ca.key

# 生成されたファイルを Host B に転送
# - host-b.crt
# - host-b.key
# - ca.crt（Lighthouse から）
```

**Host B セットアップ (Host B の PowerShell 管理者):**

```powershell
# ディレクトリ作成
New-Item -ItemType Directory -Path F:\flatnet\nebula -Force
New-Item -ItemType Directory -Path F:\flatnet\config\nebula -Force
New-Item -ItemType Directory -Path F:\flatnet\logs -Force

# Nebula バイナリ配置（ダウンロードまたは Host A からコピー）
# 証明書配置（セキュアな方法で転送）
# - F:\flatnet\config\nebula\ca.crt
# - F:\flatnet\config\nebula\host.crt (host-b.crt をリネーム)
# - F:\flatnet\config\nebula\host.key (host-b.key をリネーム)
```

**Host B 設定ファイル:**

ファイル: `F:\flatnet\config\nebula\config.yaml`

```yaml
pki:
  ca: F:/flatnet/config/nebula/ca.crt
  cert: F:/flatnet/config/nebula/host.crt
  key: F:/flatnet/config/nebula/host.key

lighthouse:
  am_lighthouse: false
  hosts:
    - "<Lighthouse の社内LAN IP>:4242"

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
      group: flatnet
```

**完了条件:**
- [ ] Host B の証明書が生成・配置されている
- [ ] Host B の設定ファイルが作成されている
- [ ] Host B が Lighthouse に接続している（Lighthouse ログで確認）
  ```
  [INFO] Handshake received from 10.100.2.1
  ```
- [ ] Host B に Nebula IP が割り当てられている
  ```powershell
  ipconfig | findstr "10.100.2"
  ```

### Sub-stage 2.2: ホスト間通信確認

**内容:**
- Host A から Host B への ping テスト（Nebula IP 経由）
- Host B から Host A への ping テスト
- 双方向通信が確立されていることを確認

**テスト手順 (PowerShell):**

```powershell
# Host A から Host B へ ping
ping 10.100.2.1

# Host B から Host A へ ping
ping 10.100.1.1

# 接続状態の確認（Nebula 経由で traceroute）
tracert 10.100.2.1
```

**完了条件:**
- [ ] `ping 10.100.1.1`（Host A）が Host B から成功する
- [ ] `ping 10.100.2.1`（Host B）が Host A から成功する
- [ ] Lighthouse ログでホールパンチ成功が確認できる
  ```powershell
  Get-Content F:\flatnet\logs\nebula.log | Select-String "Hole punch"
  ```

### Sub-stage 2.3: WSL2 からの Nebula ネットワークアクセス

**内容:**
- Windows 上の Nebula インターフェースを経由して WSL2 から通信できるようにする
- 双方向のルーティングテーブル設定
- IP フォワーディング設定

**方式案:**
1. **Windows 側でルーティング**: WSL2 → Windows(Nebula) → 相手ホスト
2. **WSL2 内に Nebula**: WSL2 内でも Nebula クライアントを起動
3. **ブリッジ方式**: Windows と WSL2 間でブリッジ接続

**推奨: 方式 1**（Windows 側でルーティング）
- 理由: WSL2 内の設定を最小限に保てる

**双方向ルーティングの詳細:**
```
[WSL2 A] → [Windows A] → [Nebula tunnel] → [Windows B] → [WSL2 B]

必要な設定:
1. WSL2 A: デフォルトゲートウェイ経由で Windows A へ
2. Windows A: Nebula 経由で Host B の IP 範囲へ転送
3. Windows A: IP フォワーディング有効化
4. Windows B: 受信パケットを WSL2 B へ転送
5. 戻りパケットも同様に逆経路を設定
```

**完了条件:**
- [ ] WSL2 から相手ホストの Nebula IP に ping が通る
  ```bash
  # WSL2 から実行
  ping -c 4 10.100.2.1
  ```
- [ ] 相手ホストの WSL2 から自ホストの Nebula IP に ping が通る
- [ ] IP フォワーディングが有効化されている
  ```powershell
  # Windows で確認
  Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter"
  # 期待: IPEnableRouter = 1
  ```

### Sub-stage 2.4: 追加ホストの接続手順確立

**内容:**
- 3台目以降のホストを追加する手順を文書化
- 証明書生成のスクリプト化（オプション）
- 設定テンプレートの作成

**ホスト追加チェックリスト:**

1. **Lighthouse で証明書生成**
   - ホスト名と IP を決定（例: host-c, 10.100.3.1）
   - `nebula-cert sign` で証明書を生成
   - 証明書をセキュアに転送

2. **新規ホストのセットアップ**
   - `F:\flatnet\` ディレクトリ構成を作成
   - Nebula バイナリを配置
   - 証明書と ca.crt を配置
   - config.yaml を作成（Lighthouse IP を設定）
   - Windows Firewall ルールを追加
   - NSSM でサービス登録

3. **接続確認**
   - Nebula サービス起動
   - Lighthouse ログで接続確認
   - 他ホストとの ping テスト

**完了条件:**
- [ ] ホスト追加手順書が完成している
- [ ] 手順書に従って 3台目のホストを追加できることを確認
- [ ] チェックリストがドキュメント化されている

## 成果物

| 種別 | パス | 説明 |
|------|------|------|
| 証明書 | `F:\flatnet\config\nebula\host.crt` | 各ホスト固有 |
| 秘密鍵 | `F:\flatnet\config\nebula\host.key` | 各ホスト固有 |
| 設定 | `F:\flatnet\config\nebula\config.yaml` | 各ホスト固有 |
| スクリプト | `F:\flatnet\scripts\setup-routing.ps1` | ルーティング設定 |
| WSLスクリプト | `/home/kh/prj/flatnet/scripts/wsl-routing.sh` | WSL2 ルーティング |

**ドキュメント成果物:**
- ホスト追加手順書（Sub-stage 2.4 に記載）
- 設定ファイルテンプレート（技術メモに記載）

## 完了条件

- [ ] 2台以上のホストが Nebula トンネルで接続されている
- [ ] ホスト間で相互に ping が通る
- [ ] 各ホストの WSL2 から相手ホストに通信できる
- [ ] 追加ホストの接続手順が文書化されている

## 技術メモ

### Windows → WSL2 ルーティング設定

```powershell
# WSL2 の IP アドレスを取得
$wslIp = (wsl hostname -I).Trim().Split()[0]

# Windows 側でルーティング設定
# WSL2 内のコンテナ宛てトラフィックを WSL2 に転送
route add 10.100.0.0 mask 255.255.0.0 $wslIp

# IP フォワーディングを有効化（管理者権限で実行）
# レジストリで永続化
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -Value 1

# 即時有効化（再起動まで）
netsh interface ipv4 set interface "vEthernet (WSL)" forwarding=enabled
netsh interface ipv4 set interface "Nebula" forwarding=enabled
```

### WSL2 側のルーティング設定

```bash
# Windows (Nebula) 経由で他ホストへ
# Windows の vEthernet (WSL) 側 IP を確認
WINDOWS_IP=$(ip route | grep default | awk '{print $3}')

# 他ホストの IP 範囲への経路を追加
sudo ip route add 10.100.2.0/24 via $WINDOWS_IP
sudo ip route add 10.100.3.0/24 via $WINDOWS_IP
```

### Nebula クライアント設定例（Windows）

```yaml
# F:\flatnet\config\nebula\config.yaml
pki:
  ca: F:/flatnet/config/nebula/ca.crt
  cert: F:/flatnet/config/nebula/host.crt
  key: F:/flatnet/config/nebula/host.key

lighthouse:
  am_lighthouse: false
  hosts:
    - "<Lighthouse の社内LAN IP>:4242"

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
      group: flatnet
```

**注意:** Windows ではパス区切りにスラッシュ（`/`）を使用。

### NAT 越えの確認

Nebula はホールパンチングにより NAT 越えを試みる。成功すると直接通信、失敗すると Lighthouse 経由（リレー）となる。

```
# ログで確認
[INFO] Handshake received from 10.100.2.1
[INFO] Hole punch established with 10.100.2.1
```

## 依存関係

- Stage 1: Nebula Lighthouse 導入

## リスク

- WSL2 の IP アドレス変更時にルーティングが壊れる
  - 対策: 起動時にルーティングを再設定するスクリプト
- NAT が厳しい環境でホールパンチが失敗する
  - 対策: Lighthouse リレー機能を有効化

## 次のステップ

Stage 2 完了後は [Stage 3: CNI Plugin マルチホスト拡張](./stage-3-cni-multihost.md) に進み、CNI Plugin をマルチホスト対応に拡張する。
