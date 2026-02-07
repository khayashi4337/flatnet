#!/bin/bash
#==============================================================================
# Flatnet Gateway - Configuration Deployment Script
# Phase 1, Stage 1: Deploy configuration from WSL2 to Windows
#
# This script:
#   1. Copies configuration files from WSL2 repository to Windows
#   2. Validates the nginx configuration
#   3. Optionally reloads OpenResty
#
# Usage:
#   ./scripts/deploy-config.sh           # Deploy only
#   ./scripts/deploy-config.sh --reload  # Deploy and reload
#   ./scripts/deploy-config.sh --help    # Show help
#
# Prerequisites:
#   - WSL2 with access to Windows drives (/mnt/f/)
#   - OpenResty installed at F:\flatnet\openresty
#   - Config directory exists at F:\flatnet\config
#==============================================================================

set -euo pipefail

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------

# Source paths (WSL2 repository)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
REPO_CONFIG="${REPO_ROOT}/config/openresty"

# Destination paths (Windows via WSL2 mount)
WIN_MOUNT="/mnt/f/flatnet"
WIN_CONFIG="${WIN_MOUNT}/config"
WIN_LOGS="${WIN_MOUNT}/logs"

# Windows native paths (for nginx.exe)
WIN_CONFIG_NATIVE="F:/flatnet/config"

# OpenResty binary
OPENRESTY_BIN="${WIN_MOUNT}/openresty/nginx.exe"

# Default configuration file (can be overridden with --config option)
# Options: nginx.conf (default), nginx-forgejo.conf (for Forgejo)
CONFIG_FILE="nginx.conf"

# Colors for output (if terminal supports it)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

show_help() {
    cat << EOF
Flatnet Configuration Deployment Script

Usage: $(basename "$0") [OPTIONS]

Options:
    --reload           Reload OpenResty after deploying configuration
    --force            Force deployment even if validation fails (not recommended)
    --dry-run          Show what would be done without making changes
    --config FILE      Specify config file to use (default: nginx.conf)
                       Available: nginx.conf, nginx-forgejo.conf
    --forgejo          Shortcut for --config nginx-forgejo.conf
    --help             Show this help message

Examples:
    $(basename "$0")                    # Deploy with nginx.conf
    $(basename "$0") --reload           # Deploy and reload OpenResty
    $(basename "$0") --forgejo --reload # Deploy Forgejo config and reload
    $(basename "$0") --dry-run          # Preview deployment

EOF
}

#------------------------------------------------------------------------------
# Validation Functions
#------------------------------------------------------------------------------

check_prerequisites() {
    local has_error=0

    # Check source configuration directory
    if [[ ! -d "${REPO_CONFIG}" ]]; then
        log_error "Source configuration directory not found: ${REPO_CONFIG}"
        has_error=1
    fi

    # Check nginx.conf exists
    if [[ ! -f "${REPO_CONFIG}/nginx.conf" ]]; then
        log_error "nginx.conf not found in ${REPO_CONFIG}"
        has_error=1
    fi

    # Check Windows mount is accessible
    if [[ ! -d "/mnt/f" ]]; then
        log_error "Windows F: drive not mounted at /mnt/f"
        log_info "Try: sudo mount -t drvfs F: /mnt/f"
        has_error=1
    fi

    # Check destination directory
    if [[ ! -d "${WIN_CONFIG}" ]]; then
        log_warn "Destination config directory not found: ${WIN_CONFIG}"
        log_info "Creating directory..."
        if [[ "${DRY_RUN:-false}" != "true" ]]; then
            mkdir -p "${WIN_CONFIG}" || {
                log_error "Failed to create ${WIN_CONFIG}"
                has_error=1
            }
        fi
    fi

    # Check logs directory
    if [[ ! -d "${WIN_LOGS}" ]]; then
        log_warn "Logs directory not found: ${WIN_LOGS}"
        log_info "Creating directory..."
        if [[ "${DRY_RUN:-false}" != "true" ]]; then
            mkdir -p "${WIN_LOGS}" || {
                log_error "Failed to create ${WIN_LOGS}"
                has_error=1
            }
        fi
    fi

    # Check OpenResty binary
    if [[ ! -f "${OPENRESTY_BIN}" ]]; then
        log_error "OpenResty binary not found: ${OPENRESTY_BIN}"
        log_info "Please install OpenResty to F:\\flatnet\\openresty"
        has_error=1
    fi

    return ${has_error}
}

#------------------------------------------------------------------------------
# Deployment Functions
#------------------------------------------------------------------------------

