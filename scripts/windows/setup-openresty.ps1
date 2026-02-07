#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Flatnet Gateway - OpenResty Setup Script for Windows

.DESCRIPTION
    This script automates the initial setup of OpenResty for the Flatnet Gateway:
    - Creates required directories
    - Downloads and extracts OpenResty
    - Configures Windows Firewall rules
    - Creates a test index.html page
    - Verifies the installation

.PARAMETER OpenRestyVersion
    The version of OpenResty to install (default: 1.25.3.1)

.PARAMETER InstallPath
    The base installation path (default: F:\flatnet)

.PARAMETER SkipDownload
    Skip downloading OpenResty (assume it's already downloaded)

.PARAMETER SkipFirewall
    Skip creating Windows Firewall rules

.EXAMPLE
    .\setup-openresty.ps1
    # Runs with default settings

.EXAMPLE
    .\setup-openresty.ps1 -OpenRestyVersion "1.25.3.1" -InstallPath "D:\flatnet"
    # Custom version and install path

.NOTES
    Phase 1, Stage 1: OpenResty Setup
    Requires: Windows 10/11, Administrator privileges
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OpenRestyVersion = "1.25.3.1",

    [Parameter()]
    [string]$InstallPath = "F:\flatnet",

    [Parameter()]
    [switch]$SkipDownload,

    [Parameter()]
    [switch]$SkipFirewall
)

#==============================================================================
# Configuration
#==============================================================================

$ErrorActionPreference = "Stop"

# Derived paths
$OpenRestyPath = Join-Path $InstallPath "openresty"
$ConfigPath = Join-Path $InstallPath "config"
$LogsPath = Join-Path $InstallPath "logs"

# Download URL
$OpenRestyZip = "openresty-$OpenRestyVersion-win64.zip"
$OpenRestyUrl = "https://openresty.org/download/$OpenRestyZip"

#==============================================================================
# Helper Functions
#==============================================================================

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

#==============================================================================
# Setup Functions
#==============================================================================

function New-Directories {
    Write-Step "Creating Directories"

    $directories = @(
        $InstallPath,
        $ConfigPath,
        $LogsPath
    )

    foreach ($dir in $directories) {
        if (Test-Path $dir) {
            Write-Info "Directory already exists: $dir"
        } else {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Success "Created: $dir"
        }
    }
}

