# Stage 1: OpenResty セットアップ

## 概要

Windows 上に OpenResty をインストールし、基本的な HTTP サーバーとして動作させる。これが Flatnet Gateway の基盤となる。

## ブランチ戦略

- ブランチ名: `phase1/stage-1-openresty-setup`
- マージ先: `master`

## インプット（前提条件）

- Windows 11 環境
- 管理者権限でのインストールが可能
- ポート 80/443 が他のアプリケーションで使用されていない

## 目標

- OpenResty を Windows 上にインストールする
- 基本的な nginx.conf を設定する
- Windows Firewall でポートを開放する
- 社内 LAN から HTTP アクセスできる状態にする

## 手段

- OpenResty 公式 Windows バイナリをダウンロード・展開
- nginx.conf を最小構成で設定
- Windows Firewall の受信規則を追加
- 動作確認用のテストページを設置

## Sub-stages

### Sub-stage 1.1: OpenResty インストール

**内容:**
- OpenResty 公式サイトから Windows 版 ZIP をダウンロード
  - URL: https://openresty.org/en/download.html
  - Windows 版 (win64) を選択
- `C:\openresty` に展開
- PATH 環境変数への追加（オプション）

**完了条件:**
- [ ] `C:\openresty\nginx.exe -v` でバージョンが表示される

### Sub-stage 1.2: 基本設定

**内容:**
- nginx.conf の最小構成を作成
  - worker_processes: 1
  - listen: 80
  - server_name: localhost
  - root ディレクトリの設定
  - error_log の設定
- テスト用 index.html の作成
- ログ出力の確認

**完了条件:**
- [ ] `nginx.exe` が起動する
- [ ] `http://localhost/` でテストページが表示される
- [ ] `logs/error.log` にログが出力される

### Sub-stage 1.3: Windows Firewall 設定

**内容:**
- 受信規則の追加（TCP 80, 443）
  ```powershell
  # 管理者権限で実行
  New-NetFirewallRule -DisplayName "OpenResty HTTP" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
  New-NetFirewallRule -DisplayName "OpenResty HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow
  ```
- nginx.exe へのプログラム許可（上記が機能しない場合）
  ```powershell
  New-NetFirewallRule -DisplayName "OpenResty" -Direction Inbound -Program "C:\openresty\nginx.exe" -Action Allow
  ```

**完了条件:**
- [ ] 同一 LAN 内の別端末から `http://<Windows IP>/` でアクセスできる

### Sub-stage 1.4: サービス化（オプション）

**内容:**
- Windows サービスとして登録（NSSM 等を使用）
- 自動起動の設定

**完了条件:**
- [ ] Windows 再起動後も OpenResty が自動で起動する

## 成果物

- `C:\openresty\` - OpenResty インストールディレクトリ
- `C:\openresty\conf\nginx.conf` - 基本設定ファイル
- `C:\openresty\html\index.html` - テストページ
- `C:\openresty\logs\` - ログディレクトリ
- Windows Firewall 受信規則

## 完了条件

- [ ] OpenResty が Windows 上で起動している
- [ ] `http://localhost/` でデフォルトページが表示される
- [ ] Windows Firewall で 80/443 ポートが開放されている
- [ ] 社内 LAN の別端末からアクセスできる

## 備考

- HTTPS (TLS) 設定は Phase 1 のスコープ外。必要に応じて Stage 2 以降で追加
- 本番運用でのセキュリティ強化は Phase 4 で対応