deploy_config() {
    log_info "Deploying configuration files..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would copy: ${REPO_CONFIG}/* -> ${WIN_CONFIG}/"
        return 0
    fi

    # Create backup of existing config if it exists
    if [[ -f "${WIN_CONFIG}/nginx.conf" ]]; then
        local backup_file="${WIN_CONFIG}/nginx.conf.backup.$(date +%Y%m%d_%H%M%S)"
        cp "${WIN_CONFIG}/nginx.conf" "${backup_file}"
        log_info "Backed up existing config to: $(basename "${backup_file}")"
    fi

    # Copy all configuration files
    cp -r "${REPO_CONFIG}"/* "${WIN_CONFIG}/"

    log_success "Configuration files deployed to ${WIN_CONFIG}"
}

test_config() {
    log_info "Testing nginx configuration (${CONFIG_FILE})..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would test: ${OPENRESTY_BIN} -c ${WIN_CONFIG_NATIVE}/${CONFIG_FILE} -t"
        return 0
    fi

    # Run nginx config test
    local test_output
    if test_output=$("${OPENRESTY_BIN}" -c "${WIN_CONFIG_NATIVE}/${CONFIG_FILE}" -t 2>&1); then
        log_success "Configuration test passed"
        return 0
    else
        log_error "Configuration test failed:"
        echo "${test_output}" >&2
        return 1
    fi
}

reload_openresty() {
    log_info "Reloading OpenResty..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY-RUN] Would reload: ${OPENRESTY_BIN} -c ${WIN_CONFIG_NATIVE}/${CONFIG_FILE} -s reload"
        return 0
    fi

    # Check if nginx is running
    if ! pgrep -x "nginx.exe" > /dev/null 2>&1; then
        log_warn "OpenResty is not running. Skipping reload."
        log_info "Start OpenResty with: ${OPENRESTY_BIN} -c ${WIN_CONFIG_NATIVE}/${CONFIG_FILE}"
        return 0
    fi

    # Reload nginx
    if "${OPENRESTY_BIN}" -c "${WIN_CONFIG_NATIVE}/${CONFIG_FILE}" -s reload 2>&1; then
        log_success "OpenResty reloaded successfully"
    else
        log_error "Failed to reload OpenResty"
        return 1
    fi
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

main() {
    local do_reload=false
    local force=false
    DRY_RUN=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reload)
                do_reload=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --config)
                if [[ -n "${2:-}" ]]; then
                    CONFIG_FILE="$2"
                    shift 2
                else
                    log_error "--config requires a filename argument"
                    exit 1
                fi
                ;;
            --forgejo)
                CONFIG_FILE="nginx-forgejo.conf"
                shift
                ;;
            --help|-h)
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

    echo "=========================================="
    echo "  Flatnet Configuration Deployment"
    echo "=========================================="
    echo ""

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "DRY-RUN mode: No changes will be made"
        echo ""
    fi

    # Check prerequisites
    log_info "Checking prerequisites..."
    if ! check_prerequisites; then
        if [[ "${force}" != "true" ]]; then
            log_error "Prerequisites check failed. Use --force to override (not recommended)."
            exit 1
        fi
        log_warn "Continuing despite failed prerequisites (--force)"
    fi
    log_success "Prerequisites check passed"
    echo ""

    # Deploy configuration
    if ! deploy_config; then
        log_error "Deployment failed"
        exit 1
    fi
    echo ""

    # Test configuration
    if ! test_config; then
        if [[ "${force}" != "true" ]]; then
            log_error "Configuration test failed. Deployment aborted."
            log_info "Fix the configuration and try again, or use --force to skip validation."
            exit 1
        fi
        log_warn "Continuing despite test failure (--force)"
    fi
    echo ""

    # Reload if requested
    if [[ "${do_reload}" == "true" ]]; then
        if ! reload_openresty; then
            log_error "Reload failed"
            exit 1
        fi
        echo ""
    fi

    echo "=========================================="
    log_success "Deployment completed successfully!"
    echo "=========================================="

    if [[ "${do_reload}" != "true" ]]; then
        echo ""
        log_info "To apply changes, either:"
        log_info "  1. Reload: ${OPENRESTY_BIN} -c ${WIN_CONFIG_NATIVE}/${CONFIG_FILE} -s reload"
        log_info "  2. Restart: Run this script with --reload option"
    fi

    # Show config file being used
    if [[ "${CONFIG_FILE}" != "nginx.conf" ]]; then
        log_info "Using configuration file: ${CONFIG_FILE}"
    fi
}

main "$@"
