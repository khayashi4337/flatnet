# Flatnet Troubleshooting Guide

このドキュメントでは、Flatnet の運用中に発生しうる問題とその解決方法を説明します。

## 目次

1. [ネットワーク接続の問題](#ネットワーク接続の問題)
2. [CNI プラグインの問題](#cni-プラグインの問題)
3. [OpenResty/Gateway の問題](#openrestygateway-の問題)
4. [コンテナライフサイクルの問題](#コンテナライフサイクルの問題)
5. [診断コマンド一覧](#診断コマンド一覧)

---

## ネットワーク接続の問題

### 症状: Windows から 10.87.1.x に ping できない

**原因候補:**
1. Windows のルートが設定されていない
2. WSL2 の IP フォワーディングが無効
3. iptables FORWARD チェーンがブロック
4. ブリッジが存在しない

**診断:**

```powershell
# Windows: ルート確認
route print | Select-String "10.87.1"

# Windows: WSL2 IP 確認
wsl hostname -I
```

```bash
# WSL2: IP フォワーディング確認
sysctl net.ipv4.ip_forward

# WSL2: ブリッジ確認
ip addr show flatnet-br0

# WSL2: iptables 確認
sudo iptables -L FORWARD -n -v | head -10
```

**解決:**

```powershell
# Windows: ルート再設定
F:\flatnet\scripts\setup-route.ps1 -Verify
```

```bash
# WSL2: フォワーディング有効化
sudo ./scripts/wsl2/setup-forwarding.sh --persist
```

---

### 症状: コンテナから外部（インターネット）に接続できない

**原因候補:**
1. NAT/マスカレードが設定されていない
2. DNS が解決できない

**診断:**

```bash
# コンテナ内から
sudo podman exec <container> ping -c 1 8.8.8.8
sudo podman exec <container> nslookup google.com
```

**解決:**

```bash
# NAT 設定追加（Flatnet は主に内部通信用だが、外部接続が必要な場合）
sudo iptables -t nat -A POSTROUTING -s 10.87.1.0/24 ! -d 10.87.1.0/24 -j MASQUERADE
```

---

### 症状: コンテナ間で通信できない

**原因候補:**
1. コンテナが異なるネットワークに接続
2. ブリッジの設定問題

**診断:**

```bash
# 両方のコンテナが flatnet ネットワークにいるか確認
sudo podman inspect <container1> | jq '.[0].NetworkSettings.Networks'
sudo podman inspect <container2> | jq '.[0].NetworkSettings.Networks'

# ブリッジの状態確認
bridge link show
```

**解決:**

```bash
# コンテナを flatnet に接続
sudo podman network connect flatnet <container>
```

---

## CNI プラグインの問題

### 症状: コンテナ起動時に "CNI plugin failed" エラー

**原因候補:**
1. CNI プラグインバイナリが存在しない
2. 実行権限がない
3. 設定ファイルの構文エラー

**診断:**

```bash
# バイナリ確認
ls -la /opt/cni/bin/flatnet

# 手動で CNI 実行テスト
echo '{"cniVersion":"1.0.0","name":"flatnet","type":"flatnet"}' | \
  CNI_COMMAND=VERSION CNI_PATH=/opt/cni/bin /opt/cni/bin/flatnet
```

**解決:**

```bash
# バイナリ再インストール
cd /home/kh/prj/flatnet/src/flatnet-cni
cargo build --release
sudo cp target/release/flatnet /opt/cni/bin/
sudo chmod +x /opt/cni/bin/flatnet
```

---

### 症状: IP アドレスが割り当てられない

**原因候補:**
1. IPAM 設定が不正
2. IP アドレス枯渇
3. allocations.json の破損

**診断:**

```bash
# IPAM 状態確認
cat /var/lib/flatnet/ipam/allocations.json | jq .

# 割り当て済み IP 数
jq '.allocations | length' /var/lib/flatnet/ipam/allocations.json
```

**解決:**

```bash
# 使用されていない IP の解放（古いエントリの削除）
# 注意: 実行中のコンテナの IP を削除しないこと
sudo vim /var/lib/flatnet/ipam/allocations.json

# または、完全リセット（全コンテナ停止後）
sudo rm /var/lib/flatnet/ipam/allocations.json
```

---

### 症状: ブリッジが作成されない

**原因候補:**
1. root 権限で実行していない
2. iproute2 パッケージがない

**診断:**

```bash
# bridge コマンド確認
which bridge
ip link show type bridge
```

**解決:**

```bash
# 手動でブリッジ作成
sudo ip link add flatnet-br0 type bridge
sudo ip addr add 10.87.1.1/24 dev flatnet-br0
sudo ip link set flatnet-br0 up
```

---

## OpenResty/Gateway の問題

### 症状: 502 Bad Gateway

**原因候補:**
1. upstream の IP が間違っている
2. コンテナが起動していない
3. Windows から WSL2 への接続問題

**診断:**

```powershell
# エラーログ確認
Get-Content F:\flatnet\logs\error.log -Tail 30

# upstream への直接アクセス
curl http://10.87.1.2:3000/
```

**解決:**

1. コンテナの IP を確認:
   ```bash
   sudo podman inspect forgejo | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress'
   ```

2. flatnet.conf の upstream を更新:
   ```nginx
   upstream flatnet_forgejo {
       server 10.87.1.X:3000;  # 実際の IP に更新
   }
   ```

3. OpenResty リロード:
   ```powershell
   F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -s reload
   ```

---

### 症状: OpenResty が起動しない

**原因候補:**
1. 設定ファイルの構文エラー
2. ポートが使用中
3. パスが間違っている

**診断:**

```powershell
# 設定テスト
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t

# ポート確認
netstat -an | Select-String ":80 "
```

**解決:**

```powershell
# 他のプロセスを停止してから起動
Stop-Process -Name nginx -Force -ErrorAction SilentlyContinue
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf
```

---

## コンテナライフサイクルの問題

### 症状: コンテナ再起動後に IP が変わる

**説明:** これは正常な動作です。Flatnet の IPAM は動的 IP 割り当てを使用しています。

**対応:**
- 固定 IP が必要な場合は、コンテナ起動後に OpenResty の upstream を更新
- 将来的に固定 IP 機能を追加予定

---

### 症状: 削除したコンテナの IP が解放されない

**原因候補:**
1. podman rm が正常に完了しなかった
2. CNI DEL が呼ばれなかった

**診断:**

```bash
# 実行中のコンテナ確認
sudo podman ps -a

# IPAM 状態確認
cat /var/lib/flatnet/ipam/allocations.json | jq .
```

**解決:**

```bash
# 孤児エントリを手動削除
sudo vim /var/lib/flatnet/ipam/allocations.json
# 存在しないコンテナ ID のエントリを削除
```

---

### 症状: WSL2 再起動後に設定が消える

**原因候補:**
1. sysctl 設定が永続化されていない
2. iptables 設定が永続化されていない
3. Windows のルートが一時的

**解決:**

WSL2 側:
```bash
# 設定の永続化
sudo ./scripts/wsl2/setup-forwarding.sh --persist
```

Windows 側:
```powershell
# 毎回実行が必要（または起動時タスクに登録）
F:\flatnet\scripts\setup-route.ps1
```

---

## 診断コマンド一覧

### ネットワーク状態

```bash
# ブリッジ状態
ip addr show flatnet-br0
bridge link show

# IP フォワーディング
sysctl net.ipv4.ip_forward

# iptables
sudo iptables -L -n -v
sudo iptables -t nat -L -n -v
```

### CNI/IPAM 状態

```bash
# IPAM 割り当て
cat /var/lib/flatnet/ipam/allocations.json | jq .

# CNI テスト
./scripts/test-cni.sh
```

### コンテナ状態

```bash
# Flatnet コンテナ一覧
sudo podman ps --filter "network=flatnet"

# コンテナ詳細
sudo podman inspect <container> | jq '.[0].NetworkSettings'
```

### Gateway 状態

```powershell
# OpenResty プロセス
Get-Process nginx

# ログ確認
Get-Content F:\flatnet\logs\error.log -Tail 50
Get-Content F:\flatnet\logs\access.log -Tail 50

# 設定テスト
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t
```

### 統合テスト

```bash
# フルテスト
sudo ./scripts/test-integration.sh

# クイックテスト
sudo ./scripts/test-integration.sh --quick
```

---

## ログの場所

| ログ | パス |
|------|------|
| OpenResty error | `F:\flatnet\logs\error.log` |
| OpenResty access | `F:\flatnet\logs\access.log` |
| CNI debug | syslog または journalctl |
| Podman | `journalctl -u podman` |

---

## サポート

問題が解決しない場合:
1. 上記の診断コマンドの出力を収集
2. エラーログを確認
3. プロジェクトの Issue として報告

## 関連ドキュメント

- [Setup Guide](setup-guide.md) - 初期セットアップ手順
- [Operations Guide](operations-guide.md) - 日常運用タスク
- [Phase 2 Setup Guide](../setup/phase-2-setup.md) - Phase 2 セットアップ
- [CNI Operations Guide](cni-operations.md) - CNI 詳細運用
