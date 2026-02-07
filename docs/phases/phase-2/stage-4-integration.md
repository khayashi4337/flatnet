# Stage 4: Podman統合とGateway連携

## 概要

Phase 1 で構築した Gateway（OpenResty）と Phase 2 の CNI プラグインを連携させ、エンドツーエンドでの動作を確認する。社内メンバーがブラウザから Flatnet IP のコンテナにアクセスできる状態を完成させる。

## ブランチ戦略

- ブランチ名: `phase2/stage-4-integration`
- マージ先: `master`

## インプット（前提条件）

- Stage 3 完了（ネットワーク設定が動作）
- Phase 1 完了（Gateway が動作している）
- コンテナに Flatnet IP が割り当て可能
- ホスト-コンテナ間の通信が可能

**前提条件の確認:**

WSL2 側:
```bash
# Stage 3 確認
ip addr show flatnet-br0 | grep -q "10.87.1.1" && echo "[OK] Bridge"
podman run -d --name prereq-test --network flatnet nginx:alpine 2>/dev/null
IP=$(podman inspect prereq-test 2>/dev/null | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress')
ping -c 1 -W 2 $IP >/dev/null 2>&1 && echo "[OK] Container reachable: $IP" || echo "[NG] Container not reachable"
podman rm -f prereq-test >/dev/null 2>&1
```

Windows 側 (PowerShell):
```powershell
# Phase 1 確認
(Invoke-WebRequest -Uri http://localhost/health -TimeoutSec 5).Content
# 期待出力: OK
```

## 目標

1. Gateway から Flatnet IP のコンテナに HTTP アクセスできる
2. 複数コンテナの同時運用ができる
3. コンテナのライフサイクル（起動/停止/再起動）が正常に動作
4. エラーケースの処理が適切
5. 運用に必要なドキュメントが整備される

## 手段

### エンドツーエンド構成

```
[社内 LAN: ブラウザ]
    │
    ▼ HTTP :80
[Windows: OpenResty Gateway]
    │
    ▼ proxy_pass http://10.87.1.x:port
[WSL2: flatnet-br0]
    │
    ▼ veth pair
[Container: 10.87.1.x]
```

---

## Sub-stages

### Sub-stage 4.1: Windows-WSL2 ルーティング設定

**内容:**
- Windows から WSL2 内の Flatnet サブネット（10.87.1.0/24）への経路設定
- WSL2 の IP フォワーディング有効化
- iptables/nftables 設定（必要に応じて）

**Windows 側設定 (PowerShell 管理者):**
```powershell
# WSL2 の IP を取得
$wsl_ip = (wsl hostname -I).Trim().Split()[0]
Write-Host "WSL2 IP: $wsl_ip"

# Flatnet サブネットへのルート追加
route add 10.87.1.0 mask 255.255.255.0 $wsl_ip
# 期待出力: OK!

# ルート確認
route print | Select-String "10.87.1.0"
```

**ルートの永続化スクリプト:**

WSL2 の IP は再起動で変わるため、起動時にルートを設定するスクリプトを作成:

ファイル: `F:\flatnet\scripts\setup-route.ps1`
```powershell
# Flatnet ルーティング設定スクリプト
# 管理者権限で実行が必要

$wsl_ip = (wsl hostname -I).Trim().Split()[0]
if (-not $wsl_ip) {
    Write-Error "WSL2 IP could not be determined. Is WSL running?"
    exit 1
}

Write-Host "WSL2 IP: $wsl_ip"

# 既存ルートを削除（エラーは無視）
route delete 10.87.1.0 2>$null

# 新しいルートを追加
route add 10.87.1.0 mask 255.255.255.0 $wsl_ip
if ($LASTEXITCODE -eq 0) {
    Write-Host "Route added successfully"
} else {
    Write-Error "Failed to add route"
    exit 1
}

# 疎通確認
Write-Host "Testing connectivity..."
ping -n 1 10.87.1.1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Ping to bridge (10.87.1.1) successful"
} else {
    Write-Warning "Ping to bridge failed - check WSL2 IP forwarding"
}
```

**WSL2 側設定:**
```bash
# IP フォワーディング有効化
sudo sysctl -w net.ipv4.ip_forward=1

# 永続化
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-flatnet.conf

# iptables 設定（FORWARD チェーンを許可）
sudo iptables -A FORWARD -i flatnet-br0 -j ACCEPT
sudo iptables -A FORWARD -o flatnet-br0 -j ACCEPT

# iptables 永続化（iptables-persistent パッケージが必要）
sudo apt-get install -y iptables-persistent
sudo netfilter-persistent save
```

**完了条件:**
- [ ] Windows から `ping 10.87.1.1`（ブリッジ）が通る
  ```powershell
  ping 10.87.1.1
  # 期待出力: Reply from 10.87.1.1: ...
  ```
