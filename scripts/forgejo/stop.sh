#!/bin/bash
set -euo pipefail

# Forgejo コンテナを停止
CONTAINER_NAME="forgejo"

if podman container exists "${CONTAINER_NAME}"; then
    echo "Stopping Forgejo container..."
    podman stop -t 30 "${CONTAINER_NAME}" || true
    podman rm --force "${CONTAINER_NAME}"
    echo "Forgejo stopped and removed."
else
    echo "Forgejo container is not running."
fi
