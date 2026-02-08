#!/bin/bash
#==============================================================================
# Flatnet - Nebula Scripts Deployment
# Phase 3, Stage 1: Deploy Nebula scripts and templates from WSL2 to Windows
#
# This script:
#   1. Copies Nebula scripts from WSL2 repository to Windows
#   2. Copies configuration templates
#
# Usage:
#   ./scripts/deploy-nebula-scripts.sh
#   ./scripts/deploy-nebula-scripts.sh --dry-run
#
# Prerequisites:
#   - WSL2 with access to Windows drives (/mnt/f/)
#   - F:\flatnet directory exists
#==============================================================================

set -euo pipefail

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------

# Source paths (WSL2 repository)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
REPO_NEBULA_SCRIPTS="${REPO_ROOT}/scripts/nebula"
REPO_NEBULA_CONFIG="${REPO_ROOT}/config/nebula"

# Destination paths (Windows via WSL2 mount)
WIN_MOUNT="/mnt/f/flatnet"
WIN_SCRIPTS="${WIN_MOUNT}/scripts/nebula"
WIN_CONFIG_NEBULA="${WIN_MOUNT}/config/nebula"

# Colors for output
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
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
    printf '%b[INFO]%b %s\n' "${BLUE}" "${NC}" "$1"
}

log_success() {
    printf '%b[OK]%b %s\n' "${GREEN}" "${NC}" "$1"
}

log_warn() {
    printf '%b[WARN]%b %s\n' "${YELLOW}" "${NC}" "$1"
}

log_error() {
    printf '%b[ERROR]%b %s\n' "${RED}" "${NC}" "$1" >&2
}

show_help() {
    cat << EOF
Flatnet Nebula Scripts Deployment

Usage: $(basename "$0") [OPTIONS]

Options:
    --dry-run          Show what would be done without making changes
    --help             Show this help message

Examples:
    $(basename "$0")              # Deploy scripts and templates
    $(basename "$0") --dry-run    # Preview deployment

EOF
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

main() {
    local DRY_RUN=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
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
    echo "  Flatnet Nebula Scripts Deployment"
    echo "=========================================="
    echo ""

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "DRY-RUN mode: No changes will be made"
        echo ""
    fi

    # Check source directories
    if [[ ! -d "${REPO_NEBULA_SCRIPTS}" ]]; then
        log_error "Source scripts directory not found: ${REPO_NEBULA_SCRIPTS}"
        exit 1
    fi

    if [[ ! -d "${REPO_NEBULA_CONFIG}" ]]; then
        log_error "Source config directory not found: ${REPO_NEBULA_CONFIG}"
        exit 1
    fi

    # Check Windows mount
    if [[ ! -d "/mnt/f" ]]; then
        log_error "Windows F: drive not mounted at /mnt/f"
        log_info "Try: sudo mount -t drvfs F: /mnt/f"
        exit 1
    fi

    # Create destination directories
    log_info "Creating destination directories..."
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would create: ${WIN_SCRIPTS}"
        log_info "[DRY-RUN] Would create: ${WIN_CONFIG_NEBULA}"
    else
        mkdir -p "${WIN_SCRIPTS}"
        mkdir -p "${WIN_CONFIG_NEBULA}"
        log_success "Directories created"
    fi
    echo ""

    # Deploy scripts
    log_info "Deploying Nebula scripts..."
    local script_count=0
    if [[ "${DRY_RUN}" == "true" ]]; then
        for script in "${REPO_NEBULA_SCRIPTS}"/*.ps1; do
            if [[ -f "${script}" ]]; then
                log_info "[DRY-RUN] Would copy: $(basename "${script}") -> ${WIN_SCRIPTS}/"
                script_count=$((script_count + 1))
            fi
        done
    else
        for script in "${REPO_NEBULA_SCRIPTS}"/*.ps1; do
            if [[ -f "${script}" ]]; then
                cp "${script}" "${WIN_SCRIPTS}/"
                script_count=$((script_count + 1))
            fi
        done
        if [[ ${script_count} -gt 0 ]]; then
            log_success "Scripts deployed to ${WIN_SCRIPTS} (${script_count} files)"
        else
            log_warn "No .ps1 scripts found in ${REPO_NEBULA_SCRIPTS}"
        fi
    fi
    echo ""

    # Deploy configuration templates
    log_info "Deploying configuration templates..."
    local template_count=0
    if [[ "${DRY_RUN}" == "true" ]]; then
        for template in "${REPO_NEBULA_CONFIG}"/*.template; do
            if [[ -f "${template}" ]]; then
                log_info "[DRY-RUN] Would copy: $(basename "${template}") -> ${WIN_CONFIG_NEBULA}/"
                template_count=$((template_count + 1))
            fi
        done
    else
        # Only copy templates, not generated files
        for template in "${REPO_NEBULA_CONFIG}"/*.template; do
            if [[ -f "${template}" ]]; then
                cp "${template}" "${WIN_CONFIG_NEBULA}/"
                template_count=$((template_count + 1))
            fi
        done
        if [[ ${template_count} -gt 0 ]]; then
            log_success "Templates deployed to ${WIN_CONFIG_NEBULA} (${template_count} files)"
        else
            log_warn "No .template files found in ${REPO_NEBULA_CONFIG}"
        fi
    fi
    echo ""

    echo "=========================================="
    log_success "Deployment completed!"
    echo "=========================================="
    echo ""
    log_info "Deployed files:"
    log_info "  Scripts:   ${WIN_SCRIPTS}/"
    log_info "  Templates: ${WIN_CONFIG_NEBULA}/"
    echo ""
    log_info "Next steps (run in PowerShell as Administrator):"
    log_info "  1. cd F:\\flatnet\\scripts\\nebula"
    log_info "  2. .\\gen-ca.ps1"
    log_info "  3. .\\gen-host-cert.ps1 -Name lighthouse -Ip 10.100.0.1/16"
    log_info "  4. .\\setup-lighthouse.ps1 -Install -Start -SetupFirewall"
}

main "$@"
