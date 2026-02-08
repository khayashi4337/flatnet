# Windows Log Rotation Script for Flatnet Gateway
# Phase 4, Stage 2: Logging Infrastructure
#
# This script rotates OpenResty logs on Windows.
# Schedule this script to run daily using Windows Task Scheduler.
#
# Usage:
#   .\rotate-logs.ps1
#   .\rotate-logs.ps1 -RetentionDays 7
#   .\rotate-logs.ps1 -LogPath "D:\flatnet\logs"

[CmdletBinding()]
param(
    [string]$LogPath = "F:\flatnet\logs",
    [int]$RetentionDays = 14,
    [string]$OpenRestyPath = "F:\flatnet\openresty"
)

# Ensure script runs with proper error handling
$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
}

function Test-OpenRestyRunning {
    $process = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    return $null -ne $process
}

try {
    Write-Log "Starting log rotation for Flatnet Gateway"
    Write-Log "Log path: $LogPath"
    Write-Log "Retention days: $RetentionDays"

    # Verify log directory exists
    if (-not (Test-Path $LogPath)) {
        Write-Log "Log directory does not exist: $LogPath" -Level "ERROR"
        exit 1
    }

    # Verify write permissions
    try {
        $testFile = Join-Path $LogPath ".write-test-$(Get-Random)"
        [IO.File]::WriteAllText($testFile, "test")
        Remove-Item $testFile -Force
    } catch {
        Write-Log "No write permission to log directory: $LogPath" -Level "ERROR"
        exit 1
    }

    # Step 1: Delete old rotated logs
    Write-Log "Deleting logs older than $RetentionDays days..."
    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    $oldLogs = Get-ChildItem -Path $LogPath -Filter "*.log.*" -File |
               Where-Object { $_.LastWriteTime -lt $cutoffDate }

    $deletedCount = 0
    foreach ($log in $oldLogs) {
        try {
            Remove-Item $log.FullName -Force
            Write-Log "Deleted: $($log.Name)"
            $deletedCount++
        } catch {
            Write-Log "Failed to delete: $($log.Name) - $_" -Level "WARN"
        }
    }
    Write-Log "Deleted $deletedCount old log files"

    # Step 2: Rotate current logs
    $date = Get-Date -Format "yyyyMMdd-HHmmss"
    $logsToRotate = @("access.log", "error.log")

    foreach ($logName in $logsToRotate) {
        $logFile = Join-Path $LogPath $logName
        if (Test-Path $logFile) {
            $fileInfo = Get-Item $logFile
            # Only rotate if file has content
            if ($fileInfo.Length -gt 0) {
                $rotatedName = "$logName.$date"
                $rotatedPath = Join-Path $LogPath $rotatedName

                try {
                    Copy-Item $logFile $rotatedPath -Force
                    # Clear the original log file (nginx will continue writing to it)
                    Clear-Content $logFile -Force
                    Write-Log "Rotated: $logName -> $rotatedName"
                } catch {
                    Write-Log "Failed to rotate: $logName - $_" -Level "ERROR"
                }
            } else {
                Write-Log "Skipping empty log: $logName"
            }
        } else {
            Write-Log "Log file not found: $logName" -Level "WARN"
        }
    }

    # Step 3: Signal nginx to reopen log files
    if (Test-OpenRestyRunning) {
        $nginxExe = Join-Path $OpenRestyPath "nginx.exe"
        if (Test-Path $nginxExe) {
            Write-Log "Signaling nginx to reopen log files..."
            try {
                & $nginxExe -s reopen
                if ($LASTEXITCODE -ne 0) {
                    Write-Log "nginx reopen signal returned exit code: $LASTEXITCODE" -Level "WARN"
                } else {
                    Write-Log "nginx log reopen signal sent successfully"
                }
            } catch {
                Write-Log "Failed to send reopen signal: $_" -Level "ERROR"
            }
        } else {
            Write-Log "nginx.exe not found at: $nginxExe" -Level "WARN"
        }
    } else {
        Write-Log "nginx is not running, skipping reopen signal"
    }

    # Step 4: Report disk usage
    $totalSize = (Get-ChildItem -Path $LogPath -File | Measure-Object -Property Length -Sum).Sum
    $totalSizeMB = [math]::Round($totalSize / 1MB, 2)
    Write-Log "Total log directory size: $totalSizeMB MB"

    $currentLogCount = (Get-ChildItem -Path $LogPath -Filter "*.log" -File).Count
    $rotatedLogCount = (Get-ChildItem -Path $LogPath -Filter "*.log.*" -File).Count
    Write-Log "Current logs: $currentLogCount, Rotated logs: $rotatedLogCount"

    Write-Log "Log rotation completed successfully"
    exit 0

} catch {
    Write-Log "Log rotation failed: $_" -Level "ERROR"
    exit 1
}
