# Flatnet Nebula Host Certificate Generation Script
# Phase 3 - Stage 1
#
# Usage:
#   .\gen-host-cert.ps1 -Name lighthouse -Ip 10.100.0.1/16
#   .\gen-host-cert.ps1 -Name host-a -Ip 10.100.1.1/16 -Groups "flatnet,gateway"
#
# Prerequisites:
#   - nebula-cert.exe が F:\flatnet\nebula\ に配置されていること
#   - CA 証明書が生成済み (gen-ca.ps1)

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Name,

    [Parameter(Mandatory=$true)]
    [string]$Ip,

    [string]$Groups = "",
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
$HostCrt = "$ConfigNebulaDir\$Name.crt"
$HostKey = "$ConfigNebulaDir\$Name.key"

Write-Host "Flatnet Nebula Host Certificate Generator" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
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

# CA ファイルの存在確認
if (-not (Test-Path $CaKey)) {
    Write-Error @"
CA 秘密鍵が見つかりません: $CaKey

先に .\gen-ca.ps1 を実行して CA を生成してください。
"@
    exit 1
}

if (-not (Test-Path $CaCrt)) {
    Write-Error @"
CA 証明書が見つかりません: $CaCrt

先に .\gen-ca.ps1 を実行して CA を生成してください。
"@
    exit 1
}

# 既存証明書の確認
if ((Test-Path $HostCrt) -and -not $Force) {
    Write-Error @"
証明書が既に存在します: $HostCrt

既存の証明書を上書きする場合は -Force オプションを使用してください。
"@
    exit 1
}

# ディレクトリ確認
if (-not (Test-Path $ConfigNebulaDir)) {
    New-Item -ItemType Directory -Path $ConfigNebulaDir -Force | Out-Null
}

# 証明書の生成
Write-Host "ホスト証明書を生成しています..."
Write-Host "  Name: $Name"
Write-Host "  IP: $Ip"
if ($Groups) {
    Write-Host "  Groups: $Groups"
}
Write-Host "  Duration: $Duration"
Write-Host ""

Push-Location $PkiDir
try {
    $certArgs = @(
        "sign",
        "-name", $Name,
        "-ip", $Ip,
        "-ca-crt", $CaCrt,
        "-ca-key", $CaKey,
        "-duration", $Duration
    )

    if ($Groups) {
        $certArgs += "-groups"
        $certArgs += $Groups
    }

    & $NebulaCert @certArgs
    if ($LASTEXITCODE -ne 0) {
        throw "nebula-cert sign の実行に失敗しました"
    }

    # 証明書を config ディレクトリに移動
    Move-Item "$PkiDir\$Name.crt" $HostCrt -Force
    Move-Item "$PkiDir\$Name.key" $HostKey -Force
}
finally {
    Pop-Location
}

# 結果の確認
Write-Host ""
Write-Host "ホスト証明書の生成が完了しました" -ForegroundColor Green
Write-Host ""
Write-Host "生成されたファイル:" -ForegroundColor Yellow
Write-Host "  証明書: $HostCrt"
Write-Host "  秘密鍵: $HostKey"
Write-Host ""

# 証明書の内容を表示
Write-Host "証明書の内容:" -ForegroundColor Yellow
& $NebulaCert print -path $HostCrt

# 証明書の検証
Write-Host ""
Write-Host "証明書の検証:" -ForegroundColor Yellow
& $NebulaCert verify -ca $CaCrt -crt $HostCrt
if ($LASTEXITCODE -eq 0) {
    Write-Host "  検証成功" -ForegroundColor Green
} else {
    Write-Host "  検証失敗" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "次のステップ:" -ForegroundColor Cyan
if ($Name -eq "lighthouse") {
    Write-Host "  1. .\setup-lighthouse.ps1 で Lighthouse をセットアップ"
} else {
    Write-Host "  1. 証明書を対象ホストに安全にコピー"
    Write-Host "  2. 対象ホストで Nebula を設定"
}
