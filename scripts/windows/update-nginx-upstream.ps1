<#
.SYNOPSIS
    Update nginx.conf with the current WSL2 IP address

.DESCRIPTION
    This script:
    1. Gets the current WSL2 IP address
    2. Updates nginx.conf upstream configuration
    3. Tests the configuration
    4. Optionally reloads OpenResty

.PARAMETER ConfigPath
    Path to nginx.conf (default: F:\flatnet\config\nginx.conf)

.PARAMETER Reload
    If specified, reload OpenResty after updating configuration

.EXAMPLE
    .\update-nginx-upstream.ps1
    # Update IP in config only

.EXAMPLE
    .\update-nginx-upstream.ps1 -Reload
    # Update IP and reload OpenResty

.NOTES
    Phase 1, Stage 2: WSL2 Proxy Configuration
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ConfigPath = "F:\flatnet\config\nginx.conf",

    [Parameter()]
    [switch]$Reload
)

$ErrorActionPreference = "Stop"

# Paths
$InstallPath = "F:\flatnet"
$NginxBin = Join-Path $InstallPath "openresty\nginx.exe"
$ConfigNative = "F:/flatnet/config/nginx.conf"

#==============================================================================
# Helper Functions
#==============================================================================

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

#==============================================================================
# Main
#==============================================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Update WSL2 IP in nginx.conf" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get WSL2 IP address
Write-Info "Getting WSL2 IP address..."
$wsl2Ip = (wsl hostname -I).Trim().Split()[0]

if (-not $wsl2Ip) {
    Write-ErrorMsg "Failed to get WSL2 IP address"
    Write-Host "Is WSL2 running? Try: wsl --status"
    exit 1
}

Write-Success "WSL2 IP: $wsl2Ip"

# Check if config file exists
if (-not (Test-Path $ConfigPath)) {
    Write-ErrorMsg "Configuration file not found: $ConfigPath"
    Write-Host "Please deploy configuration first: ./scripts/deploy-config.sh"
    exit 1
}

# Read and update configuration
Write-Info "Updating configuration..."
$content = Get-Content $ConfigPath -Raw

# Replace IP address in upstream server directive
# Pattern: server 172.x.x.x:port; or server 10.x.x.x:port; etc.
$newContent = $content -replace 'server \d+\.\d+\.\d+\.\d+:', "server ${wsl2Ip}:"

if ($content -eq $newContent) {
    Write-Info "No changes needed (IP may already be correct)"
} else {
    # Write updated content
    $newContent | Set-Content $ConfigPath -NoNewline
    Write-Success "Updated: $ConfigPath"
}

# Test configuration
Write-Info "Testing configuration..."
$testResult = & $NginxBin -c $ConfigNative -t 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-ErrorMsg "Configuration test failed:"
    Write-Host $testResult -ForegroundColor Red
    exit 1
}

Write-Success "Configuration test passed"

# Reload if requested
if ($Reload) {
    Write-Info "Reloading OpenResty..."

    # Check if nginx is running
    $nginxProcess = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    if (-not $nginxProcess) {
        Write-ErrorMsg "OpenResty is not running. Cannot reload."
        Write-Host "Start OpenResty first: .\manage-openresty.ps1 start"
        exit 1
    }

    $reloadResult = & $NginxBin -c $ConfigNative -s reload 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Success "OpenResty reloaded"
    } else {
        Write-ErrorMsg "Reload failed:"
        Write-Host $reloadResult -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Success "Done!"
Write-Host ""

if (-not $Reload) {
    Write-Info "To apply changes, run: .\manage-openresty.ps1 reload"
    Write-Info "Or run this script with -Reload switch"
}
