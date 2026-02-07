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

## 手段

- 各ホスト用の証明書を生成
- 各ホストに Nebula をインストール・設定
- WSL2 へのルーティング設定

## Sub-stages

### Sub-stage 2.1: Host B 証明書生成と接続

**内容:**
- Host B 用の証明書を生成（例: `10.100.2.1`）
- Host B に Nebula をインストール
- `config.yaml` を設定して Lighthouse に接続

**完了条件:**
- [ ] Host B が Lighthouse に接続している（ログで確認）
- [ ] Host B に Nebula IP が割り当てられている

### Sub-stage 2.2: ホスト間通信確認

**内容:**
- Host A から Host B への ping テスト（Nebula IP 経由）
- Host B から Host A への ping テスト
- 双方向通信が確立されていることを確認

**完了条件:**
- [ ] `ping 10.100.1.1`（Host A）が Host B から成功する
- [ ] `ping 10.100.2.1`（Host B）が Host A から成功する
- [ ] Lighthouse ログでホールパンチ成功が確認できる

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
- [ ] 相手ホストの WSL2 から自ホストの Nebula IP に ping が通る
- [ ] IP フォワーディングが有効化されている

### Sub-stage 2.4: 追加ホストの接続手順確立

**内容:**
- 3台目以降のホストを追加する手順を文書化
- 証明書生成のスクリプト化（オプション）
- 設定テンプレートの作成

**完了条件:**
- [ ] ホスト追加手順書が完成している
- [ ] 手順書に従って 3台目のホストを追加できることを確認

## 成果物

- 各ホスト用証明書
- Nebula 設定ファイルテンプレート
- WSL2 ルーティング設定スクリプト
- ホスト追加手順書

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

### Nebula クライアント設定例

```yaml
pki:
  ca: /etc/nebula/ca.crt
  cert: /etc/nebula/host.crt
  key: /etc/nebula/host.key

lighthouse:
  am_lighthouse: false
  hosts:
    - "lighthouse-ip:4242"

listen:
  host: 0.0.0.0
  port: 4242

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
