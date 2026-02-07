<#
.SYNOPSIS
    Flatnet Gateway - OpenResty Service Management Script

.DESCRIPTION
    This script provides commands to manage the OpenResty service:
    - start   : Start OpenResty
    - stop    : Stop OpenResty gracefully
    - restart : Stop and start OpenResty
    - reload  : Reload configuration without downtime
    - status  : Show current status
    - test    : Test configuration syntax
    - logs    : View recent logs

.PARAMETER Action
    The action to perform: start, stop, restart, reload, status, test, logs

.PARAMETER InstallPath
    The base installation path (default: F:\flatnet)

.PARAMETER Lines
    Number of log lines to show (default: 50, used with 'logs' action)

.EXAMPLE
    .\manage-openresty.ps1 start
    # Start OpenResty

.EXAMPLE
    .\manage-openresty.ps1 status
    # Check if OpenResty is running

.EXAMPLE
    .\manage-openresty.ps1 logs -Lines 100
    # View last 100 lines of error log

.NOTES
    Phase 1, Stage 1: Service Management
    Does not require Administrator for most operations
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet("start", "stop", "restart", "reload", "status", "test", "logs", "help")]
    [string]$Action,

    [Parameter()]
    [string]$InstallPath = "F:\flatnet",

    [Parameter()]
    [int]$Lines = 50
)

#==============================================================================
# Configuration
#==============================================================================

$ErrorActionPreference = "Stop"

# Derived paths
$OpenRestyPath = Join-Path $InstallPath "openresty"
$ConfigPath = Join-Path $InstallPath "config"
$LogsPath = Join-Path $InstallPath "logs"

# Files
$NginxExe = Join-Path $OpenRestyPath "nginx.exe"
$ConfigFile = Join-Path $ConfigPath "nginx.conf"
$PidFile = Join-Path $LogsPath "nginx.pid"
$ErrorLog = Join-Path $LogsPath "error.log"
$AccessLog = Join-Path $LogsPath "access.log"

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

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Test-Prerequisites {
    if (-not (Test-Path $NginxExe)) {
        Write-ErrorMsg "nginx.exe not found at: $NginxExe"
        Write-Host "Please run setup-openresty.ps1 first."
        return $false
    }

    if (-not (Test-Path $ConfigFile)) {
        Write-ErrorMsg "Configuration file not found at: $ConfigFile"
        Write-Host "Please deploy configuration with: ./scripts/deploy-config.sh"
        return $false
    }

    return $true
}

function Get-NginxProcess {
    return Get-Process -Name "nginx" -ErrorAction SilentlyContinue
}

function Get-NginxPid {
    if (Test-Path $PidFile) {
        $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($pid) {
            return [int]$pid
        }
    }
    return $null
}

#==============================================================================
# Action Functions
#==============================================================================

function Start-Nginx {
    Write-Info "Starting OpenResty..."

    # Check if already running
    $processes = Get-NginxProcess
    if ($processes) {
        Write-Warning "OpenResty is already running (PIDs: $($processes.Id -join ', '))"
        return
    }

    # Test configuration first
    Write-Info "Testing configuration..."
    $testResult = & $NginxExe -c $ConfigFile -t 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMsg "Configuration test failed:"
        Write-Host $testResult -ForegroundColor Red
        return
    }

    # Start nginx
    # Need to change to OpenResty directory for proper operation
    Push-Location $OpenRestyPath
    try {
        Start-Process -FilePath $NginxExe -ArgumentList "-c", $ConfigFile -WindowStyle Hidden
        Start-Sleep -Milliseconds 500

        # Verify it started
        $processes = Get-NginxProcess
        if ($processes) {
            Write-Success "OpenResty started (PIDs: $($processes.Id -join ', '))"

            # Test health endpoint
            try {
                $response = Invoke-WebRequest -Uri "http://localhost/health" -TimeoutSec 5 -UseBasicParsing
                if ($response.StatusCode -eq 200) {
                    Write-Success "Health check passed: http://localhost/health"
                }
            } catch {
                Write-Warning "Health check failed (server may still be starting)"
            }
        } else {
            Write-ErrorMsg "OpenResty failed to start. Check error log:"
            Write-Host $ErrorLog -ForegroundColor Gray
        }
    } finally {
        Pop-Location
    }
}

function Stop-Nginx {
    param([switch]$Quiet)

    if (-not $Quiet) {
        Write-Info "Stopping OpenResty..."
    }

    # Try graceful shutdown first
    $processes = Get-NginxProcess
    if (-not $processes) {
        if (-not $Quiet) {
            Write-Warning "OpenResty is not running"
        }
        return
    }

    # Send stop signal
    try {
        & $NginxExe -c $ConfigFile -s stop 2>&1 | Out-Null
        Start-Sleep -Milliseconds 500

        # Check if stopped
        $processes = Get-NginxProcess
        if (-not $processes) {
            if (-not $Quiet) {
                Write-Success "OpenResty stopped gracefully"
            }
            return
        }

        # Wait a bit more
        Start-Sleep -Seconds 2
        $processes = Get-NginxProcess
        if (-not $processes) {
            if (-not $Quiet) {
                Write-Success "OpenResty stopped"
            }
            return
        }

        # Force kill if still running
        Write-Warning "Graceful shutdown timed out, forcing stop..."
        $processes | Stop-Process -Force
        Write-Success "OpenResty stopped (forced)"

    } catch {
        # Fallback to force kill
        Write-Warning "Could not send stop signal, forcing stop..."
        $processes = Get-NginxProcess
        if ($processes) {
            $processes | Stop-Process -Force
            Write-Success "OpenResty stopped (forced)"
        }
    }

    # Clean up PID file
    if (Test-Path $PidFile) {
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    }
}

