# Stage 1: OpenResty セットアップ

## 概要

Windows 上に OpenResty をインストールし、基本的な HTTP サーバーとして動作させる。OpenResty は Nginx をベースに LuaJIT を統合した Web プラットフォームであり、これが Flatnet Gateway の基盤となる。

## ブランチ戦略

- ブランチ名: `phase1/stage-1-openresty-setup`
- マージ先: `master`

## インプット（前提条件）

- Windows 10/11 環境
- 管理者権限でのインストールが可能
- ポート 80/443 が他のアプリケーションで使用されていない（設定ファイルで変更可能）
- WSL2 (Ubuntu) がインストール済み

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

## ディレクトリ構成と設定ファイル管理

### 方針

設定ファイルは WSL2 側のリポジトリで Git 管理し、Windows 側にデプロイする。

```
[WSL2] /home/kh/prj/flatnet/
       └── config/
           └── openresty/           ← Git 管理（正）
               ├── nginx.conf
               └── conf.d/
                   └── default.conf

           デプロイスクリプト (scripts/deploy-config.sh)
                   │
                   ▼
[Windows] F:\flatnet\
          ├── openresty\            ← OpenResty 本体
          │   ├── nginx.exe
          │   ├── html\             ← 静的コンテンツ
          │   └── conf\             ← デフォルト設定（参照用）
          │       └── mime.types
          ├── config\               ← 設定ファイル（デプロイ先）
          │   └── nginx.conf
          └── logs\                 ← ログ出力先
              ├── access.log
              └── error.log
```

### WSL2 と Windows 間のパス

```bash
# WSL2 から Windows F: ドライブへアクセス
/mnt/f/flatnet/openresty/

# Windows から WSL2 へアクセス
\\wsl$\Ubuntu\home\kh\prj\flatnet\
```

## Sub-stages

### Sub-stage 1.1: OpenResty インストール

**内容:**

- OpenResty 公式サイトから Windows 版 ZIP をダウンロード
- `F:\flatnet\openresty` に展開
- PATH 環境変数への追加（オプション）

**手順:**

1. **ディレクトリ作成 (PowerShell 管理者):**

```powershell
New-Item -ItemType Directory -Path F:\flatnet -Force
New-Item -ItemType Directory -Path F:\flatnet\config -Force
New-Item -ItemType Directory -Path F:\flatnet\logs -Force
```

2. **OpenResty ダウンロードと展開:**

```powershell
# ダウンロード（ブラウザでも可）
# URL: https://openresty.org/en/download.html から Windows 版 (win64) を選択
# 例: openresty-1.25.3.1-win64.zip

# ダウンロードディレクトリに移動
cd $env:USERPROFILE\Downloads

# ZIP を展開
Expand-Archive -Path openresty-1.25.3.1-win64.zip -DestinationPath F:\flatnet\

# 展開されたディレクトリをリネーム
Rename-Item -Path "F:\flatnet\openresty-1.25.3.1-win64" -NewName "openresty"
```

3. **WSL2 側ディレクトリ作成:**

```bash
# WSL2 (Ubuntu)
mkdir -p /home/kh/prj/flatnet/config/openresty/conf.d
mkdir -p /home/kh/prj/flatnet/scripts
```

**完了条件:**

- [ ] `F:\flatnet\openresty\nginx.exe -v` でバージョンが表示される
  ```powershell
  # 確認コマンド
  F:\flatnet\openresty\nginx.exe -v
  # 期待出力: nginx version: openresty/1.25.3.1
  ```
- [ ] ディレクトリ構成が正しいことを確認
  ```powershell
  Test-Path F:\flatnet\openresty\nginx.exe
  Test-Path F:\flatnet\openresty\conf\mime.types
  Test-Path F:\flatnet\config
  Test-Path F:\flatnet\logs
  # 期待出力: すべて True
  ```

### Sub-stage 1.2: 基本設定

**内容:**

- nginx.conf の最小構成を作成（WSL2 側で Git 管理）
- テスト用 index.html の作成
- ログ出力の確認

**手順:**

1. **WSL2 側で nginx.conf を作成:**

ファイル: `/home/kh/prj/flatnet/config/openresty/nginx.conf`

