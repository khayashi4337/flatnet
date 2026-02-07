#!/bin/bash
# WSL2 の IP アドレスを取得するスクリプト
#
# 使用方法:
#   ./scripts/get-wsl2-ip.sh
#
# 出力:
#   WSL2 の eth0 インターフェースの IPv4 アドレス（例: 172.25.160.1）

set -euo pipefail

# eth0 の IPv4 アドレスを取得
ip addr show eth0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1
