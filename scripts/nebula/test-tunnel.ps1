# Flatnet Nebula Tunnel Connection Test Script
# Phase 3 - Stage 2
#
# Usage:
#   .\test-tunnel.ps1                           # 基本テスト（Lighthouse のみ）
#   .\test-tunnel.ps1 -Hosts 10.100.2.1,10.100.3.1  # 複数ホストをテスト
#   .\test-tunnel.ps1 -Detailed                 # 詳細情報を表示
#
# This script tests:
#   1. Nebula service status
#   2. Network interface status
#   3. Connectivity to Lighthouse
#   4. Connectivity to other hosts (if specified)
#   5. WSL2 connectivity

[CmdletBinding()]
param(
    [string[]]$Hosts = @(),
    [string]$LighthouseIp = "10.100.0.1",
    [switch]$Detailed,
    [switch]$SkipWsl,
    [string]$FlatnetBase = "F:\flatnet"
)

$ErrorActionPreference = "Continue"

# 色付き出力用関数
function Write-Success { param($Message) Write-Host $Message -ForegroundColor Green }
function Write-Warn { param($Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Fail { param($Message) Write-Host $Message -ForegroundColor Red }
function Write-Info { param($Message) Write-Host $Message -ForegroundColor Cyan }

Write-Info "Flatnet Nebula Tunnel Connection Test"
Write-Info "======================================"
Write-Host ""

$allPassed = $true

# 1. Nebula サービス状態
Write-Host "1. Nebula サービス状態" -ForegroundColor Yellow
$service = Get-Service -Name "Nebula" -ErrorAction SilentlyContinue
if ($service) {
    if ($service.Status -eq "Running") {
        Write-Success "   Nebula サービス: Running"
    } else {
        Write-Fail "   Nebula サービス: $($service.Status)"
        Write-Host "   -> Start-Service Nebula で起動してください"
        $allPassed = $false
    }
} else {
    Write-Fail "   Nebula サービス: インストールされていません"
    Write-Host "   -> setup-host.ps1 -Install でインストールしてください"
    $allPassed = $false
}
Write-Host ""

# 2. ネットワークインターフェース
Write-Host "2. ネットワークインターフェース" -ForegroundColor Yellow

# Nebula インターフェース
$nebulaInterface = Get-NetAdapter | Where-Object {
    $_.InterfaceDescription -like "*Nebula*" -or
    $_.Name -like "*nebula*" -or
    $_.Name -like "*Wintun*"
}

if ($nebulaInterface) {
    foreach ($iface in $nebulaInterface) {
        if ($iface.Status -eq "Up") {
            Write-Success "   $($iface.Name): Up"
            if ($Detailed) {
                $ipConfig = Get-NetIPAddress -InterfaceIndex $iface.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
                if ($ipConfig) {
                    Write-Host "     IP: $($ipConfig.IPAddress)/$($ipConfig.PrefixLength)"
                }
            }
        } else {
            Write-Fail "   $($iface.Name): $($iface.Status)"
            $allPassed = $false
        }
    }
} else {
    Write-Fail "   Nebula インターフェース: 見つかりません"
    Write-Host "   -> Nebula サービスを起動してください"
    $allPassed = $false
}

# WSL インターフェース
$wslInterface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*WSL*" -or $_.Name -like "*WSL*" }
if ($wslInterface) {
    foreach ($iface in $wslInterface) {
        if ($iface.Status -eq "Up") {
            Write-Success "   $($iface.Name): Up"
        } else {
            Write-Warn "   $($iface.Name): $($iface.Status)"
        }
    }
} else {
    Write-Warn "   WSL インターフェース: 見つかりません (WSL が停止している可能性)"
}
Write-Host ""

# 3. Lighthouse への接続
Write-Host "3. Lighthouse への接続" -ForegroundColor Yellow
$pingResult = Test-Connection -ComputerName $LighthouseIp -Count 2 -Quiet -ErrorAction SilentlyContinue
if ($pingResult) {
    Write-Success "   ping $LighthouseIp : 成功"
} else {
    Write-Fail "   ping $LighthouseIp : 失敗"
    $allPassed = $false

    # トラブルシューティング
    Write-Host ""
    Write-Host "   トラブルシューティング:" -ForegroundColor Yellow
    Write-Host "   - Nebula サービスが起動しているか確認"
    Write-Host "   - Lighthouse が起動しているか確認"
    Write-Host "   - Windows Firewall で Nebula が許可されているか確認"
    Write-Host "   - ログ確認: Get-Content $FlatnetBase\logs\nebula.log -Tail 20"
}
Write-Host ""

# 4. 他ホストへの接続
if ($Hosts.Count -gt 0) {
    Write-Host "4. 他ホストへの接続" -ForegroundColor Yellow
    foreach ($hostIp in $Hosts) {
        $pingResult = Test-Connection -ComputerName $hostIp -Count 2 -Quiet -ErrorAction SilentlyContinue
        if ($pingResult) {
            Write-Success "   ping $hostIp : 成功"
        } else {
            Write-Fail "   ping $hostIp : 失敗"
            $allPassed = $false
        }
    }
    Write-Host ""
}

# 5. WSL2 への接続
if (-not $SkipWsl) {
    Write-Host "5. WSL2 への接続" -ForegroundColor Yellow
    try {
        $wslIp = (wsl hostname -I 2>$null).Trim().Split()[0]
        if ($wslIp) {
            Write-Host "   WSL2 IP: $wslIp"
            $pingResult = Test-Connection -ComputerName $wslIp -Count 2 -Quiet -ErrorAction SilentlyContinue
            if ($pingResult) {
                Write-Success "   ping $wslIp : 成功"
            } else {
                Write-Warn "   ping $wslIp : 失敗 (WSL Firewall の可能性)"
            }
        } else {
            Write-Warn "   WSL2 が起動していないか、IP を取得できません"
        }
    } catch {
        Write-Warn "   WSL2 の状態を確認できません"
    }
    Write-Host ""
}

# 6. 詳細情報
if ($Detailed) {
    Write-Host "6. 詳細情報" -ForegroundColor Yellow

    # IP Forwarding 状態
    Write-Host "   IP Forwarding:" -ForegroundColor Cyan
    $forwardingInterfaces = Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.Forwarding -eq "Enabled" }
    if ($forwardingInterfaces) {
        foreach ($iface in $forwardingInterfaces) {
            $adapter = Get-NetAdapter -InterfaceIndex $iface.ifIndex -ErrorAction SilentlyContinue
            if ($adapter) {
                Write-Host "     $($adapter.Name): Enabled"
            }
        }
    } else {
        Write-Warn "     有効なインターフェースなし"
    }
    Write-Host ""

    # ルーティングテーブル
    Write-Host "   Nebula 関連ルート:" -ForegroundColor Cyan
    $routes = Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -like "10.100.*" }
    if ($routes) {
        foreach ($route in $routes) {
            $adapter = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
            Write-Host "     $($route.DestinationPrefix) via $($route.NextHop) ($($adapter.Name))"
        }
    } else {
        Write-Host "     10.100.x.x へのルートなし"
    }
    Write-Host ""

    # Nebula ログ（最新5行）
    $logFile = "$FlatnetBase\logs\nebula.log"
    if (Test-Path $logFile) {
        Write-Host "   Nebula ログ (最新5行):" -ForegroundColor Cyan
        Get-Content $logFile -Tail 5 | ForEach-Object {
            Write-Host "     $_"
        }
    }
    Write-Host ""
}

# 結果サマリー
Write-Host "======================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Success "テスト結果: 全て成功"
} else {
    Write-Fail "テスト結果: 一部失敗"
    Write-Host ""
    Write-Host "確認コマンド:" -ForegroundColor Yellow
    Write-Host "  サービス: Get-Service Nebula"
    Write-Host "  ログ: Get-Content $FlatnetBase\logs\nebula.log -Tail 20"
    Write-Host "  ルーティング: .\setup-routing.ps1 -ShowStatus"
}
Write-Host ""