- [ ] Windows から `ping 10.87.1.x`（コンテナ）が通る
  ```powershell
  # コンテナ起動後
  ping 10.87.1.2
  # 期待出力: Reply from 10.87.1.2: ...
  ```
- [ ] ルート設定スクリプトが `F:\flatnet\scripts\` に配置されている
  ```powershell
  Test-Path F:\flatnet\scripts\setup-route.ps1
  # 期待出力: True
  ```

---

### Sub-stage 4.2: OpenResty 設定更新

**内容:**
- Flatnet IP へのプロキシ設定
- 動的ルーティング（Lua）の検討
- ヘルスチェック設定

**設定ファイル更新:**

WSL2 側で設定を編集し、Windows 側にデプロイ:

ファイル: `/home/kh/prj/flatnet/config/openresty/conf.d/flatnet.conf`
```nginx
# Flatnet コンテナへのプロキシ設定

# Forgejo (例)
upstream flatnet_forgejo {
    server 10.87.1.2:3000;
}

server {
    listen 80;
    server_name forgejo.local;

    location / {
        proxy_pass http://flatnet_forgejo;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket サポート（Forgejo の一部機能で必要）
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# 汎用 Flatnet プロキシ（IP 直接指定）
server {
    listen 80;
    server_name ~^(?<container_ip>10\.87\.1\.\d+)\.flatnet\.local$;

    location / {
        resolver 127.0.0.1 valid=30s;
        set $backend "http://$container_ip:80";
        proxy_pass $backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

**nginx.conf の更新（conf.d を include）:**

ファイル: `/home/kh/prj/flatnet/config/openresty/nginx.conf` に追加:
```nginx
http {
    # ... 既存の設定 ...

    # Flatnet 設定を読み込み
    include F:/flatnet/config/conf.d/*.conf;
}
```

**デプロイ:**
```bash
# conf.d ディレクトリ作成（初回のみ）
mkdir -p /mnt/f/flatnet/config/conf.d

# WSL2 から Windows へデプロイ
cp -r /home/kh/prj/flatnet/config/openresty/* /mnt/f/flatnet/config/

# ファイル確認
ls -la /mnt/f/flatnet/config/
ls -la /mnt/f/flatnet/config/conf.d/

# 設定テスト（WSL2 から実行）
/mnt/f/flatnet/openresty/nginx.exe -c F:/flatnet/config/nginx.conf -t
# 期待出力: nginx: configuration file ... test is successful

# リロード（Windows 側で）
```

Windows 側 (PowerShell):
```powershell
# 設定リロード
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -s reload
```

**完了条件:**
- [ ] OpenResty から Flatnet IP のコンテナに接続できる
  ```powershell
  # Forgejo コンテナが起動している場合
  (Invoke-WebRequest -Uri http://forgejo.local/ -Headers @{Host="forgejo.local"}).StatusCode
  # 期待出力: 200
  ```
- [ ] HTTP リクエストが正しくプロキシされる
  ```bash
  # WSL2 から Windows 経由でコンテナにアクセス
  curl -H "Host: forgejo.local" http://$(hostname).local/
  ```
- [ ] 設定変更が nginx reload で反映される
  ```powershell
  F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -s reload
  # エラーが出なければ OK
  ```

---

### Sub-stage 4.3: 複数コンテナ運用テスト

**内容:**
- 複数コンテナの同時起動
- IP の競合がないことを確認
- コンテナ間通信のテスト
- リソース使用量の確認

**テストシナリオ:**
```bash
# 複数コンテナ起動（rootful Podman を使用）
sudo podman run -d --name web1 --network flatnet nginx:alpine
sudo podman run -d --name web2 --network flatnet nginx:alpine
sudo podman run -d --name db1 --network flatnet postgres:alpine

# IP 確認
sudo podman inspect web1 web2 db1 | jq '.[].NetworkSettings.Networks.flatnet.IPAddress'
# 期待出力:
# "10.87.1.2"
# "10.87.1.3"
# "10.87.1.4"

# IP を変数に格納
WEB1_IP=$(sudo podman inspect web1 | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress')
WEB2_IP=$(sudo podman inspect web2 | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress')
DB1_IP=$(sudo podman inspect db1 | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress')

# コンテナ間通信テスト
sudo podman exec web1 ping -c 3 $WEB2_IP
sudo podman exec web1 wget -q -O - http://$WEB2_IP/ | head -5

# クリーンアップ
sudo podman rm -f web1 web2 db1
```

**完了条件:**
- [ ] 3つ以上のコンテナが同時に動作する
- [ ] 各コンテナに異なる IP が割り当てられる
- [ ] コンテナ間で通信できる

---

### Sub-stage 4.4: ライフサイクルテスト

**内容:**
- コンテナの起動/停止/再起動
- IP の再利用
- 異常終了時のクリーンアップ
- CNI CHECK コマンドの動作確認

**テストシナリオ:**
```bash
# 通常ライフサイクル
sudo podman run -d --name lifecycle-test --network flatnet nginx:alpine
IP_BEFORE=$(sudo podman inspect lifecycle-test | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress')
echo "IP before stop: $IP_BEFORE"

sudo podman stop lifecycle-test
sudo podman start lifecycle-test
IP_AFTER=$(sudo podman inspect lifecycle-test | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress')
echo "IP after start: $IP_AFTER"

# IP が維持されているか確認
[ "$IP_BEFORE" = "$IP_AFTER" ] && echo "[OK] IP preserved" || echo "[INFO] IP changed (acceptable)"

sudo podman rm -f lifecycle-test

# 異常終了シミュレーション
sudo podman run -d --name crash-test --network flatnet nginx:alpine
CRASH_IP=$(sudo podman inspect crash-test | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress')
sudo podman kill crash-test

# IP が解放されているか確認
cat /var/lib/flatnet/ipam/allocations.json | jq '.allocations'
# crash-test の IP がまだ残っている場合は DEL コマンドの問題

sudo podman rm crash-test
cat /var/lib/flatnet/ipam/allocations.json | jq '.allocations'
# rm 後は IP が解放されているべき

# 再起動テスト
sudo podman run -d --name restart-test --network flatnet nginx:alpine
sudo podman restart restart-test
sudo podman exec restart-test ping -c 1 10.87.1.1 && echo "[OK] Network works after restart"
sudo podman rm -f restart-test
```

**完了条件:**
- [ ] 停止/開始で IP が維持される（または適切に再割り当て）
- [ ] 強制終了後もリソースリークがない
- [ ] 再起動が正常に動作する

---

### Sub-stage 4.5: エラーハンドリング強化

**内容:**
- IP 枯渇時の動作
- 不正な設定でのエラーメッセージ
- ログ出力の改善
- 診断用コマンドの追加

**対応すべきエラーケース:**
1. IP アドレス枯渇
2. ブリッジ作成失敗（権限不足等）
3. netns が存在しない
4. veth 作成失敗
5. 設定ファイルの構文エラー

**完了条件:**
- [ ] 各エラーケースで適切なエラーメッセージが出力される
- [ ] エラー時に中途半端なリソースが残らない
- [ ] ログから問題の原因が特定できる

---

### Sub-stage 4.6: ドキュメント整備

**内容:**
- セットアップ手順書
- トラブルシューティングガイド
- 運用手順書
- アーキテクチャ図の更新

**作成するドキュメント:**
1. `docs/setup/phase-2-setup.md` - セットアップ手順
2. `docs/operations/troubleshooting.md` - トラブルシューティング
3. `docs/operations/cni-operations.md` - CNI 運用手順

**完了条件:**
- [ ] 別の環境で手順書通りにセットアップできる
- [ ] よくある問題と解決方法が文書化されている
- [ ] コンポーネント図が Phase 2 の状態を反映している

---

## 成果物

### Windows 側 (F:\flatnet\)

| パス | 説明 |
|------|------|
| `F:\flatnet\scripts\setup-route.ps1` | ルーティング設定スクリプト |
| `F:\flatnet\config\conf.d\flatnet.conf` | Flatnet プロキシ設定 |

### WSL2 側 (Git 管理)

| パス | 説明 |
|------|------|
| `config/openresty/conf.d/flatnet.conf` | Flatnet プロキシ設定（正） |
| `scripts/test-integration.sh` | 統合テストスクリプト |
| `docs/setup/phase-2-setup.md` | セットアップ手順 |
| `docs/operations/troubleshooting.md` | トラブルシューティング |
| `docs/operations/cni-operations.md` | CNI 運用手順 |

## 完了条件

| 条件 | 確認方法 |
|------|----------|
| 社内 LAN からコンテナにアクセス | ブラウザで `http://forgejo.local/` |
| 複数コンテナが同時動作 | 3+ コンテナが稼働 |
| コンテナ起動/停止が正常 | `podman stop/start` が動作 |
| エラー時のメッセージ | 適切なログ出力 |
| セットアップ手順書 | 別環境で構築可能 |

**一括確認スクリプト:**

ファイル: `/home/kh/prj/flatnet/scripts/test-integration.sh`
```bash
#!/bin/bash
set -e
echo "=== Phase 2 Integration Test ==="
echo "注意: rootful Podman を使用（sudo が必要）"

# 1. コンテナ起動
echo "1. Starting test containers..."
sudo podman run -d --name integ-web1 --network flatnet nginx:alpine
sudo podman run -d --name integ-web2 --network flatnet nginx:alpine

sleep 3

# 2. IP 取得
IP1=$(sudo podman inspect integ-web1 | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress')
IP2=$(sudo podman inspect integ-web2 | jq -r '.[0].NetworkSettings.Networks.flatnet.IPAddress')
echo "Container IPs: $IP1, $IP2"

# 3. ホストからアクセス
echo "2. Testing host -> container..."
curl -s --connect-timeout 5 http://$IP1/ >/dev/null && echo "[OK] HTTP to $IP1" || echo "[NG] HTTP to $IP1"
curl -s --connect-timeout 5 http://$IP2/ >/dev/null && echo "[OK] HTTP to $IP2" || echo "[NG] HTTP to $IP2"

# 4. コンテナ間通信
echo "3. Testing container -> container..."
sudo podman exec integ-web1 wget -q -O /dev/null --timeout=5 http://$IP2/ && echo "[OK] Container inter-communication" || echo "[NG] Container inter-communication"

# 5. クリーンアップ
echo "4. Cleanup..."
sudo podman rm -f integ-web1 integ-web2

echo "=== Done ==="
```

## Phase 2 完了チェックリスト

Phase 2 全体としての完了を確認:

- [ ] **機能要件**
  - [ ] `podman run --network flatnet` でコンテナが起動する
  - [ ] コンテナに Flatnet IP が割り当てられる
  - [ ] Gateway からコンテナに HTTP アクセスできる
  - [ ] 社内メンバーがブラウザからアクセスできる

- [ ] **非機能要件**
  - [ ] コンテナ起動時間への影響が許容範囲（+1秒以内）
  - [ ] メモリリークがない
  - [ ] ログが適切に出力される

- [ ] **運用要件**
  - [ ] セットアップ手順書が存在する
  - [ ] トラブルシューティングガイドが存在する
  - [ ] Phase 3 への拡張ポイントが明確

## 次のフェーズ（Phase 3）への接続点

Phase 3（マルチホスト対応）で拡張が必要な箇所:

1. **IPAM**: ホスト間での IP 重複を避ける仕組み
2. **ルーティング**: 他ホストの Flatnet サブネットへの経路
3. **ブリッジ → オーバーレイ**: Nebula トンネルとの連携
4. **Lighthouse 連携**: ノード登録と発見

これらの拡張点を意識した設計になっていることを確認する。

## トラブルシューティング

### Windows から 10.87.1.x に ping できない

**症状:** route add は成功したが ping がタイムアウト

**対処:**
```powershell
# ルートが正しく設定されているか確認
route print | Select-String "10.87.1"

# WSL2 の IP が正しいか確認
wsl hostname -I

# WSL2 側で IP フォワーディングが有効か確認
wsl sysctl net.ipv4.ip_forward
# 0 の場合は有効化: wsl sudo sysctl -w net.ipv4.ip_forward=1

# WSL2 側の iptables FORWARD チェーンを確認
wsl sudo iptables -L FORWARD -n
# DROP がデフォルトの場合は許可ルールを追加
```

### OpenResty からコンテナに接続できない

**症状:** 502 Bad Gateway

**対処:**
```powershell
# Windows からコンテナ IP に直接アクセスできるか確認
curl http://10.87.1.2:3000/

# OpenResty のエラーログ確認
Get-Content F:\flatnet\logs\error.log -Tail 20

# upstream が正しい IP を指しているか確認
# nginx.conf の upstream 設定を確認

# DNS 解決の問題がある場合は resolver を設定
```

### WSL2 再起動後にルートが消える

**症状:** Windows 再起動または WSL2 シャットダウン後にルートがなくなる

**対処:**
```powershell
# setup-route.ps1 を実行
F:\flatnet\scripts\setup-route.ps1

# タスクスケジューラで自動実行を設定（オプション）
# - トリガー: ログオン時
# - 操作: powershell.exe -ExecutionPolicy Bypass -File F:\flatnet\scripts\setup-route.ps1
```

### hosts ファイルの設定

社内 LAN から `forgejo.local` でアクセスするには、クライアント PC の hosts ファイルを設定:

Windows クライアント:
```
# C:\Windows\System32\drivers\etc\hosts に追加
192.168.x.x  forgejo.local
# 192.168.x.x は Flatnet Gateway (OpenResty) が動作している Windows の IP
```

または、社内 DNS サーバーで設定する方法もある。

## 参考リンク

- [OpenResty Documentation](https://openresty.org/en/docs/)
- [WSL2 Networking](https://learn.microsoft.com/en-us/windows/wsl/networking)
- [Podman Network Commands](https://docs.podman.io/en/latest/markdown/podman-network.1.html)
- [Windows route コマンド](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/route_ws2008)
