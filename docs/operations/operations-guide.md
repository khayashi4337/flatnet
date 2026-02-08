# Flatnet Operations Guide

このドキュメントでは、Flatnet の日常運用タスクについて説明します。

## 目次

1. [日常運用タスク](#日常運用タスク)
2. [ホスト管理](#ホスト管理)
3. [証明書管理](#証明書管理)
4. [コンテナ管理](#コンテナ管理)
5. [Gateway 管理](#gateway-管理)
6. [監視とログ](#監視とログ)
7. [バックアップと復旧](#バックアップと復旧)

---

## 日常運用タスク

### 毎日のヘルスチェック

```powershell
# Windows (各ホストで実行)

# 1. Nebula サービス確認
Get-Service Nebula

# 2. OpenResty 確認
Get-Process nginx -ErrorAction SilentlyContinue

# 3. API ヘルスチェック
curl http://10.100.1.1:8080/api/health
```

```bash
# WSL2 で実行

# 4. コンテナ状態確認
sudo podman ps --filter "network=flatnet"

# 5. ブリッジ状態確認
ip addr show flatnet-br0

# 6. IP フォワーディング確認
sysctl net.ipv4.ip_forward
```

### 週次タスク

1. **ログローテーション確認**
   ```powershell
   # ログサイズ確認
   Get-ChildItem F:\flatnet\logs\ | Format-Table Name, Length
   ```

2. **証明書有効期限確認**
   ```powershell
   cd F:\flatnet\nebula
   .\nebula-cert.exe print -path F:\flatnet\config\nebula\host.crt
   ```

3. **ディスク使用量確認**
   ```bash
   df -h /var/lib/flatnet
   sudo du -sh /var/lib/flatnet/*
   ```

### 月次タスク

1. **セキュリティアップデート確認**
2. **パフォーマンスレポート生成**
3. **バックアップの検証**

---

## ホスト管理

### 新規ホストの追加

#### Step 1: 証明書生成 (Lighthouse で実行)

```powershell
cd F:\flatnet\nebula

# 新規ホスト用の証明書を生成
# IP は連番で割り当て: 10.100.3.1, 10.100.4.1, ...
.\nebula-cert.exe sign `
    -name "host-new" `
    -ip "10.100.3.1/16" `
    -groups "flatnet,gateway" `
    -ca-crt F:\flatnet\config\nebula\ca.crt `
    -ca-key F:\flatnet\config\nebula\ca.key
```

#### Step 2: ファイル転送

安全な方法で以下を新規ホストに転送:
- `ca.crt`
- `host-new.crt` → `host.crt` にリネーム
- `host-new.key` → `host.key` にリネーム

#### Step 3: 新規ホストセットアップ

[Setup Guide](setup-guide.md) の「ホストセットアップ」セクションを参照。

#### Step 4: 他ホストへの通知

Gateway 同期が設定されている場合、新規ホストは自動的に認識されます。
手動で追加する場合:

```bash
# 各ホストの OpenResty 設定を更新
# peers に新規ホストを追加
```

### ホストの削除

#### Step 1: コンテナの移行

```bash
# 削除対象ホストのコンテナを確認
sudo podman ps --filter "network=flatnet"

# 必要なコンテナを他ホストに移行
```

#### Step 2: サービス停止

```powershell
# 削除対象ホストで実行
Stop-Service Nebula
Stop-Service OpenResty
```

#### Step 3: 証明書の無効化

現在、Nebula は CRL (Certificate Revocation List) をサポートしていません。
対策:
- 証明書の有効期限を短く設定する
- CA 鍵を更新して全証明書を再発行する（大規模変更）

#### Step 4: 他ホストの設定から削除

```bash
# peers リストから削除したホストを除去
# Gateway 同期設定を更新
```

### ホストの一時停止

メンテナンス等で一時的にホストを停止する場合:

```powershell
# 1. コンテナを停止
wsl sudo podman stop --all

# 2. OpenResty を停止
Stop-Service OpenResty

# 3. Nebula を停止 (他ホストへの影響を確認)
Stop-Service Nebula
```

再開時:

```powershell
# 1. Nebula を開始
Start-Service Nebula

# 2. OpenResty を開始
Start-Service OpenResty

# 3. WSL2 設定を再適用
wsl sudo /home/kh/prj/flatnet/scripts/wsl2/setup-forwarding.sh

# 4. コンテナを開始
wsl sudo podman start --all
```

---

## 証明書管理

### 証明書の有効期限確認

```powershell
cd F:\flatnet\nebula

# 全証明書を確認
.\nebula-cert.exe print -path F:\flatnet\config\nebula\ca.crt
.\nebula-cert.exe print -path F:\flatnet\config\nebula\host.crt
```

### 証明書の更新

#### ホスト証明書の更新

証明書の有効期限が近づいたら (30日前を推奨):

```powershell
# Lighthouse で実行
cd F:\flatnet\nebula

# 新しい証明書を生成 (同じ IP/名前で)
.\nebula-cert.exe sign `
    -name "host-a" `
    -ip "10.100.1.1/16" `
    -groups "flatnet,gateway" `
    -ca-crt F:\flatnet\config\nebula\ca.crt `
    -ca-key F:\flatnet\config\nebula\ca.key

# 対象ホストに配布
# host-a.crt → host.crt, host-a.key → host.key

# 対象ホストで Nebula を再起動
Restart-Service Nebula
```

#### CA 証明書の更新

CA の更新は大きな作業です。計画的に実施してください。

```powershell
# 1. 新しい CA を生成
.\nebula-cert.exe ca -name "flatnet-ca-v2" -duration 8760h

# 2. 全ホストの証明書を新しい CA で再生成

# 3. 移行期間を設けて段階的に入れ替え
#    - 新旧両方の CA を信頼する設定が可能

# 4. 全ホストが新 CA に移行後、旧 CA を削除
```

### 証明書のバックアップ

**重要:** CA 秘密鍵 (`ca.key`) は厳重に管理してください。

```powershell
# CA 鍵のバックアップ (暗号化推奨)
# 安全なオフライン場所に保管

# 証明書一覧のエクスポート
Get-ChildItem F:\flatnet\config\nebula\*.crt |
    ForEach-Object {
        F:\flatnet\nebula\nebula-cert.exe print -path $_.FullName
    } > F:\flatnet\backups\certificates.txt
```

---

## コンテナ管理

### コンテナの起動

```bash
# Flatnet ネットワークでコンテナを起動
sudo podman run -d \
    --name my-service \
    --network flatnet \
    my-image:latest

# IP 確認
sudo podman inspect my-service | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress'
```

### コンテナの移行

ホスト間でコンテナを移行する場合:

```bash
# 1. 元ホストでイメージをエクスポート
sudo podman save my-image:latest | gzip > my-image.tar.gz

# 2. 新ホストに転送
scp my-image.tar.gz user@new-host:~/

# 3. 新ホストでインポート
gunzip -c my-image.tar.gz | sudo podman load

# 4. 新ホストでコンテナ起動
sudo podman run -d --name my-service --network flatnet my-image:latest

# 5. 元ホストでコンテナ削除
sudo podman rm -f my-service
```

### コンテナの一括管理

```bash
# 全 Flatnet コンテナの状態確認
sudo podman ps -a --filter "network=flatnet" --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}"

# 全コンテナの再起動
sudo podman restart $(sudo podman ps -q --filter "network=flatnet")

# 停止中のコンテナを削除
sudo podman rm $(sudo podman ps -aq --filter "network=flatnet" --filter "status=exited")
```

---

## Gateway 管理

### 設定のリロード

```powershell
# 設定テスト
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t

# 設定リロード (ダウンタイムなし)
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -s reload
```

### ピアの追加・削除

OpenResty の Lua 設定でピアを管理:

```lua
-- F:\flatnet\config\lualib\flatnet\sync.lua または
-- API 経由で動的に追加

-- ピア追加
sync.add_peer("http://10.100.3.1:8080")

-- ピア削除
sync.remove_peer("http://10.100.3.1:8080")
```

### 同期状態の確認

```bash
# API 経由で確認
curl http://10.100.1.1:8080/api/sync/status | jq

# 応答例:
# {
#   "host_id": "1",
#   "peer_count": 2,
#   "peers": ["http://10.100.2.1:8080", "http://10.100.3.1:8080"],
#   "local_containers": 5
# }
```

### Escalation 状態の管理

```bash
# 全状態を確認
curl http://10.100.1.1:8080/api/escalation/states | jq

# 特定 IP の状態をリセット
curl -X POST "http://10.100.1.1:8080/api/escalation/reset?ip=10.100.2.10"

# 統計情報
curl http://10.100.1.1:8080/api/escalation/stats | jq
```

---

## 監視とログ

### ログの場所

| コンポーネント | パス |
|----------------|------|
| Nebula | `F:\flatnet\logs\nebula.log` |
| OpenResty access | `F:\flatnet\logs\access.log` |
| OpenResty error | `F:\flatnet\logs\error.log` |
| CNI Plugin | syslog / journalctl |
| Podman | `journalctl -u podman` |

### ログの確認

```powershell
# Nebula ログ (最新 50 行)
Get-Content F:\flatnet\logs\nebula.log -Tail 50

# OpenResty エラーログ
Get-Content F:\flatnet\logs\error.log -Tail 50

# 特定のパターンを検索
Select-String -Path F:\flatnet\logs\nebula.log -Pattern "handshake"
```

```bash
# CNI ログ
sudo grep -i cni /var/log/syslog | tail -20

# Podman ログ
journalctl -u podman --since "1 hour ago"
```

### アラート設定 (推奨)

監視すべき項目:
- Nebula サービスのダウン
- OpenResty の 5xx エラー増加
- ディスク使用量
- 証明書の有効期限

---

## バックアップと復旧

### バックアップ対象

| 項目 | パス | 重要度 |
|------|------|--------|
| CA 証明書・鍵 | `F:\flatnet\config\nebula\ca.*` | 最重要 |
| ホスト証明書 | `F:\flatnet\config\nebula\host.*` | 高 |
| Nebula 設定 | `F:\flatnet\config\nebula\config.yaml` | 中 |
| OpenResty 設定 | `F:\flatnet\config\` | 中 |
| IPAM データ | `/var/lib/flatnet/ipam/` | 低 (再生成可能) |

### バックアップスクリプト

```powershell
# backup-flatnet.ps1
$backupDir = "F:\flatnet\backups\$(Get-Date -Format 'yyyy-MM-dd')"
New-Item -ItemType Directory -Path $backupDir -Force

# 証明書のバックアップ
Copy-Item F:\flatnet\config\nebula\*.crt $backupDir\
Copy-Item F:\flatnet\config\nebula\*.key $backupDir\
Copy-Item F:\flatnet\config\nebula\config.yaml $backupDir\

# 設定のバックアップ
Copy-Item -Recurse F:\flatnet\config\conf.d $backupDir\
Copy-Item -Recurse F:\flatnet\config\lualib $backupDir\

Write-Host "Backup completed: $backupDir"
```

### 復旧手順

1. **Nebula の復旧**
   ```powershell
   # 証明書を復元
   Copy-Item $backupDir\*.crt F:\flatnet\config\nebula\
   Copy-Item $backupDir\*.key F:\flatnet\config\nebula\
   Copy-Item $backupDir\config.yaml F:\flatnet\config\nebula\

   # サービス再起動
   Restart-Service Nebula
   ```

2. **OpenResty の復旧**
   ```powershell
   # 設定を復元
   Copy-Item -Recurse $backupDir\conf.d F:\flatnet\config\
   Copy-Item -Recurse $backupDir\lualib F:\flatnet\config\

   # 設定テスト
   F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t

   # 再起動
   Restart-Service OpenResty
   ```

3. **CNI Plugin の復旧**
   ```bash
   # プラグインの再インストール
   cd /home/kh/prj/flatnet/src/flatnet-cni
   cargo build --release
   sudo cp target/release/flatnet /opt/cni/bin/
   ```

---

## クイックリファレンス

### よく使うコマンド

| 操作 | コマンド |
|------|----------|
| サービス状態確認 | `Get-Service Nebula, OpenResty` |
| ログ確認 | `Get-Content F:\flatnet\logs\error.log -Tail 50` |
| API ヘルス確認 | `curl http://10.100.1.1:8080/api/health` |
| 設定リロード | `nginx.exe -c ... -s reload` |
| コンテナ一覧 | `sudo podman ps --filter "network=flatnet"` |
| 証明書確認 | `nebula-cert.exe print -path host.crt` |

---

## 関連ドキュメント

- [Setup Guide](setup-guide.md) - 初期セットアップ
- [Troubleshooting](troubleshooting.md) - 問題解決
- [CNI Operations](cni-operations.md) - CNI 詳細運用
