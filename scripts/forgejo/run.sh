#!/bin/bash
set -euo pipefail

# Forgejo コンテナを起動
CONTAINER_NAME="forgejo"
IMAGE="codeberg.org/forgejo/forgejo:9"
DATA_DIR="${HOME}/forgejo/data"
CONFIG_DIR="${HOME}/forgejo/config"

# データディレクトリが存在しない場合は作成
if [ ! -d "${DATA_DIR}" ]; then
    echo "Creating data directory: ${DATA_DIR}"
    mkdir -p "${DATA_DIR}"
fi

if [ ! -d "${CONFIG_DIR}" ]; then
    echo "Creating config directory: ${CONFIG_DIR}"
    mkdir -p "${CONFIG_DIR}"
fi

# 既存コンテナがあれば停止・削除
if podman container exists "${CONTAINER_NAME}"; then
    echo "Stopping existing container..."
    podman stop -t 30 "${CONTAINER_NAME}" || true
    podman rm --force "${CONTAINER_NAME}" || true
fi

# コンテナを起動
echo "Starting Forgejo..."
podman run -d \
    --name "${CONTAINER_NAME}" \
    -p 3000:3000 \
    -v "${DATA_DIR}:/data:Z" \
    -v "${CONFIG_DIR}:/etc/gitea:Z" \
    "${IMAGE}"

# 起動確認
if podman container exists "${CONTAINER_NAME}"; then
    echo "Forgejo started successfully."
    echo "Access at http://localhost:3000"
    echo "Container ID: $(podman ps -q -f name="${CONTAINER_NAME}")"
else
    echo "ERROR: Failed to start Forgejo container" >&2
    exit 1
fi
