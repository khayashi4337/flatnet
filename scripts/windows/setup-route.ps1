# Flatnet Routing Setup Script for Windows
# Phase 2, Stage 4: Integration
#
# This script configures Windows routing to reach Flatnet containers
# running in WSL2. It must be run as Administrator.
#
# Usage:
#   .\setup-route.ps1           # Add route only
#   .\setup-route.ps1 -Verify   # Add route and verify connectivity
#   .\setup-route.ps1 -Remove   # Remove the route
#
# The Flatnet subnet is 10.87.1.0/24 and routes through WSL2.

param(
    [switch]$Verify,
    [switch]$Remove,
    [switch]$Help
)

#==============================================================================
# Configuration
#==============================================================================

$FlatnetSubnet = "10.87.1.0"
$FlatnetMask = "255.255.255.0"
$FlatnetBridge = "10.87.1.1"

#==============================================================================
# Helper Functions
#==============================================================================

function Write-Status {
    param([string]$Message, [string]$Status = "INFO")
    $color = switch ($Status) {
        "OK"    { "Green" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }
    Write-Host "[$Status] " -ForegroundColor $color -NoNewline
    Write-Host $Message
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WSL2IP {
    try {
        $wslIP = (wsl hostname -I).Trim().Split()[0]
        if (-not $wslIP) {
            return $null
        }
        return $wslIP
    }
    catch {
        return $null
    }
}

function Test-RouteExists {
    $route = route print | Select-String $FlatnetSubnet
    return $null -ne $route
}

function Show-Help {
    @"
Flatnet Routing Setup Script
=============================

This script configures Windows routing to reach Flatnet containers in WSL2.

USAGE:
    .\setup-route.ps1 [OPTIONS]

OPTIONS:
    -Verify     After adding the route, verify connectivity to the bridge
    -Remove     Remove the Flatnet route instead of adding it
    -Help       Show this help message

EXAMPLES:
    # Add route to Flatnet subnet
    .\setup-route.ps1

    # Add route and verify connectivity
    .\setup-route.ps1 -Verify

    # Remove Flatnet route
    .\setup-route.ps1 -Remove

PREREQUISITES:
    - Run as Administrator
    - WSL2 must be running
    - Flatnet bridge (10.87.1.1) should be configured in WSL2

TROUBLESHOOTING:
    If ping to 10.87.1.1 fails after adding the route:
    1. Check WSL2 IP forwarding: wsl sysctl net.ipv4.ip_forward
    2. Check iptables FORWARD chain: wsl sudo iptables -L FORWARD -n
    3. Verify bridge exists: wsl ip addr show flatnet-br0
"@
}

#==============================================================================
# Main Logic
#==============================================================================

if ($Help) {
    Show-Help
    exit 0
}

# Check Administrator privileges
if (-not (Test-Administrator)) {
    Write-Status "This script requires Administrator privileges" "ERROR"
    Write-Host "Please run PowerShell as Administrator and try again."
    exit 1
}

# Get WSL2 IP
$wslIP = Get-WSL2IP
if (-not $wslIP) {
    Write-Status "Could not determine WSL2 IP address. Is WSL running?" "ERROR"
    Write-Host "Try running: wsl hostname -I"
    exit 1
}

Write-Status "WSL2 IP: $wslIP" "INFO"

# Handle Remove mode
if ($Remove) {
    Write-Status "Removing Flatnet route..." "INFO"

    if (-not (Test-RouteExists)) {
        Write-Status "Route does not exist, nothing to remove" "WARN"
        exit 0
    }

    $result = route delete $FlatnetSubnet 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Status "Route removed successfully" "OK"
    }
    else {
        Write-Status "Failed to remove route: $result" "ERROR"
        exit 1
    }
    exit 0
}

# Add mode (default)
Write-Status "Configuring Flatnet routing..." "INFO"

# Remove existing route if present (to update with new WSL2 IP)
if (Test-RouteExists) {
    Write-Status "Removing old route..." "INFO"
    route delete $FlatnetSubnet 2>$null | Out-Null
}

# Add new route
Write-Status "Adding route: $FlatnetSubnet/24 via $wslIP" "INFO"
$result = route add $FlatnetSubnet mask $FlatnetMask $wslIP 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Status "Route added successfully" "OK"
}
else {
    Write-Status "Failed to add route: $result" "ERROR"
    exit 1
}

# Verify route was added
if (Test-RouteExists) {
    Write-Status "Route verified in routing table" "OK"
    route print | Select-String $FlatnetSubnet
}
else {
    Write-Status "Route not found in routing table" "ERROR"
    exit 1
}

# Optional connectivity verification
if ($Verify) {
    Write-Host ""
    Write-Status "Verifying connectivity..." "INFO"

    # Ping the bridge
    $pingResult = ping -n 1 -w 2000 $FlatnetBridge 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Status "Ping to bridge ($FlatnetBridge) successful" "OK"
    }
    else {
        Write-Status "Ping to bridge ($FlatnetBridge) failed" "WARN"
        Write-Host ""
        Write-Host "Possible causes:"
        Write-Host "  - WSL2 IP forwarding is disabled"
        Write-Host "  - iptables FORWARD chain is blocking"
        Write-Host "  - Bridge interface not configured"
        Write-Host ""
        Write-Host "Check with:"
        Write-Host "  wsl sysctl net.ipv4.ip_forward"
        Write-Host "  wsl ip addr show flatnet-br0"
    }
}

Write-Host ""
Write-Status "Setup complete" "OK"
Write-Host ""
Write-Host "Note: This route is temporary and will be lost after Windows restart."
Write-Host "Run this script again after restart, or set up a scheduled task."