function Restart-Nginx {
    Write-Info "Restarting OpenResty..."
    Stop-Nginx -Quiet
    Start-Sleep -Milliseconds 500
    Start-Nginx
}

function Invoke-Reload {
    Write-Info "Reloading OpenResty configuration..."

    # Check if running
    $processes = Get-NginxProcess
    if (-not $processes) {
        Write-ErrorMsg "OpenResty is not running. Use 'start' to start it."
        return
    }

    # Test configuration first
    Write-Info "Testing configuration..."
    $testResult = & $NginxExe -c $ConfigFile -t 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMsg "Configuration test failed:"
        Write-Host $testResult -ForegroundColor Red
        return
    }
    Write-Success "Configuration valid"

    # Send reload signal
    $reloadResult = & $NginxExe -c $ConfigFile -s reload 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Configuration reloaded successfully"
    } else {
        Write-ErrorMsg "Reload failed:"
        Write-Host $reloadResult -ForegroundColor Red
    }
}

function Show-Status {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  OpenResty Status" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # Check processes
    $processes = Get-NginxProcess
    if ($processes) {
        Write-Host "Status: " -NoNewline
        Write-Host "RUNNING" -ForegroundColor Green
        Write-Host ""
        Write-Host "Processes:" -ForegroundColor Yellow
        foreach ($proc in $processes) {
            Write-Host "  PID: $($proc.Id), CPU: $($proc.CPU)s, Memory: $([math]::Round($proc.WorkingSet64/1MB, 2))MB"
        }
    } else {
        Write-Host "Status: " -NoNewline
        Write-Host "STOPPED" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Paths:" -ForegroundColor Yellow
    Write-Host "  Executable:    $NginxExe"
    Write-Host "  Configuration: $ConfigFile"
    Write-Host "  Error Log:     $ErrorLog"
    Write-Host "  Access Log:    $AccessLog"
    Write-Host "  PID File:      $PidFile"

    # Check if files exist
    Write-Host ""
    Write-Host "File Status:" -ForegroundColor Yellow
    Write-Host "  nginx.exe:    $(if (Test-Path $NginxExe) { 'Found' } else { 'NOT FOUND' })"
    Write-Host "  nginx.conf:   $(if (Test-Path $ConfigFile) { 'Found' } else { 'NOT FOUND' })"
    Write-Host "  error.log:    $(if (Test-Path $ErrorLog) { 'Found' } else { 'Not yet created' })"

    # Test health endpoint if running
    if ($processes) {
        Write-Host ""
        Write-Host "Health Check:" -ForegroundColor Yellow
        try {
            $response = Invoke-WebRequest -Uri "http://localhost/health" -TimeoutSec 5 -UseBasicParsing
            Write-Host "  http://localhost/health - " -NoNewline
            Write-Host "OK ($($response.StatusCode))" -ForegroundColor Green
        } catch {
            Write-Host "  http://localhost/health - " -NoNewline
            Write-Host "FAILED" -ForegroundColor Red
        }
    }

    Write-Host ""
}

function Test-Config {
    Write-Info "Testing OpenResty configuration..."
    Write-Host ""

    $result = & $NginxExe -c $ConfigFile -t 2>&1
    Write-Host $result

    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Success "Configuration syntax is valid"
    } else {
        Write-Host ""
        Write-ErrorMsg "Configuration test failed"
    }
}

function Show-Logs {
    param([string]$LogType = "error")

    $logFile = if ($LogType -eq "access") { $AccessLog } else { $ErrorLog }

    if (-not (Test-Path $logFile)) {
        Write-Warning "Log file not found: $logFile"
        Write-Info "The log file will be created when OpenResty starts."
        return
    }

    Write-Info "Last $Lines lines from: $logFile"
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Gray

    Get-Content $logFile -Tail $Lines | ForEach-Object {
        # Color error messages
        if ($_ -match '\[error\]') {
            Write-Host $_ -ForegroundColor Red
        } elseif ($_ -match '\[warn\]') {
            Write-Host $_ -ForegroundColor Yellow
        } else {
            Write-Host $_
        }
    }

    Write-Host ("=" * 60) -ForegroundColor Gray
}

function Show-Help {
    Write-Host ""
    Write-Host "OpenResty Management Script" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\manage-openresty.ps1 <action> [options]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Actions:" -ForegroundColor Yellow
    Write-Host "  start     Start OpenResty"
    Write-Host "  stop      Stop OpenResty gracefully"
    Write-Host "  restart   Stop and start OpenResty"
    Write-Host "  reload    Reload configuration (no downtime)"
    Write-Host "  status    Show current status"
    Write-Host "  test      Test configuration syntax"
    Write-Host "  logs      View recent error logs"
    Write-Host "  help      Show this help message"
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  -InstallPath <path>  Base path (default: F:\flatnet)"
    Write-Host "  -Lines <n>           Log lines to show (default: 50)"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\manage-openresty.ps1 start"
    Write-Host "  .\manage-openresty.ps1 status"
    Write-Host "  .\manage-openresty.ps1 logs -Lines 100"
    Write-Host ""
}

#==============================================================================
# Main
#==============================================================================

function Main {
    # Help doesn't need prerequisites
    if ($Action -eq "help") {
        Show-Help
        return
    }

    # Check prerequisites for other actions
    if (-not (Test-Prerequisites)) {
        exit 1
    }

    switch ($Action) {
        "start"   { Start-Nginx }
        "stop"    { Stop-Nginx }
        "restart" { Restart-Nginx }
        "reload"  { Invoke-Reload }
        "status"  { Show-Status }
        "test"    { Test-Config }
        "logs"    { Show-Logs }
    }
}

Main
