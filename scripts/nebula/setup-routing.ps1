# Flatnet Windows Routing Setup Script
# Phase 3 - Stage 2
#
# Usage:
#   .\setup-routing.ps1
#   .\setup-routing.ps1 -EnableForwarding -Persistent
#
# This script configures:
#   1. IP Forwarding between WSL2 and Nebula interfaces
#   2. Routes for Nebula network (10.100.0.0/16)
#
# Prerequisites:
#   - Nebula サービスが起動していること
#   - WSL2 が起動していること
#   - 管理者権限で実行すること

[CmdletBinding()]
param(
    [switch]$EnableForwarding,
    [switch]$Persistent,
    [switch]$ShowStatus,
    [string]$NebulaNetwork = "10.100.0.0",
    [string]$NebulaMask = "255.255.0.0",
    [string]$FlatnetBase = "F:\flatnet"
)

$ErrorActionPreference = "Stop"

# 管理者権限チェック関数
function Test-Administrator {
    $currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Host "Flatnet Windows Routing Setup" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""

# ステータス表示
if ($ShowStatus -or (-not $EnableForwarding -and -not $Persistent)) {
    Write-Host "現在の状態:" -ForegroundColor Yellow
    Write-Host ""

    # IP Forwarding 状態
    try {
        $regValue = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -ErrorAction SilentlyContinue
        if ($regValue.IPEnableRouter -eq 1) {
            Write-Host "  IP Forwarding (Registry): 有効" -ForegroundColor Green
        } else {
            Write-Host "  IP Forwarding (Registry): 無効" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  IP Forwarding (Registry): 未設定" -ForegroundColor Yellow
    }

    # インターフェース一覧
    Write-Host ""
    Write-Host "ネットワークインターフェース:" -ForegroundColor Yellow

    # WSL インターフェース
    $wslInterface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*WSL*" -or $_.Name -like "*WSL*" }
    if ($wslInterface) {
        foreach ($iface in $wslInterface) {
            $forwarding = (Get-NetIPInterface -InterfaceIndex $iface.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).Forwarding
            $status = if ($forwarding -eq "Enabled") { "有効" } else { "無効" }
            Write-Host "  $($iface.Name): Forwarding=$status" -ForegroundColor $(if ($forwarding -eq "Enabled") { "Green" } else { "Yellow" })
        }
    } else {
        Write-Host "  WSL インターフェース: 見つかりません" -ForegroundColor Red
    }

    # Nebula インターフェース
    $nebulaInterface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*Nebula*" -or $_.Name -like "*nebula*" -or $_.Name -like "*Wintun*" }
    if ($nebulaInterface) {
        foreach ($iface in $nebulaInterface) {
            $forwarding = (Get-NetIPInterface -InterfaceIndex $iface.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).Forwarding
            $status = if ($forwarding -eq "Enabled") { "有効" } else { "無効" }
            Write-Host "  $($iface.Name): Forwarding=$status" -ForegroundColor $(if ($forwarding -eq "Enabled") { "Green" } else { "Yellow" })
        }
    } else {
        Write-Host "  Nebula インターフェース: 見つかりません (Nebula が起動していない可能性)" -ForegroundColor Yellow
    }

    # ルーティングテーブル
    Write-Host ""
    Write-Host "Nebula ネットワーク関連ルート:" -ForegroundColor Yellow
    $routes = Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.DestinationPrefix -like "10.100.*" }
    if ($routes) {
        foreach ($route in $routes) {
            $iface = (Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue).Name
            Write-Host "  $($route.DestinationPrefix) via $($route.NextHop) (Interface: $iface)"
        }
    } else {
        Write-Host "  10.100.0.0/16 へのルート: なし" -ForegroundColor Yellow
    }

    # WSL2 IP
    Write-Host ""
    Write-Host "WSL2 IP アドレス:" -ForegroundColor Yellow
    try {
        $wslIp = (wsl hostname -I 2>$null).Trim().Split()[0]
        if ($wslIp) {
            Write-Host "  WSL2: $wslIp"
        } else {
            Write-Host "  WSL2 が起動していないか、IP を取得できません" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  WSL2 の IP を取得できません" -ForegroundColor Yellow
    }

    if (-not $EnableForwarding -and -not $Persistent) {
        Write-Host ""
        Write-Host "使用方法:" -ForegroundColor Cyan
        Write-Host "  IP Forwarding を有効化: .\setup-routing.ps1 -EnableForwarding"
        Write-Host "  永続化 (再起動後も有効): .\setup-routing.ps1 -EnableForwarding -Persistent"
        exit 0
    }
}

# 管理者権限チェック（設定変更時）
if ($EnableForwarding -or $Persistent) {
    if (-not (Test-Administrator)) {
        Write-Error "この操作には管理者権限が必要です。管理者として再実行してください。"
        exit 1
    }
}

# IP Forwarding の有効化
if ($EnableForwarding) {
    Write-Host ""
    Write-Host "IP Forwarding を有効化しています..." -ForegroundColor Yellow

    # レジストリで永続化
    if ($Persistent) {
        Write-Host "  レジストリ設定 (永続化)..."
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -Name "IPEnableRouter" -Value 1 -Type DWord
        Write-Host "    IPEnableRouter = 1: 設定完了" -ForegroundColor Green
        Write-Host "    注意: 完全な有効化には再起動が必要な場合があります" -ForegroundColor Yellow
    }

    # WSL インターフェースの Forwarding を有効化
    $wslInterface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*WSL*" -or $_.Name -like "*WSL*" }
    if ($wslInterface) {
        foreach ($iface in $wslInterface) {
            Write-Host "  $($iface.Name) の Forwarding を有効化..."
            try {
                Set-NetIPInterface -InterfaceIndex $iface.ifIndex -AddressFamily IPv4 -Forwarding Enabled
                Write-Host "    $($iface.Name): 有効化完了" -ForegroundColor Green
            } catch {
                Write-Warning "    $($iface.Name): 有効化に失敗 - $_"
            }
        }
    } else {
        Write-Warning "WSL インターフェースが見つかりません"
    }

    # Nebula インターフェースの Forwarding を有効化
    $nebulaInterface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*Nebula*" -or $_.Name -like "*nebula*" -or $_.Name -like "*Wintun*" }
    if ($nebulaInterface) {
        foreach ($iface in $nebulaInterface) {
            Write-Host "  $($iface.Name) の Forwarding を有効化..."
            try {
                Set-NetIPInterface -InterfaceIndex $iface.ifIndex -AddressFamily IPv4 -Forwarding Enabled
                Write-Host "    $($iface.Name): 有効化完了" -ForegroundColor Green
            } catch {
                Write-Warning "    $($iface.Name): 有効化に失敗 - $_"
            }
        }
    } else {
        Write-Warning "Nebula インターフェースが見つかりません（Nebula サービスを起動してから再実行してください）"
    }
}

# WSL2 への戻りルート設定
Write-Host ""
Write-Host "ルーティング確認..." -ForegroundColor Yellow

try {
    $wslIp = (wsl hostname -I 2>$null).Trim().Split()[0]
    if ($wslIp) {
        Write-Host "  WSL2 IP: $wslIp"

        # WSL2 内のコンテナネットワークへのルート
        # (Phase 2 の CNI で使用する 10.89.x.x など)
        # 現時点では WSL2 自体への疎通確認のみ

        Write-Host ""
        Write-Host "WSL2 への疎通確認..." -ForegroundColor Yellow
        $pingResult = Test-Connection -ComputerName $wslIp -Count 1 -Quiet
        if ($pingResult) {
            Write-Host "  ping $wslIp : 成功" -ForegroundColor Green
        } else {
            Write-Host "  ping $wslIp : 失敗" -ForegroundColor Red
            Write-Host "  WSL2 のファイアウォール設定を確認してください"
        }
    }
} catch {
    Write-Warning "WSL2 の IP を取得できませんでした"
}

# 結果サマリー
Write-Host ""
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "ルーティング設定完了" -ForegroundColor Green
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""
Write-Host "次のステップ:" -ForegroundColor Cyan
Write-Host "  1. WSL2 側でルーティング設定: wsl ~/flatnet/scripts/wsl-routing.sh"
Write-Host "  2. 接続テスト: .\test-tunnel.ps1"
Write-Host ""
Write-Host "確認コマンド:" -ForegroundColor Yellow
Write-Host "  状態確認: .\setup-routing.ps1 -ShowStatus"
Write-Host "  ルート確認: route print | findstr 10.100"
Write-Host "  Forwarding 確認: Get-NetIPInterface | Where-Object { `$_.Forwarding -eq 'Enabled' }"
