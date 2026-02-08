#!/bin/bash
#
# Flatnet Restore Script
# Phase 4, Stage 4: Operations
#
# This script restores Flatnet configurations from backups.
#
# Usage:
#   ./restore.sh --list                    # List available backups
#   ./restore.sh --date 20240101_120000    # Restore specific backup
#   ./restore.sh --latest                  # Restore from latest backup
#   ./restore.sh --verify 20240101_120000  # Verify backup integrity
#   ./restore.sh --help                    # Show help
#

set -euo pipefail

# Script version
VERSION="1.0.0"

# Configuration
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/backup/flatnet}"
FLATNET_DIR="${FLATNET_DIR:-/home/kh/prj/flatnet}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-flatnet}"
GRAFANA_API_KEY="${GRAFANA_API_KEY:-}"  # Optional: use API key instead of basic auth
DRY_RUN=false
SKIP_CONFIRM=false
CREATE_PRE_RESTORE_BACKUP=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

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

# Help message
show_help() {
    cat << EOF
Flatnet Restore Script v${VERSION}

Usage: $(basename "$0") [OPTIONS]

Options:
    --list              List available backups
    --date DATE         Restore from specific backup (format: YYYYMMDD_HHMMSS)
    --latest            Restore from the latest backup
    --verify DATE       Verify backup integrity without restoring
    --dry-run           Show what would be done without executing
    --yes               Skip confirmation prompts
    --no-pre-backup     Skip creating backup of current state before restore
    --version           Show version information
    --help              Show this help message

Components to Restore:
    --cni               Restore CNI configurations
    --monitoring        Restore monitoring configurations
    --grafana           Restore Grafana dashboards
    --all               Restore all components (default)

Environment Variables:
    BACKUP_BASE_DIR     Base directory for backups (default: /backup/flatnet)
    FLATNET_DIR         Flatnet project directory (default: /home/kh/prj/flatnet)
    GRAFANA_URL         Grafana URL (default: http://localhost:3000)
    GRAFANA_USER        Grafana admin user (default: admin)
    GRAFANA_PASS        Grafana admin password (default: flatnet)
    GRAFANA_API_KEY     Grafana API key (optional, preferred over user/pass)

Examples:
    $(basename "$0") --list                     # List backups
    $(basename "$0") --latest                   # Restore latest
    $(basename "$0") --date 20240101_120000     # Restore specific
    $(basename "$0") --verify 20240101_120000   # Verify backup
    $(basename "$0") --latest --cni --dry-run   # Preview CNI restore
    $(basename "$0") --latest --no-pre-backup   # Restore without safety backup

EOF
}

# List available backups
list_backups() {
    log_info "Available backups in $BACKUP_BASE_DIR:"
    echo ""

    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        log_error "Backup directory does not exist: $BACKUP_BASE_DIR"
        exit 1
    fi

    # List backups with details
    printf "%-20s %-10s %-40s\n" "DATE" "SIZE" "CONTENTS"
    printf "%s\n" "$(printf '=%.0s' {1..70})"

    for backup in $(ls -1d "$BACKUP_BASE_DIR"/*/ 2>/dev/null | sort -r); do
        if [[ -d "$backup" ]]; then
            backup_name=$(basename "$backup")
            backup_size=$(du -sh "$backup" 2>/dev/null | cut -f1 || echo "?")
            backup_contents=$(ls "$backup" 2>/dev/null | tr '\n' ' ' | cut -c1-40)
            printf "%-20s %-10s %-40s\n" "$backup_name" "$backup_size" "$backup_contents"
        fi
    done

    echo ""
    total_count=$(ls -1d "$BACKUP_BASE_DIR"/*/ 2>/dev/null | wc -l)
    log_info "Total: $total_count backup(s)"
}

# Verify backup integrity
verify_backup() {
    local backup_date=$1
    local backup_dir="$BACKUP_BASE_DIR/$backup_date"

    log_info "Verifying backup: $backup_dir"

    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup not found: $backup_dir"
        exit 1
    fi

    # Check checksums if available
    if [[ -f "$backup_dir/checksums.sha256" ]]; then
        log_step "Verifying checksums..."
        (cd "$backup_dir" && sha256sum -c checksums.sha256 2>/dev/null) && {
            log_info "Checksum verification: PASSED"
        } || {
            log_error "Checksum verification: FAILED"
            exit 1
        }
    else
        log_warn "No checksums.sha256 found, skipping checksum verification"
    fi

    # Verify JSON files
    log_step "Verifying JSON files..."
    json_errors=0
    for json_file in $(find "$backup_dir" -name "*.json" 2>/dev/null); do
        if ! jq empty "$json_file" 2>/dev/null; then
            log_error "Invalid JSON: $json_file"
            ((json_errors++))
        fi
    done

    if [[ $json_errors -eq 0 ]]; then
        log_info "JSON validation: PASSED"
    else
        log_error "JSON validation: $json_errors file(s) failed"
    fi

    # Show backup contents
    log_step "Backup contents:"
    ls -la "$backup_dir"

    log_info "Verification complete"
}

# Get latest backup directory
get_latest_backup() {
    latest=$(ls -1d "$BACKUP_BASE_DIR"/*/ 2>/dev/null | sort -r | head -1)
    if [[ -z "$latest" ]]; then
        log_error "No backups found in $BACKUP_BASE_DIR"
        exit 1
    fi
    basename "$latest"
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

# Create pre-restore backup of current state
create_pre_restore_backup() {
    if [[ "$CREATE_PRE_RESTORE_BACKUP" != "true" ]]; then
        log_info "Skipping pre-restore backup (--no-pre-backup)"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create pre-restore backup"
        return 0
    fi

    local pre_backup_dir="$BACKUP_BASE_DIR/pre-restore_$(date +%Y%m%d_%H%M%S)"
    log_step "Creating pre-restore backup: $pre_backup_dir"

    mkdir -p "$pre_backup_dir"

    # Backup current CNI config
    if [[ -d "/etc/cni/net.d" ]]; then
        mkdir -p "$pre_backup_dir/cni-config"
        sudo cp -r /etc/cni/net.d/* "$pre_backup_dir/cni-config/" 2>/dev/null || true
    fi

    # Backup current monitoring config
    local monitoring_dir="$FLATNET_DIR/monitoring"
    if [[ -d "$monitoring_dir/prometheus" ]]; then
        cp -r "$monitoring_dir/prometheus" "$pre_backup_dir/prometheus-config" 2>/dev/null || true
    fi
    if [[ -d "$monitoring_dir/alertmanager" ]]; then
        cp -r "$monitoring_dir/alertmanager" "$pre_backup_dir/alertmanager-config" 2>/dev/null || true
    fi
    if [[ -d "$monitoring_dir/grafana" ]]; then
        cp -r "$monitoring_dir/grafana" "$pre_backup_dir/grafana-config" 2>/dev/null || true
    fi

    log_info "Pre-restore backup created: $pre_backup_dir"
    log_info "If restore fails, you can restore from: $pre_backup_dir"
}

# Confirm action
confirm_action() {
    local message=$1

    if [[ "$SKIP_CONFIRM" == "true" ]]; then
        return 0
    fi

    echo -e "${YELLOW}$message${NC}"
    read -p "Continue? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled"
        exit 0
    fi
}

# Restore CNI configurations
restore_cni_config() {
    local backup_dir=$1
    local cni_backup="$backup_dir/cni-config"

    log_step "Restoring CNI configurations..."

    if [[ ! -d "$cni_backup" ]]; then
        log_warn "CNI config backup not found in $backup_dir"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would copy $cni_backup/* to /etc/cni/net.d/"
        return 0
    fi

    sudo mkdir -p /etc/cni/net.d
    sudo cp -r "$cni_backup"/* /etc/cni/net.d/

    log_info "CNI configurations restored"
}

# Restore monitoring configurations
restore_monitoring_config() {
    local backup_dir=$1

    log_step "Restoring monitoring configurations..."

    local monitoring_dir="$FLATNET_DIR/monitoring"

    if [[ "$DRY_RUN" == "true" ]]; then
        [[ -d "$backup_dir/prometheus-config" ]] && log_info "[DRY RUN] Would restore prometheus config"
        [[ -d "$backup_dir/alertmanager-config" ]] && log_info "[DRY RUN] Would restore alertmanager config"
        [[ -d "$backup_dir/grafana-config" ]] && log_info "[DRY RUN] Would restore grafana config"
        return 0
    fi

    # Prometheus config
    if [[ -d "$backup_dir/prometheus-config" ]]; then
        rm -rf "$monitoring_dir/prometheus"
        cp -r "$backup_dir/prometheus-config" "$monitoring_dir/prometheus"
        log_info "Prometheus configuration restored"
    fi

    # Alertmanager config
    if [[ -d "$backup_dir/alertmanager-config" ]]; then
        rm -rf "$monitoring_dir/alertmanager"
        cp -r "$backup_dir/alertmanager-config" "$monitoring_dir/alertmanager"
        log_info "Alertmanager configuration restored"
    fi

    # Grafana config
    if [[ -d "$backup_dir/grafana-config" ]]; then
        rm -rf "$monitoring_dir/grafana"
        cp -r "$backup_dir/grafana-config" "$monitoring_dir/grafana"
        log_info "Grafana configuration restored"
    fi
}

# Restore Grafana dashboards via API
restore_grafana_dashboards() {
    local backup_dir=$1
    local dashboards_dir="$backup_dir/grafana-dashboards"

    log_step "Restoring Grafana dashboards..."

    if [[ ! -d "$dashboards_dir" ]]; then
        log_warn "Grafana dashboards backup not found in $backup_dir"
        return 0
    fi

    local auth_header
    auth_header=$(get_grafana_auth)

    # Check if Grafana is accessible
    if ! curl -sf "$GRAFANA_URL/api/health" > /dev/null 2>&1; then
        log_warn "Grafana is not accessible at $GRAFANA_URL, skipping dashboard restore"
        return 0
    fi

    # Verify authentication
    if ! curl -sf -H "$auth_header" "$GRAFANA_URL/api/org" > /dev/null 2>&1; then
        log_warn "Grafana authentication failed, skipping dashboard restore"
        log_warn "Check GRAFANA_USER/GRAFANA_PASS or GRAFANA_API_KEY"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        dashboard_count=$(ls -1 "$dashboards_dir"/*.json 2>/dev/null | wc -l)
        log_info "[DRY RUN] Would restore $dashboard_count dashboard(s)"
        return 0
    fi

    imported_count=0
    failed_count=0

    for file in "$dashboards_dir"/*.json; do
        if [[ -f "$file" ]]; then
            # Extract dashboard JSON and prepare for import
            dashboard=$(jq '.dashboard | .id = null' "$file" 2>/dev/null)

            if [[ -n "$dashboard" && "$dashboard" != "null" ]]; then
                response=$(curl -sf -X POST \
                    -H "Content-Type: application/json" \
                    -H "$auth_header" \
                    -d "{\"dashboard\": $dashboard, \"overwrite\": true}" \
                    "$GRAFANA_URL/api/dashboards/db" 2>/dev/null || echo '{"status":"error"}')

                # Grafana API returns "id" and "uid" on success, not "status": "success"
                if echo "$response" | jq -e '.uid' > /dev/null 2>&1; then
                    ((imported_count++))
                else
                    log_warn "Failed to import: $(basename "$file")"
                    log_warn "Response: $response"
                    ((failed_count++))
                fi
            fi
        fi
    done

    log_info "Imported $imported_count dashboard(s), $failed_count failed"
}

# Restore logging configurations
restore_logging_config() {
    local backup_dir=$1
    local logging_backup="$backup_dir/logging-config"

    log_step "Restoring logging configurations..."

    if [[ ! -d "$logging_backup" ]]; then
        log_warn "Logging config backup not found in $backup_dir"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would copy $logging_backup to $FLATNET_DIR/logging"
        return 0
    fi

    rm -rf "$FLATNET_DIR/logging"
    cp -r "$logging_backup" "$FLATNET_DIR/logging"

    log_info "Logging configurations restored"
}

# Full restore
restore_all() {
    local backup_date=$1
    local backup_dir="$BACKUP_BASE_DIR/$backup_date"

    log_info "Starting full restore from: $backup_dir"

    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup not found: $backup_dir"
        exit 1
    fi

    # Verify backup first
    verify_backup "$backup_date"

    # Confirm
    confirm_action "This will restore configurations from $backup_date. Services may need to be restarted."

    # Create pre-restore backup
    create_pre_restore_backup

    # Stop services if not dry run
    if [[ "$DRY_RUN" != "true" ]]; then
        log_step "Consider stopping services before restore..."
        log_info "Run: cd $FLATNET_DIR/monitoring && podman-compose down"
    fi

    # Restore components
    restore_cni_config "$backup_dir"
    restore_monitoring_config "$backup_dir"
    restore_logging_config "$backup_dir"
    restore_grafana_dashboards "$backup_dir"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Restore preview completed"
    else
        log_info "Restore completed"
        log_info ""
        log_info "Next steps:"
        log_info "  1. Restart services: cd $FLATNET_DIR/monitoring && podman-compose up -d"
        log_info "  2. Verify services: podman-compose ps"
        log_info "  3. Check health: curl http://localhost:9090/-/ready"
    fi
}

# Main execution
main() {
    local action=""
    local backup_date=""
    local components="all"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --list)
                action="list"
                shift
                ;;
            --date)
                action="restore"
                backup_date="$2"
                shift 2
                ;;
            --latest)
                action="restore"
                backup_date="latest"
                shift
                ;;
            --verify)
                action="verify"
                backup_date="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --yes|-y)
                SKIP_CONFIRM=true
                shift
                ;;
            --no-pre-backup)
                CREATE_PRE_RESTORE_BACKUP=false
                shift
                ;;
            --version)
                echo "Flatnet Restore Script v${VERSION}"
                exit 0
                ;;
            --cni)
                components="cni"
                shift
                ;;
            --monitoring)
                components="monitoring"
                shift
                ;;
            --grafana)
                components="grafana"
                shift
                ;;
            --all)
                components="all"
                shift
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

    # Check requirements before proceeding
    check_requirements

    # Execute action
    case $action in
        list)
            list_backups
            ;;
        verify)
            verify_backup "$backup_date"
            ;;
        restore)
            if [[ "$backup_date" == "latest" ]]; then
                backup_date=$(get_latest_backup)
                log_info "Using latest backup: $backup_date"
            fi

            if [[ "$components" == "all" ]]; then
                restore_all "$backup_date"
            else
                backup_dir="$BACKUP_BASE_DIR/$backup_date"
                if [[ ! -d "$backup_dir" ]]; then
                    log_error "Backup not found: $backup_dir"
                    exit 1
                fi

                confirm_action "This will restore $components from $backup_date."

                case $components in
                    cni)
                        restore_cni_config "$backup_dir"
                        ;;
                    monitoring)
                        restore_monitoring_config "$backup_dir"
                        ;;
                    grafana)
                        restore_grafana_dashboards "$backup_dir"
                        ;;
                esac
            fi
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"

exit 0