```nginx
worker_processes 1;
error_log F:/flatnet/logs/error.log info;
pid       F:/flatnet/logs/nginx.pid;

events {
    worker_connections 1024;
}

http {
    # OpenResty 本体の mime.types を参照
    include       F:/flatnet/openresty/conf/mime.types;
    default_type  application/octet-stream;
    access_log    F:/flatnet/logs/access.log;

    server {
        listen 80;
        server_name localhost;

        location / {
            root   F:/flatnet/openresty/html;
            index  index.html;
        }

        # ヘルスチェック用エンドポイント
        location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
        }
    }
}
```

2. **Windows 側に設定をコピー（初回は手動）:**

```bash
# WSL2 から実行
cp /home/kh/prj/flatnet/config/openresty/nginx.conf /mnt/f/flatnet/config/
```

3. **テストページ作成 (PowerShell):**

```powershell
# F:\flatnet\openresty\html\index.html を作成
$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Flatnet Gateway</title>
    <meta charset="utf-8">
</head>
<body>
    <h1>Flatnet Gateway</h1>
    <p>OpenResty is running.</p>
    <p>Stage 1 setup complete.</p>
</body>
</html>
"@
$html | Out-File -FilePath F:\flatnet\openresty\html\index.html -Encoding utf8
```

**操作コマンド (PowerShell):**

```powershell
# 設定テスト
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t

# 起動
cd F:\flatnet\openresty
.\nginx.exe -c F:\flatnet\config\nginx.conf

# 停止
.\nginx.exe -c F:\flatnet\config\nginx.conf -s stop

# 設定リロード（再起動なし）
.\nginx.exe -c F:\flatnet\config\nginx.conf -s reload

# プロセス確認
Get-Process nginx -ErrorAction SilentlyContinue

# 強制終了（通常の停止ができない場合）
Stop-Process -Name nginx -Force
```

**完了条件:**

- [ ] `nginx.exe -t` で設定テストが成功する
  ```powershell
  F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t
  # 期待出力: nginx: configuration file F:\flatnet\config\nginx.conf test is successful
  ```
- [ ] `http://localhost/` でテストページが表示される
  ```powershell
  (Invoke-WebRequest -Uri http://localhost/).Content
  # 期待出力: HTML コンテンツ（Flatnet Gateway）
  ```
- [ ] `http://localhost/health` で "OK" が返る
  ```powershell
  (Invoke-WebRequest -Uri http://localhost/health).Content
  # 期待出力: OK
  ```
- [ ] `F:\flatnet\logs\error.log` にログが出力される
  ```powershell
  Get-Content F:\flatnet\logs\error.log -Tail 5
  ```

### Sub-stage 1.3: Windows Firewall 設定

**内容:**

- 受信規則の追加（TCP 80, 443）
- 動作確認

**手順 (PowerShell 管理者):**

1. **Firewall ルール追加:**

```powershell
# ポートベースのルール
New-NetFirewallRule -DisplayName "OpenResty HTTP" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
New-NetFirewallRule -DisplayName "OpenResty HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow

# 上記が機能しない場合は、プログラムベースのルールを追加
New-NetFirewallRule -DisplayName "OpenResty Program" -Direction Inbound -Program "F:\flatnet\openresty\nginx.exe" -Action Allow
```

2. **設定確認:**

```powershell
# 設定したルールの確認
Get-NetFirewallRule -DisplayName "OpenResty*" | Format-Table DisplayName, Enabled, Action

# Windows の IP アドレス確認
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } | Select-Object IPAddress, InterfaceAlias
```

**完了条件:**

- [ ] Firewall ルールが有効になっている
  ```powershell
  (Get-NetFirewallRule -DisplayName "OpenResty HTTP").Enabled
  # 期待出力: True
  ```
- [ ] 同一 LAN 内の別端末から `http://<Windows IP>/` でアクセスできる
  ```bash
  # 別端末（Linux、macOS）から実行
  curl http://<Windows IP>/health
  # 期待出力: OK
  ```
  ```powershell
  # 別端末（Windows）から実行
  (Invoke-WebRequest -Uri http://<Windows IP>/health).Content
  # 期待出力: OK
  ```

### Sub-stage 1.4: デプロイスクリプト作成

**内容:**

- WSL2 リポジトリの設定を Windows 側にデプロイするスクリプトを作成

**手順:**

1. **スクリプトファイル作成:**

ファイル: `/home/kh/prj/flatnet/scripts/deploy-config.sh`

