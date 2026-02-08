# Phase 1 検証チェックリスト

Phase 1（Gateway 基盤）のセットアップ完了を確認するためのチェックリスト。

## 環境情報

記入日に環境情報を記録してください。

| 項目 | 値 |
|------|-----|
| 検証日 | |
| 検証者 | |
| Windows バージョン | |
| WSL2 ディストリビューション | |
| Podman バージョン | |
| OpenResty バージョン | |

## Stage 1: OpenResty セットアップ

### 1.1 インストール確認

- [ ] OpenResty がインストールされている
  ```powershell
  Test-Path F:\flatnet\openresty\nginx.exe
  # 期待: True
  ```

- [ ] バージョンが表示される
  ```powershell
  F:\flatnet\openresty\nginx.exe -v
  # 期待: nginx version: openresty/1.25.x.x
  ```

- [ ] ディレクトリ構成が正しい
  ```powershell
  Test-Path F:\flatnet\config
  Test-Path F:\flatnet\logs
  Test-Path F:\flatnet\openresty\conf\mime.types
  # 期待: すべて True
  ```

### 1.2 基本動作確認

- [ ] 設定テストが成功する
  ```powershell
  # Stage 1-2 の確認時は nginx.conf を使用
  F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t
  # 期待: test is successful
  ```

- [ ] OpenResty が起動する
  ```powershell
  cd F:\flatnet\openresty
  .\nginx.exe -c F:\flatnet\config\nginx.conf
  Get-Process nginx
  # 期待: nginx プロセスが表示される
  ```

- [ ] ヘルスチェックが成功する
  ```powershell
  (Invoke-WebRequest -Uri http://localhost/health).Content
  # 期待: OK
  ```

### 1.3 Firewall 設定

- [ ] Firewall ルールが存在する
  ```powershell
  Get-NetFirewallRule -DisplayName "OpenResty*" | Format-Table DisplayName, Enabled
  # 期待: OpenResty HTTP, OpenResty HTTPS が Enabled=True
  ```

### 1.4 デプロイスクリプト

- [ ] デプロイスクリプトが動作する
  ```bash
  ./scripts/deploy-config.sh --dry-run
  # 期待: DRY-RUN mode で正常終了
  ```

## Stage 2: WSL2 プロキシ設定

### 2.1 IP 取得

- [ ] WSL2 IP が取得できる（WSL2 側）
  ```bash
  ./scripts/get-wsl2-ip.sh
  # 期待: 172.x.x.x 形式の IP アドレス
  ```

- [ ] WSL2 IP が取得できる（Windows 側）
  ```powershell
  (wsl hostname -I).Trim().Split()[0]
  # 期待: 172.x.x.x 形式の IP アドレス
  ```

### 2.2 プロキシ設定

- [ ] nginx.conf に upstream が設定されている
  ```bash
  grep -E "upstream|server 172" /home/kh/prj/flatnet/config/openresty/nginx.conf
  # 期待: upstream と server IP が表示される
  ```

- [ ] プロキシ共通設定が存在する
  ```bash
  test -f /home/kh/prj/flatnet/config/openresty/conf.d/proxy-params.conf && echo "OK"
  # 期待: OK
  ```

- [ ] WebSocket 設定が存在する
  ```bash
  test -f /home/kh/prj/flatnet/config/openresty/conf.d/websocket-params.conf && echo "OK"
  # 期待: OK
  ```

### 2.3 IP 更新スクリプト

- [ ] upstream 更新スクリプトが動作する
  ```bash
  ./scripts/update-upstream.sh --dry-run
  # 期待: WSL2 IP が表示され、DRY-RUN で正常終了
  ```

## Stage 3: Forgejo 統合

> **注意:** Stage 3 では `nginx-forgejo.conf` を使用します。
> 設定変更後は `./scripts/deploy-config.sh --forgejo --reload` でデプロイしてください。

### 3.1 コンテナ準備

- [ ] Forgejo イメージが存在する
  ```bash
  podman images | grep forgejo
  # 期待: codeberg.org/forgejo/forgejo が表示される
  ```

- [ ] データディレクトリが存在する
  ```bash
  test -d ~/forgejo/data && test -d ~/forgejo/config && echo "OK"
  # 期待: OK
  ```

### 3.2 コンテナ動作

- [ ] Forgejo コンテナが起動している
  ```bash
  podman ps --filter name=forgejo --format "{{.Status}}"
  # 期待: Up xxx で始まるステータス
  ```

- [ ] WSL2 内から Forgejo にアクセスできる
  ```bash
  curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/
  # 期待: 200
  ```

### 3.3 OpenResty 連携

- [ ] OpenResty 経由で Forgejo にアクセスできる（Windows）
  ```powershell
  (Invoke-WebRequest -Uri http://localhost/).StatusCode
  # 期待: 200
  ```

- [ ] OpenResty 経由で Forgejo にアクセスできる（LAN）
  ```bash
  # 別端末から実行
  curl -s -o /dev/null -w "%{http_code}" http://<Windows IP>/
  # 期待: 200
  ```

### 3.4 Git 操作

- [ ] git clone が成功する
  ```bash
  git clone http://<Windows IP>/admin/test-repo.git /tmp/clone-test
  # 期待: Cloning ... done
  ```

- [ ] git push が成功する
  ```bash
  cd /tmp/clone-test
  echo "test" >> README.md
  git add . && git commit -m "test" && git push
  # 期待: main -> main
  ```

### 3.5 自動起動設定

- [ ] Quadlet 定義ファイルが存在する
  ```bash
  test -f ~/.config/containers/systemd/forgejo.container && echo "OK"
  # 期待: OK
  ```

- [ ] systemd サービスが有効になっている
  ```bash
  systemctl --user is-enabled forgejo
  # 期待: enabled
  ```

- [ ] systemd サービスが起動している
  ```bash
  systemctl --user is-active forgejo
  # 期待: active
  ```

### 3.6 復旧確認

- [ ] WSL2 再起動後も Forgejo が動作する
  ```powershell
  # Windows から実行
  wsl --shutdown
  Start-Sleep -Seconds 5
  wsl --exec bash -c "sleep 10 && curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/"
  # 期待: 200
  ```

### 3.7 セキュリティ確認

- [ ] 管理者アカウントが作成されている
  ```
  # ブラウザで Forgejo にログインし、管理者権限を確認
  ```

- [ ] 新規ユーザー登録が無効化されている（推奨）
  ```bash
  grep DISABLE_REGISTRATION ~/forgejo/config/app.ini
  # 期待: DISABLE_REGISTRATION = true
  ```

- [ ] ネットワークプロファイルが適切に設定されている
  ```powershell
  Get-NetConnectionProfile
  # 社内 LAN の場合、NetworkCategory が Private であることを確認
  ```

## 発見した問題

検証中に発見した問題を記録してください。

| 問題 | 発生箇所 | 解決策 | 対応状況 |
|------|----------|--------|----------|
| | | | |
| | | | |
| | | | |

## 手順書への修正提案

手順書の改善点を記録してください。

| ドキュメント | 箇所 | 修正内容 |
|--------------|------|----------|
| | | |
| | | |
| | | |

## 検証結果サマリー

| Stage | 項目数 | 完了数 | 結果 |
|-------|--------|--------|------|
| Stage 1 | 8 | | |
| Stage 2 | 6 | | |
| Stage 3 | 13 | | |
| **合計** | **27** | | |

## 備考

検証中の特記事項を記録してください。

---

検証完了日: _______________

検証者署名: _______________
