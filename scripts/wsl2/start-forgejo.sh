#!/bin/bash
# Flatnet - Forgejo Startup Script
# Phase 1, Stage 3: Forgejo Integration
#
# This script starts Forgejo container using Podman.
# It is designed to be used for manual startup or when not using Quadlet.
#
# Usage:
#   ./scripts/wsl2/start-forgejo.sh [options]
#
# Options:
#   --force    Force restart even if container is running
#   --pull     Pull latest image before starting
#   --logs     Show container logs after starting
#   --help     Show this help message
#
# Prerequisites:
#   - Podman installed on WSL2
#   - Data directories: ~/forgejo/data and ~/forgejo/config
#   - Internet access (for initial image pull)

set -euo pipefail

#==============================================================================
# Configuration
#==============================================================================

CONTAINER_NAME="forgejo"
IMAGE="codeberg.org/forgejo/forgejo:9"
DATA_DIR="${HOME}/forgejo/data"
CONFIG_DIR="${HOME}/forgejo/config"
HOST_PORT="3000"
CONTAINER_PORT="3000"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#==============================================================================
# Helper Functions
#==============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    head -30 "$0" | grep -E '^#' | sed 's/^# //' | sed 's/^#//'
}

#==============================================================================
# Parse Arguments
#==============================================================================

FORCE_RESTART=false
PULL_IMAGE=false
SHOW_LOGS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_RESTART=true
            shift
            ;;
        --pull)
            PULL_IMAGE=true
            shift
            ;;
        --logs)
            SHOW_LOGS=true
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

#==============================================================================
# Pre-flight Checks
#==============================================================================

# Check if podman is available
if ! command -v podman &> /dev/null; then
    log_error "podman is not installed. Please install podman first."
    exit 1
fi

# Create data directories if they don't exist
if [[ ! -d "${DATA_DIR}" ]]; then
    log_info "Creating data directory: ${DATA_DIR}"
    mkdir -p "${DATA_DIR}"
fi

if [[ ! -d "${CONFIG_DIR}" ]]; then
    log_info "Creating config directory: ${CONFIG_DIR}"
    mkdir -p "${CONFIG_DIR}"
fi

# Check if port is already in use (by something other than our container)
if ss -tlnp 2>/dev/null | grep -q ":${HOST_PORT}" && ! podman ps --filter "name=${CONTAINER_NAME}" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    log_warn "Port ${HOST_PORT} is already in use. Forgejo may not start properly."
fi

#==============================================================================
# Pull Image (if requested)
#==============================================================================

if [[ "${PULL_IMAGE}" == "true" ]]; then
    log_info "Pulling latest image: ${IMAGE}"
    podman pull "${IMAGE}"
fi

#==============================================================================
# Handle Existing Container
#==============================================================================

if podman container exists "${CONTAINER_NAME}" 2>/dev/null; then
    if [[ "${FORCE_RESTART}" == "true" ]]; then
        log_info "Stopping existing container..."
        podman stop "${CONTAINER_NAME}" 2>/dev/null || true
        log_info "Removing existing container..."
        podman rm "${CONTAINER_NAME}" 2>/dev/null || true
    else
        # Check if container is running
        if podman ps --filter "name=${CONTAINER_NAME}" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
            log_info "Container '${CONTAINER_NAME}' is already running."
            log_info "Use --force to restart, or check status with: podman ps"
            exit 0
        else
            log_info "Container exists but not running. Removing..."
            podman rm "${CONTAINER_NAME}" 2>/dev/null || true
        fi
    fi
fi

#==============================================================================
# Start Container
#==============================================================================

log_info "Starting Forgejo container..."

podman run -d \
    --name "${CONTAINER_NAME}" \
    -p "${HOST_PORT}:${CONTAINER_PORT}" \
    -v "${DATA_DIR}:/data:Z" \
    -v "${CONFIG_DIR}:/etc/gitea:Z" \
    -e TZ=Asia/Tokyo \
    "${IMAGE}"

#==============================================================================
# Verify Startup
#==============================================================================

# Wait for container to start
sleep 2

if podman ps --filter "name=${CONTAINER_NAME}" --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    log_info "Forgejo started successfully!"
    log_info "Access Forgejo at: http://localhost:${HOST_PORT}"
    log_info ""
    log_info "Container info:"
    podman ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
else
    log_error "Failed to start Forgejo container."
    log_error "Check logs with: podman logs ${CONTAINER_NAME}"
    exit 1
fi

#==============================================================================
# Show Logs (if requested)
#==============================================================================

if [[ "${SHOW_LOGS}" == "true" ]]; then
    log_info ""
    log_info "Container logs (Ctrl+C to exit):"
    podman logs -f "${CONTAINER_NAME}"
fi
