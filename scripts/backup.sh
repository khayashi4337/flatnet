#!/bin/bash
#
# Flatnet Backup Script
# Phase 4, Stage 4: Operations
#
# This script creates backups of Flatnet configurations, Grafana dashboards,
# and Prometheus snapshots.
#
# Usage:
#   ./backup.sh                  # Run backup with default settings
#   ./backup.sh --retention 14   # Custom retention in days
#   ./backup.sh --dry-run        # Show what would be done
#   ./backup.sh --help           # Show help
#

set -euo pipefail

# Script version
VERSION="1.0.0"

# Configuration
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/backup/flatnet}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
FLATNET_DIR="${FLATNET_DIR:-/home/kh/prj/flatnet}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-flatnet}"
GRAFANA_API_KEY="${GRAFANA_API_KEY:-}"  # Optional: use API key instead of basic auth
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
DRY_RUN=false
VERIFY_AFTER_BACKUP=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help message
show_help() {
    cat << EOF
Flatnet Backup Script v${VERSION}

Usage: $(basename "$0") [OPTIONS]

Options:
    --retention DAYS    Number of days to keep backups (default: 7)
    --dry-run           Show what would be done without executing
    --no-verify         Skip verification after backup
    --version           Show version information
    --help              Show this help message

Environment Variables:
    BACKUP_BASE_DIR     Base directory for backups (default: /backup/flatnet)
    FLATNET_DIR         Flatnet project directory (default: /home/kh/prj/flatnet)
    GRAFANA_URL         Grafana URL (default: http://localhost:3000)
    GRAFANA_USER        Grafana admin user (default: admin)
    GRAFANA_PASS        Grafana admin password (default: flatnet)
    GRAFANA_API_KEY     Grafana API key (optional, preferred over user/pass)
    PROMETHEUS_URL      Prometheus URL (default: http://localhost:9090)

Examples:
    $(basename "$0")                    # Standard backup
    $(basename "$0") --retention 14     # Keep backups for 14 days
    $(basename "$0") --dry-run          # Preview backup operations
    $(basename "$0") --no-verify        # Skip post-backup verification

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --retention)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-verify)
            VERIFY_AFTER_BACKUP=false
            shift
            ;;
        --version)
            echo "Flatnet Backup Script v${VERSION}"
            exit 0
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check required commands
check_requirements() {
    local missing=0
    for cmd in curl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required command not found: $cmd"
            missing=1
        fi
    done
    if [[ $missing -eq 1 ]]; then
        log_error "Install missing commands and retry"
        exit 1
    fi
}

check_requirements

# Create backup directory
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_BASE_DIR/$BACKUP_DATE"

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would create backup directory: $BACKUP_DIR"
else
    mkdir -p "$BACKUP_DIR"
    log_info "Created backup directory: $BACKUP_DIR"
fi

