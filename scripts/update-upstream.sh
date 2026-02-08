#!/bin/bash
# Flatnet - WSL2 Upstream IP Update Script
# Phase 1, Stage 2-3: WSL2 Proxy / Forgejo Integration
#
# WSL2 IP を取得して nginx 設定ファイルの upstream を更新し、デプロイするスクリプト
#
# 使用方法:
#   ./scripts/update-upstream.sh           # IP 更新 + デプロイのみ
#   ./scripts/update-upstream.sh --reload  # IP 更新 + デプロイ + nginx リロード
#
# 前提条件:
#   - scripts/get-wsl2-ip.sh が存在すること
#   - scripts/deploy-config.sh が存在すること
#   - config/openresty/nginx.conf または nginx-forgejo.conf が存在すること

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${PROJECT_DIR}/config/openresty"
GET_IP_SCRIPT="${SCRIPT_DIR}/get-wsl2-ip.sh"
DEPLOY_SCRIPT="${SCRIPT_DIR}/deploy-config.sh"

# 更新対象の設定ファイルリスト
CONFIG_FILES=(
    "${CONFIG_DIR}/nginx.conf"
    "${CONFIG_DIR}/nginx-forgejo.conf"
    "${CONFIG_DIR}/conf.d/forgejo.conf"
)

# スクリプトの存在確認
if [[ ! -x "${GET_IP_SCRIPT}" ]]; then
    echo "Error: ${GET_IP_SCRIPT} not found or not executable" >&2
    exit 1
fi

# WSL2 IP を取得
WSL2_IP=$("${GET_IP_SCRIPT}")
if [[ -z "${WSL2_IP}" ]]; then
    echo "Error: Failed to get WSL2 IP address" >&2
    exit 1
fi

# IP アドレス形式のバリデーション（セキュリティ対策）
if [[ ! "${WSL2_IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid IP address format: ${WSL2_IP}" >&2
    exit 1
fi
echo "WSL2 IP: ${WSL2_IP}"

# 設定ファイルの upstream IP を置換
# パターン: server 172.x.x.x:ポート; → server ${WSL2_IP}:ポート;
UPDATED_COUNT=0
for CONFIG_FILE in "${CONFIG_FILES[@]}"; do
    if [[ -f "${CONFIG_FILE}" ]]; then
        sed -i -E "s/server [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:/server ${WSL2_IP}:/g" "${CONFIG_FILE}"
        echo "Updated: ${CONFIG_FILE}"
        UPDATED_COUNT=$((UPDATED_COUNT + 1))
    fi
done

if [[ ${UPDATED_COUNT} -eq 0 ]]; then
    echo "Warning: No configuration files found to update" >&2
fi

# デプロイスクリプトが存在する場合は実行
if [[ -x "${DEPLOY_SCRIPT}" ]]; then
    "${DEPLOY_SCRIPT}" "$@"
else
    echo "Warning: ${DEPLOY_SCRIPT} not found or not executable, skipping deploy" >&2
fi
