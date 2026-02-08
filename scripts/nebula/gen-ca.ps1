# Flatnet Nebula CA Certificate Generation Script
# Phase 3 - Stage 1
#
# Usage: .\gen-ca.ps1 [-Name "Flatnet CA"] [-Duration "8760h"] [-Force]
#
# Prerequisites:
#   - nebula-cert.exe が F:\flatnet\nebula\ に配置されていること

[CmdletBinding()]
param(
    [string]$Name = "Flatnet CA",
    [string]$Duration = "8760h",  # 1年
    [switch]$Force,
    [string]$FlatnetBase = "F:\flatnet"
)

$ErrorActionPreference = "Stop"

# パス設定
$NebulaCert = "$FlatnetBase\nebula\nebula-cert.exe"
$PkiDir = "$FlatnetBase\pki"
$ConfigNebulaDir = "$FlatnetBase\config\nebula"

$CaKey = "$PkiDir\ca.key"
$CaCrt = "$ConfigNebulaDir\ca.crt"

Write-Host "Flatnet Nebula CA Certificate Generator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# nebula-cert.exe の存在確認
if (-not (Test-Path $NebulaCert)) {
    Write-Error @"
nebula-cert.exe が見つかりません: $NebulaCert

以下の手順で Nebula バイナリを取得してください:
1. https://github.com/slackhq/nebula/releases から nebula-windows-amd64.zip をダウンロード
2. 展開して nebula.exe と nebula-cert.exe を $FlatnetBase\nebula\ に配置
"@
    exit 1
}

# 既存の CA 確認
if ((Test-Path $CaKey) -and -not $Force) {
    Write-Error @"
CA 秘密鍵が既に存在します: $CaKey

既存の CA を上書きする場合は -Force オプションを使用してください。
警告: CA を再生成すると、既存の全証明書が無効になります。
"@
    exit 1
}

# ディレクトリ作成
Write-Host "ディレクトリを作成しています..."
New-Item -ItemType Directory -Path $PkiDir -Force | Out-Null
New-Item -ItemType Directory -Path $ConfigNebulaDir -Force | Out-Null

# CA 証明書の生成
Write-Host "CA 証明書を生成しています..."
Write-Host "  Name: $Name"
Write-Host "  Duration: $Duration"
Write-Host ""

Push-Location $PkiDir
try {
    & $NebulaCert ca -name $Name -duration $Duration
    if ($LASTEXITCODE -ne 0) {
        throw "nebula-cert ca の実行に失敗しました"
    }
}
finally {
    Pop-Location
}

# ca.crt を config にコピー
Write-Host "ca.crt を config ディレクトリにコピーしています..."
Copy-Item "$PkiDir\ca.crt" $CaCrt -Force

# 結果の確認
Write-Host ""
Write-Host "CA 証明書の生成が完了しました" -ForegroundColor Green
Write-Host ""
Write-Host "生成されたファイル:" -ForegroundColor Yellow
Write-Host "  CA 秘密鍵: $CaKey (厳重に保管してください)"
Write-Host "  CA 証明書: $CaCrt (各ホストに配布)"
Write-Host ""

# 証明書の内容を表示
Write-Host "CA 証明書の内容:" -ForegroundColor Yellow
& $NebulaCert print -path $CaCrt

Write-Host ""
Write-Host "次のステップ:" -ForegroundColor Cyan
Write-Host "  1. CA 秘密鍵 ($CaKey) をバックアップしてください"
Write-Host "  2. .\gen-host-cert.ps1 -Name lighthouse -Ip 10.100.0.1/16 で Lighthouse 証明書を生成"