function Install-OpenResty {
    Write-Step "Installing OpenResty"

    # Check if already installed
    $nginxExe = Join-Path $OpenRestyPath "nginx.exe"
    if (Test-Path $nginxExe) {
        Write-Info "OpenResty already installed at: $OpenRestyPath"
        $version = & $nginxExe -v 2>&1
        Write-Info "Version: $version"
        return
    }

    if ($SkipDownload) {
        Write-Warning "Skipping download. Please manually extract OpenResty to: $OpenRestyPath"
        return
    }

    # Download
    $downloadPath = Join-Path $env:TEMP $OpenRestyZip
    if (Test-Path $downloadPath) {
        Write-Info "Using existing download: $downloadPath"
    } else {
        Write-Info "Downloading OpenResty from: $OpenRestyUrl"
        try {
            # Use TLS 1.2 for HTTPS
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($OpenRestyUrl, $downloadPath)
            Write-Success "Downloaded to: $downloadPath"
        } catch {
            Write-ErrorMsg "Failed to download OpenResty: $_"
            Write-Info "Please download manually from: https://openresty.org/en/download.html"
            Write-Info "Then extract to: $OpenRestyPath"
            throw
        }
    }

    # Extract
    Write-Info "Extracting OpenResty..."
    $extractPath = Join-Path $InstallPath "temp_extract"

    try {
        Expand-Archive -Path $downloadPath -DestinationPath $extractPath -Force

        # Find the extracted directory (e.g., openresty-1.25.3.1-win64)
        $extractedDir = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1

        if ($extractedDir) {
            # Move to final location
            if (Test-Path $OpenRestyPath) {
                Remove-Item $OpenRestyPath -Recurse -Force
            }
            Move-Item -Path $extractedDir.FullName -Destination $OpenRestyPath
            Write-Success "Installed to: $OpenRestyPath"
        } else {
            throw "Could not find extracted OpenResty directory"
        }
    } finally {
        # Cleanup
        if (Test-Path $extractPath) {
            Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Verify installation
    if (Test-Path $nginxExe) {
        $version = & $nginxExe -v 2>&1
        Write-Success "OpenResty installed successfully"
        Write-Info "Version: $version"
    } else {
        throw "Installation verification failed: nginx.exe not found"
    }
}

function Set-FirewallRules {
    Write-Step "Configuring Windows Firewall"

    if ($SkipFirewall) {
        Write-Warning "Skipping firewall configuration"
        return
    }

    $rules = @(
        @{
            DisplayName = "OpenResty HTTP"
            Protocol = "TCP"
            LocalPort = 80
            Description = "Flatnet Gateway - HTTP traffic"
        },
        @{
            DisplayName = "OpenResty HTTPS"
            Protocol = "TCP"
            LocalPort = 443
            Description = "Flatnet Gateway - HTTPS traffic"
        }
    )

    foreach ($rule in $rules) {
        $existingRule = Get-NetFirewallRule -DisplayName $rule.DisplayName -ErrorAction SilentlyContinue

        if ($existingRule) {
            Write-Info "Firewall rule already exists: $($rule.DisplayName)"
        } else {
            try {
                New-NetFirewallRule `
                    -DisplayName $rule.DisplayName `
                    -Direction Inbound `
                    -Protocol $rule.Protocol `
                    -LocalPort $rule.LocalPort `
                    -Action Allow `
                    -Description $rule.Description `
                    -Profile Any | Out-Null

                Write-Success "Created firewall rule: $($rule.DisplayName)"
            } catch {
                Write-ErrorMsg "Failed to create firewall rule: $($rule.DisplayName)"
                Write-ErrorMsg $_
            }
        }
    }

    # Also add program-based rule as backup
    $nginxExe = Join-Path $OpenRestyPath "nginx.exe"
    if (Test-Path $nginxExe) {
        $programRule = Get-NetFirewallRule -DisplayName "OpenResty Program" -ErrorAction SilentlyContinue

        if (-not $programRule) {
            try {
                New-NetFirewallRule `
                    -DisplayName "OpenResty Program" `
                    -Direction Inbound `
                    -Program $nginxExe `
                    -Action Allow `
                    -Description "Flatnet Gateway - OpenResty executable" `
                    -Profile Any | Out-Null

                Write-Success "Created program-based firewall rule"
            } catch {
                Write-Warning "Could not create program-based rule: $_"
            }
        }
    }
}

function New-TestPage {
    Write-Step "Creating Test Page"

    $htmlPath = Join-Path $OpenRestyPath "html"
    $indexPath = Join-Path $htmlPath "index.html"

    # Create html directory if it doesn't exist
    if (-not (Test-Path $htmlPath)) {
        New-Item -ItemType Directory -Path $htmlPath -Force | Out-Null
    }

    $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Flatnet Gateway</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            border-bottom: 2px solid #007bff;
            padding-bottom: 10px;
        }
        .status {
            display: inline-block;
            padding: 5px 15px;
            background-color: #28a745;
            color: white;
            border-radius: 20px;
            font-size: 14px;
        }
        .info {
            margin-top: 30px;
            padding: 20px;
            background-color: #f8f9fa;
            border-radius: 4px;
        }
        .info dt {
            font-weight: bold;
            color: #666;
        }
        .info dd {
            margin-left: 0;
            margin-bottom: 10px;
            color: #333;
        }
        .endpoints {
            margin-top: 20px;
        }
        .endpoints code {
            background-color: #e9ecef;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Consolas', 'Monaco', monospace;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Flatnet Gateway</h1>
        <p><span class="status">Running</span></p>
        <p>OpenResty is successfully installed and running.</p>

        <div class="info">
            <dl>
                <dt>Service</dt>
                <dd>Flatnet Gateway (OpenResty)</dd>

                <dt>Stage</dt>
                <dd>Phase 1, Stage 1 - Basic Setup</dd>

                <dt>Purpose</dt>
                <dd>HTTP Gateway for WSL2 containers</dd>
            </dl>
        </div>

        <div class="endpoints">
            <h3>Available Endpoints</h3>
            <ul>
                <li><code>GET /</code> - This page</li>
                <li><code>GET /health</code> - Health check endpoint</li>
                <li><code>GET /status</code> - Status info (localhost only)</li>
            </ul>
        </div>
    </div>
</body>
</html>
"@

    Set-Content -Path $indexPath -Value $htmlContent -Encoding UTF8
    Write-Success "Created test page: $indexPath"
}

function Test-Installation {
    Write-Step "Verifying Installation"

    $allPassed = $true

    # Check nginx.exe
    $nginxExe = Join-Path $OpenRestyPath "nginx.exe"
    if (Test-Path $nginxExe) {
        Write-Success "nginx.exe found"
    } else {
        Write-ErrorMsg "nginx.exe not found at: $nginxExe"
        $allPassed = $false
    }

    # Check mime.types
    $mimeTypes = Join-Path $OpenRestyPath "conf\mime.types"
    if (Test-Path $mimeTypes) {
        Write-Success "mime.types found"
    } else {
        Write-ErrorMsg "mime.types not found at: $mimeTypes"
        $allPassed = $false
    }

    # Check directories
    foreach ($path in @($ConfigPath, $LogsPath)) {
        if (Test-Path $path) {
            Write-Success "Directory exists: $path"
        } else {
            Write-ErrorMsg "Directory missing: $path"
            $allPassed = $false
        }
    }

    # Check firewall rules
    if (-not $SkipFirewall) {
        $httpRule = Get-NetFirewallRule -DisplayName "OpenResty HTTP" -ErrorAction SilentlyContinue
        if ($httpRule -and $httpRule.Enabled -eq "True") {
            Write-Success "Firewall rule enabled: OpenResty HTTP"
        } else {
            Write-Warning "Firewall rule not found or disabled: OpenResty HTTP"
        }
    }

    return $allPassed
}

function Show-NextSteps {
    Write-Step "Setup Complete!"

    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Deploy configuration from WSL2:" -ForegroundColor White
    Write-Host "   ./scripts/deploy-config.sh" -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. Test configuration:" -ForegroundColor White
    Write-Host "   $OpenRestyPath\nginx.exe -c $ConfigPath\nginx.conf -t" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. Start OpenResty:" -ForegroundColor White
    Write-Host "   cd $OpenRestyPath" -ForegroundColor Gray
    Write-Host "   .\nginx.exe -c $ConfigPath\nginx.conf" -ForegroundColor Gray
    Write-Host ""
    Write-Host "4. Test in browser:" -ForegroundColor White
    Write-Host "   http://localhost/" -ForegroundColor Gray
    Write-Host "   http://localhost/health" -ForegroundColor Gray
    Write-Host ""
    Write-Host "5. Check from another machine on LAN:" -ForegroundColor White
    Write-Host "   curl http://<this-pc-ip>/health" -ForegroundColor Gray
    Write-Host ""

    # Show Windows IP addresses
    Write-Host "Your Windows IP addresses:" -ForegroundColor Yellow
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.*" } |
        ForEach-Object {
            Write-Host "   $($_.IPAddress) ($($_.InterfaceAlias))" -ForegroundColor Gray
        }
}

#==============================================================================
# Main
#==============================================================================

function Main {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Magenta
    Write-Host "  Flatnet Gateway - OpenResty Setup" -ForegroundColor Magenta
    Write-Host "  Phase 1, Stage 1" -ForegroundColor Magenta
    Write-Host "============================================" -ForegroundColor Magenta

    # Check administrator
    if (-not (Test-Administrator)) {
        Write-ErrorMsg "This script requires Administrator privileges."
        Write-Host "Please run PowerShell as Administrator and try again."
        exit 1
    }

    Write-Info "Install path: $InstallPath"
    Write-Info "OpenResty version: $OpenRestyVersion"

    try {
        New-Directories
        Install-OpenResty
        Set-FirewallRules
        New-TestPage

        $verified = Test-Installation

        if ($verified) {
            Show-NextSteps
        } else {
            Write-Host ""
            Write-Warning "Some verification checks failed. Please review the errors above."
        }
    } catch {
        Write-Host ""
        Write-ErrorMsg "Setup failed: $_"
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
        exit 1
    }
}

Main