```bash
#!/bin/bash
set -euo pipefail

# WSL2 から Windows へ設定ファイルをデプロイ

REPO_CONFIG="/home/kh/prj/flatnet/config/openresty"
WIN_CONFIG="/mnt/f/flatnet/config"
WIN_CONFIG_NATIVE="F:/flatnet/config"
OPENRESTY_BIN="/mnt/f/flatnet/openresty/nginx.exe"

# 設定ファイルが存在するか確認
if [ ! -d "${REPO_CONFIG}" ]; then
    echo "Error: ${REPO_CONFIG} does not exist"
    exit 1
fi

# Windows 側ディレクトリが存在するか確認
if [ ! -d "${WIN_CONFIG}" ]; then
    echo "Error: ${WIN_CONFIG} does not exist"
    echo "Hint: Create it with 'mkdir -p ${WIN_CONFIG}' or from Windows"
    exit 1
fi

# 設定ファイルをコピー
echo "Copying configuration files..."
cp -r ${REPO_CONFIG}/* ${WIN_CONFIG}/
echo "Deployed to ${WIN_CONFIG}"

# 設定テスト
echo "Testing configuration..."
if ${OPENRESTY_BIN} -c "${WIN_CONFIG_NATIVE}/nginx.conf" -t 2>&1; then
    echo "Configuration test passed"
else
    echo "Configuration test failed"
    exit 1
fi

# オプション: リロード（引数に --reload を指定した場合）
if [ "${1:-}" = "--reload" ]; then
    echo "Reloading OpenResty..."
    ${OPENRESTY_BIN} -c "${WIN_CONFIG_NATIVE}/nginx.conf" -s reload
    echo "OpenResty reloaded"
fi

echo "Done."
```

2. **実行権限を付与:**

```bash
chmod +x /home/kh/prj/flatnet/scripts/deploy-config.sh
```

**使用方法:**

```bash
# デプロイのみ
./scripts/deploy-config.sh

# デプロイ + リロード
./scripts/deploy-config.sh --reload
```

**完了条件:**

- [ ] スクリプトに実行権限がある
  ```bash
  ls -la scripts/deploy-config.sh
  # 期待出力: -rwxr-xr-x が表示される
  ```
- [ ] `./scripts/deploy-config.sh` で設定がデプロイされる
- [ ] デプロイ後に設定テストが成功する
- [ ] `--reload` オプションで OpenResty がリロードされる

### Sub-stage 1.5: サービス化（オプション）

**内容:**

- Windows サービスとして登録（NSSM を使用）
- 自動起動の設定

**NSSM のダウンロードと配置:**

- URL: https://nssm.cc/download
- ZIP をダウンロードして展開
- `nssm.exe` (win64) を `F:\flatnet\` にコピー

**サービス登録 (PowerShell 管理者):**

```powershell
# サービスとして登録
F:\flatnet\nssm.exe install OpenResty F:\flatnet\openresty\nginx.exe
F:\flatnet\nssm.exe set OpenResty AppDirectory F:\flatnet\openresty
F:\flatnet\nssm.exe set OpenResty AppParameters "-c F:\flatnet\config\nginx.conf"
F:\flatnet\nssm.exe set OpenResty Description "Flatnet Gateway (OpenResty)"
F:\flatnet\nssm.exe set OpenResty Start SERVICE_AUTO_START

# 既存の nginx プロセスを停止してからサービス開始
Stop-Process -Name nginx -Force -ErrorAction SilentlyContinue
Start-Service OpenResty

# サービス状態確認
Get-Service OpenResty
```

**サービス管理コマンド:**

```powershell
# 停止
Stop-Service OpenResty

# 開始
Start-Service OpenResty

# 再起動
Restart-Service OpenResty

