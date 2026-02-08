#!/bin/bash
#==============================================================================
# Forgejo Container Start Script - Example
# Phase 1, Stage 3: Forgejo Integration
#
# This is a simplified example script for reference.
# The actual script at scripts/forgejo/run.sh has the same core functionality.
#
# Usage:
#   chmod +x run.sh
#   ./run.sh
#
# Prerequisites:
#   - Podman installed
#   - Forgejo image: podman pull codeberg.org/forgejo/forgejo:9
#==============================================================================

set -euo pipefail

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------

# コンテナ名
CONTAINER_NAME="forgejo"

# Forgejo イメージ（バージョン固定を推奨）
IMAGE="codeberg.org/forgejo/forgejo:9"

# データディレクトリ（ホスト側）
DATA_DIR="${HOME}/forgejo/data"
CONFIG_DIR="${HOME}/forgejo/config"

# ポート設定
HOST_PORT=3000
CONTAINER_PORT=3000

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

# データディレクトリの作成
if [ ! -d "${DATA_DIR}" ]; then
    log_info "Creating data directory: ${DATA_DIR}"
    mkdir -p "${DATA_DIR}"
fi

if [ ! -d "${CONFIG_DIR}" ]; then
    log_info "Creating config directory: ${CONFIG_DIR}"
    mkdir -p "${CONFIG_DIR}"
fi

# 既存コンテナの停止・削除
if podman container exists "${CONTAINER_NAME}"; then
    log_info "Stopping existing container..."
    podman stop -t 30 "${CONTAINER_NAME}" || true
    podman rm --force "${CONTAINER_NAME}" || true
fi

# コンテナを起動
log_info "Starting Forgejo container..."
podman run -d \
    --name "${CONTAINER_NAME}" \
    -p "${HOST_PORT}:${CONTAINER_PORT}" \
    -v "${DATA_DIR}:/data:Z" \
    -v "${CONFIG_DIR}:/etc/gitea:Z" \
    "${IMAGE}"

# 起動確認
if podman container exists "${CONTAINER_NAME}"; then
    log_info "Forgejo started successfully."
    echo ""
    echo "Access Forgejo at: http://localhost:${HOST_PORT}"
    echo "Container ID: $(podman ps -q -f name="${CONTAINER_NAME}")"
    echo ""
    echo "Useful commands:"
    echo "  View logs:    podman logs ${CONTAINER_NAME}"
    echo "  Stop:         podman stop ${CONTAINER_NAME}"
    echo "  Restart:      podman restart ${CONTAINER_NAME}"
else
    log_error "Failed to start Forgejo container"
    exit 1
fi
