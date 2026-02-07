<#
.SYNOPSIS
    Get the IP address of WSL2

.DESCRIPTION
    This script retrieves the IP address of the WSL2 instance.
    The IP address is needed for nginx upstream configuration.

.EXAMPLE
    .\get-wsl2-ip.ps1
    # Outputs: 172.x.x.x

.NOTES
    Phase 1, Stage 2: WSL2 Proxy Configuration
#>

[CmdletBinding()]
param()

# Get WSL2 IP address using hostname -I command
$wsl2Ip = (wsl hostname -I).Trim().Split()[0]

if (-not $wsl2Ip) {
    Write-Error "Failed to get WSL2 IP address"
    exit 1
}

Write-Output $wsl2Ip