# サービス削除（必要な場合）
F:\flatnet\nssm.exe remove OpenResty confirm
```

**完了条件:**

- [ ] サービスが登録されている
  ```powershell
  Get-Service OpenResty
  # 期待出力: Status が Running
  ```
- [ ] Windows 再起動後も OpenResty が自動で起動する

## 成果物

### Windows 側

| パス | 説明 |
|------|------|
| `F:\flatnet\openresty\` | OpenResty インストールディレクトリ |
| `F:\flatnet\openresty\nginx.exe` | OpenResty 実行ファイル |
| `F:\flatnet\openresty\html\index.html` | テストページ |
| `F:\flatnet\config\nginx.conf` | 設定ファイル（デプロイ先） |
| `F:\flatnet\logs\` | ログディレクトリ |
| Windows Firewall 受信規則 | OpenResty HTTP/HTTPS |

### WSL2 側（Git 管理）

| パス | 説明 |
|------|------|
| `config/openresty/nginx.conf` | 設定ファイル（正） |
| `config/openresty/conf.d/` | 追加設定ディレクトリ |
| `scripts/deploy-config.sh` | デプロイスクリプト |

## 完了条件

| 条件 | 確認コマンド |
|------|-------------|
| OpenResty が Windows 上で起動している | `Get-Process nginx` |
| `http://localhost/` でテストページが表示される | `Invoke-WebRequest http://localhost/` |
| `http://localhost/health` で "OK" が返る | `Invoke-WebRequest http://localhost/health` |
| Windows Firewall で 80/443 ポートが開放されている | `Get-NetFirewallRule -DisplayName "OpenResty*"` |
| 社内 LAN の別端末からアクセスできる | 別端末から `curl http://<IP>/health` |
| 設定ファイルが WSL2 リポジトリで Git 管理されている | `git status` |
| デプロイスクリプトが動作する | `./scripts/deploy-config.sh` |

## トラブルシューティング

### ポート 80 が使用中

**症状:** `nginx: [emerg] bind() to 0.0.0.0:80 failed (10013: permission denied)` または `(10048: address already in use)`

**対処:**

```powershell
# 使用中のポートとプロセスを確認
netstat -ano | findstr :80
# PID を確認して、どのプロセスか特定
Get-Process -Id <PID>

# IIS が使用している場合
Stop-Service W3SVC
Set-Service W3SVC -StartupType Disabled

# Skype が使用している場合（Skype 設定でポート 80 の使用を無効化）

# 別のポートを使用する場合は nginx.conf で listen 8080; に変更
```

### nginx.exe が起動しない

**症状:** コマンドを実行しても何も起動しない、またはすぐに終了する

**対処:**

```powershell
# まずログディレクトリが存在するか確認
Test-Path F:\flatnet\logs
# False の場合は作成
New-Item -ItemType Directory -Path F:\flatnet\logs -Force

# エラーログを確認
Get-Content F:\flatnet\logs\error.log

# 設定ファイルをテスト
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -t

# フォアグラウンドで起動してエラーを確認
F:\flatnet\openresty\nginx.exe -c F:\flatnet\config\nginx.conf -g "daemon off;"
# Ctrl+C で停止
```

### LAN 内からアクセスできない

**症状:** localhost では動作するが、他の端末からアクセスできない

**対処:**

```powershell
# Windows Firewall ルールの確認
Get-NetFirewallRule -DisplayName "OpenResty*" | Select-Object DisplayName, Enabled, Action

# Windows Firewall のプロファイル確認
Get-NetFirewallProfile | Format-Table Name, Enabled

# 現在のネットワークプロファイルを確認（Private でないとブロックされる可能性）
Get-NetConnectionProfile

# プロファイルを Private に変更（必要な場合）
Set-NetConnectionProfile -InterfaceAlias "イーサネット" -NetworkCategory Private

# Windows 側の IP アドレスを再確認
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual" }
```

### WSL2 からのデプロイでパスエラー

**症状:** デプロイスクリプトでパスが見つからないエラー

**対処:**

```bash
# Windows ドライブがマウントされているか確認
ls /mnt/f/

# マウントされていない場合
sudo mkdir -p /mnt/f
sudo mount -t drvfs F: /mnt/f

# 永続化する場合は /etc/fstab に追加
echo "F: /mnt/f drvfs defaults 0 0" | sudo tee -a /etc/fstab
```

### mime.types が見つからない

**症状:** `nginx: [emerg] open() "F:/flatnet/openresty/conf/mime.types" failed`

**対処:**

```powershell
# mime.types の場所を確認
Get-ChildItem -Path F:\flatnet\openresty -Recurse -Filter mime.types

# 見つかったパスに合わせて nginx.conf の include を修正
```

## 備考

- HTTPS (TLS) 設定は Stage 2 で対応予定
- 本番運用でのセキュリティ強化は Phase 4 で対応
- C ドライブの容量節約のため、すべて F ドライブに配置
- ログローテーションは Phase 4 で検討（当面は手動で管理）

## 次のステップ

Stage 1 完了後は [Stage 2: WSL2 プロキシ設定](./stage-2-wsl2-proxy.md) に進み、WSL2 内のサービスへの HTTP プロキシを設定する。
