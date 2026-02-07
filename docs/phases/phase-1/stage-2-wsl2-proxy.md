# Stage 2: WSL2 プロキシ設定

## 概要

OpenResty から WSL2 内のサービスへ HTTP リクエストをプロキシする仕組みを構築する。WSL2 の IP アドレス管理方法も確立する。

## ブランチ戦略

- ブランチ名: `phase1/stage-2-wsl2-proxy`
- マージ先: `master`

## インプット（前提条件）

- Stage 1 完了（OpenResty が Windows 上で動作している）
- WSL2 (Ubuntu 24.04) がインストール済み
- WSL2 内でテスト用 HTTP サーバーが起動可能（Python http.server 等）

## 目標

- WSL2 の IP アドレスを安定して取得できる
- OpenResty から WSL2 内サービスへプロキシできる
- WSL2 IP 変更時の対応方法を確立する

## 手段

- WSL2 の IP アドレス取得スクリプトを作成
- nginx.conf に upstream と proxy_pass を設定
- Lua による動的 IP 解決を検討

## Sub-stages

### Sub-stage 2.1: WSL2 IP 取得方法の確立

**内容:**
- WSL2 内から IP を取得するコマンドの確認
  ```bash
  ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1
  ```
- Windows 側から WSL2 IP を取得する方法
  ```powershell
  wsl hostname -I
  ```
- IP アドレスの永続化オプションの調査

**完了条件:**
- [ ] WSL2 の IP アドレスを確実に取得できるスクリプトがある

### Sub-stage 2.2: 静的プロキシ設定

**内容:**
- WSL2 内でテストサーバーを起動
  ```bash
  # WSL2 内で実行
  python3 -m http.server 8080
  ```
- nginx.conf に WSL2 向け upstream を追加
  ```nginx
  upstream wsl2_backend {
      server <WSL2_IP>:8080;
  }
  ```
- location ブロックで proxy_pass を設定
- 必要なプロキシヘッダーの設定

**完了条件:**
- [ ] WSL2 内のテストサーバーに OpenResty 経由でアクセスできる

### Sub-stage 2.3: 動的 IP 解決（Lua）

**内容:**
- Lua スクリプトで WSL2 IP を動的に取得
- `init_by_lua_block` または `access_by_lua_block` で実装
  ```nginx
  # 例: init_worker_by_lua_block でキャッシュ
  init_worker_by_lua_block {
      local function get_wsl2_ip()
          local handle = io.popen("wsl hostname -I")
          local result = handle:read("*a")
          handle:close()
          return result:match("^%S+")
      end
      ngx.shared.cache:set("wsl2_ip", get_wsl2_ip(), 300) -- 5分キャッシュ
  }
  ```
- キャッシュ戦略の検討（毎回実行は負荷が高い）

**代替案:** 起動時スクリプトで nginx.conf を書き換え、reload する方式
```powershell
# update-nginx-upstream.ps1
$wsl2_ip = (wsl hostname -I).Trim().Split()[0]
(Get-Content C:\openresty\conf\nginx.conf) -replace 'server \d+\.\d+\.\d+\.\d+:', "server ${wsl2_ip}:" | Set-Content C:\openresty\conf\nginx.conf
C:\openresty\nginx.exe -s reload
```

**完了条件:**
- [ ] WSL2 再起動後も設定変更なしでプロキシが動作する
- [ ] または IP 更新スクリプトが整備されている

### Sub-stage 2.4: プロキシヘッダーの調整

**内容:**
- 以下のヘッダーを適切に設定
  - `X-Real-IP`
  - `X-Forwarded-For`
  - `X-Forwarded-Proto`
  - `Host`
- WebSocket 対応の準備（Forgejo で必要な場合）

**完了条件:**
- [ ] バックエンドでクライアント IP が正しく取得できる

## 成果物

- `C:\openresty\conf\nginx.conf` - プロキシ設定追加版
- `scripts/windows/get-wsl2-ip.ps1` - WSL2 IP 取得スクリプト
- `scripts/windows/update-nginx-upstream.ps1` - upstream 更新スクリプト（オプション）

## 完了条件

- [ ] WSL2 内で起動したサービスに OpenResty 経由でアクセスできる
- [ ] `proxy_pass` 設定が動作する
- [ ] WSL2 IP の取得・更新手順が確立されている
- [ ] プロキシヘッダーが適切に設定されている

## 備考

- Lua による動的 IP 解決は複雑になりがちなため、まずは起動時スクリプト方式を推奨
- WSL2 のネットワークモード（NAT / mirrored）によって挙動が異なる場合がある