# Backup CNI configurations
backup_cni_config() {
    log_info "Backing up CNI configurations..."

    CNI_CONFIG_DIR="/etc/cni/net.d"
    if [[ -d "$CNI_CONFIG_DIR" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would copy $CNI_CONFIG_DIR to $BACKUP_DIR/cni-config"
        else
            mkdir -p "$BACKUP_DIR/cni-config"
            sudo cp -r "$CNI_CONFIG_DIR"/* "$BACKUP_DIR/cni-config/" 2>/dev/null || true
            log_info "CNI configuration backed up"
        fi
    else
        log_warn "CNI config directory not found: $CNI_CONFIG_DIR"
    fi
}

# Backup monitoring configurations
backup_monitoring_config() {
    log_info "Backing up monitoring configurations..."

    MONITORING_DIR="$FLATNET_DIR/monitoring"
    if [[ -d "$MONITORING_DIR" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would copy monitoring configs to $BACKUP_DIR/"
        else
            # Prometheus config
            if [[ -d "$MONITORING_DIR/prometheus" ]]; then
                cp -r "$MONITORING_DIR/prometheus" "$BACKUP_DIR/prometheus-config"
            fi

            # Alertmanager config
            if [[ -d "$MONITORING_DIR/alertmanager" ]]; then
                cp -r "$MONITORING_DIR/alertmanager" "$BACKUP_DIR/alertmanager-config"
            fi

            # Grafana config
            if [[ -d "$MONITORING_DIR/grafana" ]]; then
                cp -r "$MONITORING_DIR/grafana" "$BACKUP_DIR/grafana-config"
            fi

            log_info "Monitoring configurations backed up"
        fi
    else
        log_warn "Monitoring directory not found: $MONITORING_DIR"
    fi
}

# Get Grafana auth header
get_grafana_auth() {
    if [[ -n "$GRAFANA_API_KEY" ]]; then
        echo "Authorization: Bearer $GRAFANA_API_KEY"
    else
        # Use basic auth - encode credentials
        echo "Authorization: Basic $(echo -n "$GRAFANA_USER:$GRAFANA_PASS" | base64)"
    fi
}

# Export Grafana dashboards via API
backup_grafana_dashboards() {
    log_info "Exporting Grafana dashboards..."

    local auth_header
    auth_header=$(get_grafana_auth)

    # Check if Grafana is accessible
    if ! curl -sf "$GRAFANA_URL/api/health" > /dev/null 2>&1; then
        log_warn "Grafana is not accessible at $GRAFANA_URL, skipping dashboard export"
        return 0
    fi

    # Verify authentication
    if ! curl -sf -H "$auth_header" "$GRAFANA_URL/api/org" > /dev/null 2>&1; then
        log_warn "Grafana authentication failed, skipping dashboard export"
        log_warn "Check GRAFANA_USER/GRAFANA_PASS or GRAFANA_API_KEY"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would export Grafana dashboards to $BACKUP_DIR/grafana-dashboards"
        return 0
    fi

    mkdir -p "$BACKUP_DIR/grafana-dashboards"

    # Get list of dashboards
    dashboard_list=$(curl -sf -H "$auth_header" \
        "$GRAFANA_URL/api/search?type=dash-db" 2>/dev/null || echo "[]")

    if [[ "$dashboard_list" == "[]" ]]; then
        log_warn "No dashboards found in Grafana"
        return 0
    fi

    # Export each dashboard
    dashboard_count=0
    for uid in $(echo "$dashboard_list" | jq -r '.[].uid' 2>/dev/null); do
        if [[ -n "$uid" && "$uid" != "null" ]]; then
            if curl -sf -H "$auth_header" \
                "$GRAFANA_URL/api/dashboards/uid/$uid" \
                > "$BACKUP_DIR/grafana-dashboards/$uid.json" 2>/dev/null; then
                ((dashboard_count++))
            fi
        fi
    done

    log_info "Exported $dashboard_count Grafana dashboards"
}

# Create Prometheus snapshot
backup_prometheus_snapshot() {
    log_info "Creating Prometheus snapshot..."

    # Check if Prometheus is accessible and admin API is enabled
    if ! curl -sf "$PROMETHEUS_URL/-/ready" > /dev/null 2>&1; then
        log_warn "Prometheus is not accessible at $PROMETHEUS_URL, skipping snapshot"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Prometheus snapshot"
        return 0
    fi

    # Try to create snapshot
    response=$(curl -sf -X POST "$PROMETHEUS_URL/api/v1/admin/tsdb/snapshot" 2>/dev/null || echo '{"status":"error"}')

    if echo "$response" | jq -e '.status == "success"' > /dev/null 2>&1; then
        snapshot_name=$(echo "$response" | jq -r '.data.name')
        log_info "Prometheus snapshot created: $snapshot_name"

        # Record snapshot info
        echo "$snapshot_name" > "$BACKUP_DIR/prometheus-snapshot.txt"
    else
        log_warn "Failed to create Prometheus snapshot (admin API may be disabled)"
        log_warn "Response: $response"
    fi
}

# Backup logging configurations
backup_logging_config() {
    log_info "Backing up logging configurations..."

    LOGGING_DIR="$FLATNET_DIR/logging"
    if [[ -d "$LOGGING_DIR" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would copy logging configs to $BACKUP_DIR/logging-config"
        else
            cp -r "$LOGGING_DIR" "$BACKUP_DIR/logging-config"
            log_info "Logging configurations backed up"
        fi
    else
        log_warn "Logging directory not found: $LOGGING_DIR"
    fi
}

# Clean up old backups
cleanup_old_backups() {
    log_info "Cleaning up backups older than $RETENTION_DAYS days..."

    if [[ "$DRY_RUN" == "true" ]]; then
        old_backups=$(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -mtime +"$RETENTION_DAYS" 2>/dev/null | wc -l)
        log_info "[DRY RUN] Would delete $old_backups old backup directories"
        return 0
    fi

    # Find and delete old backup directories
    deleted_count=0
    while IFS= read -r dir; do
        if [[ -n "$dir" && "$dir" != "$BACKUP_BASE_DIR" ]]; then
            rm -rf "$dir"
            ((deleted_count++))
        fi
    done < <(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -mtime +"$RETENTION_DAYS" 2>/dev/null)

    if [[ $deleted_count -gt 0 ]]; then
        log_info "Deleted $deleted_count old backup directories"
    else
        log_info "No old backups to delete"
    fi
}

# Generate backup summary
generate_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    log_info "Generating backup summary..."

    cat > "$BACKUP_DIR/backup-summary.txt" << EOF
Flatnet Backup Summary
======================
Date: $(date)
Backup Directory: $BACKUP_DIR

Contents:
$(ls -la "$BACKUP_DIR" 2>/dev/null || echo "N/A")

Sizes:
$(du -sh "$BACKUP_DIR"/* 2>/dev/null || echo "N/A")

Total Size: $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "N/A")
EOF

    log_info "Backup summary saved to $BACKUP_DIR/backup-summary.txt"
}

# Generate checksums
generate_checksums() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would generate checksums"
        return 0
    fi

    log_info "Generating checksums..."

    (cd "$BACKUP_DIR" && find . -type f ! -name "checksums.sha256" -exec sha256sum {} \; > checksums.sha256)

    log_info "Checksums saved to $BACKUP_DIR/checksums.sha256"
}

# Verify backup integrity
verify_backup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify backup"
        return 0
    fi

    if [[ "$VERIFY_AFTER_BACKUP" != "true" ]]; then
        log_info "Skipping verification (--no-verify)"
        return 0
    fi

    log_info "Verifying backup integrity..."

    local errors=0

    # Verify checksums
    if [[ -f "$BACKUP_DIR/checksums.sha256" ]]; then
        if (cd "$BACKUP_DIR" && sha256sum -c checksums.sha256 > /dev/null 2>&1); then
            log_info "Checksum verification: PASSED"
        else
            log_error "Checksum verification: FAILED"
            ((errors++))
        fi
    fi

    # Verify JSON files
    for json_file in $(find "$BACKUP_DIR" -name "*.json" 2>/dev/null); do
        if ! jq empty "$json_file" 2>/dev/null; then
            log_error "Invalid JSON: $json_file"
            ((errors++))
        fi
    done

    if [[ $errors -eq 0 ]]; then
        log_info "Backup verification: PASSED"
    else
        log_error "Backup verification: FAILED ($errors errors)"
        return 1
    fi
}

# Main execution
main() {
    log_info "Starting Flatnet backup..."
    log_info "Backup directory: $BACKUP_DIR"
    log_info "Retention: $RETENTION_DAYS days"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "=== DRY RUN MODE - No changes will be made ==="
    fi

    # Run backup steps
    backup_cni_config
    backup_monitoring_config
    backup_logging_config
    backup_grafana_dashboards
    backup_prometheus_snapshot

    # Post-backup tasks
    generate_summary
    generate_checksums
    verify_backup
    cleanup_old_backups

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Backup preview completed"
    else
        log_info "Backup completed successfully: $BACKUP_DIR"

        # Show backup size
        total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "unknown")
        log_info "Total backup size: $total_size"
    fi
}

# Run main function
main

exit 0
