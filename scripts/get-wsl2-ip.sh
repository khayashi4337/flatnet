#!/bin/bash
# WSL2 の IP アドレスを取得するスクリプト
#
# 使用方法:
#   ./scripts/get-wsl2-ip.sh
#
# 出力:
#   WSL2 の eth0 インターフェースの IPv4 アドレス（例: 172.25.160.1）

set -euo pipefail

# eth0 の IPv4 アドレスを取得（複数ある場合は最初の 1 つ）
IP=$(ip addr show eth0 2>/dev/null | grep 'inet ' | head -n1 | awk '{print $2}' | cut -d/ -f1)

# IP が取得できなかった場合はエラー
if [[ -z "${IP}" ]]; then
    # eth0 インターフェースの存在確認
    if ! ip link show eth0 &>/dev/null; then
        echo "Error: eth0 interface not found" >&2
    else
        echo "Error: Could not get IPv4 address from eth0" >&2
    fi
    exit 1
fi

echo "${IP}"
