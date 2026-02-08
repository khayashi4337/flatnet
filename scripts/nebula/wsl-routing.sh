#!/bin/bash
# Flatnet WSL2 Routing Setup Script
# Phase 3 - Stage 2
#
# Usage:
#   ./wsl-routing.sh                    # 状態表示
#   ./wsl-routing.sh add                # ルート追加
#   ./wsl-routing.sh remove             # ルート削除
#   ./wsl-routing.sh test               # 接続テスト
#
# This script configures:
#   Routes to reach other Nebula hosts through Windows Nebula interface
#
# Prerequisites:
#   - Windows 側で Nebula が起動していること
#   - Windows 側で IP Forwarding が有効化されていること

set -e

# 設定
NEBULA_NETWORK="10.100.0.0/16"
LIGHTHOUSE_IP="10.100.0.1"

# 色設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Windows (WSL vEthernet) の IP を取得
get_windows_ip() {
    ip route | grep default | awk '{print $3}' | head -1
}

# 現在の状態を表示
show_status() {
    echo -e "${CYAN}Flatnet WSL2 Routing Status${NC}"
    echo -e "${CYAN}============================${NC}"
    echo ""

    # Windows Gateway IP
    local windows_ip=$(get_windows_ip)
    echo -e "${YELLOW}Windows Gateway IP:${NC}"
    if [ -n "$windows_ip" ]; then
        echo "  $windows_ip"
    else
        echo -e "  ${RED}取得できません${NC}"
    fi
    echo ""

    # 現在のルート
    echo -e "${YELLOW}Nebula ネットワーク関連ルート:${NC}"
    local routes=$(ip route | grep "^10\.100\." 2>/dev/null || true)
    if [ -n "$routes" ]; then
        echo "$routes" | while read line; do
            echo "  $line"
        done
    else
        echo -e "  ${YELLOW}ルートなし${NC}"
    fi
    echo ""

    # デフォルトルート
    echo -e "${YELLOW}デフォルトルート:${NC}"
    ip route | grep default | head -1 | while read line; do
        echo "  $line"
    done
    echo ""
}

# ルートを追加
add_routes() {
    local windows_ip=$(get_windows_ip)

    if [ -z "$windows_ip" ]; then
        echo -e "${RED}Error: Windows Gateway IP を取得できません${NC}"
        exit 1
    fi

    echo -e "${CYAN}Nebula ネットワークへのルートを追加しています...${NC}"
    echo "  Gateway: $windows_ip"
    echo "  Network: $NEBULA_NETWORK"
    echo ""

    # 既存ルートを確認
    if ip route | grep -q "^10\.100\.0\.0/16"; then
        echo -e "${YELLOW}既存のルートを削除しています...${NC}"
        sudo ip route del $NEBULA_NETWORK 2>/dev/null || true
    fi

    # ルート追加
    echo -e "${YELLOW}ルートを追加しています...${NC}"
    if sudo ip route add $NEBULA_NETWORK via $windows_ip; then
        echo -e "  ${GREEN}完了${NC}"
    else
        echo -e "  ${RED}ルートの追加に失敗しました${NC}"
        echo "  sudo 権限があるか確認してください"
        exit 1
    fi
    echo ""

    # 確認
    echo -e "${YELLOW}追加されたルート:${NC}"
    ip route | grep "^10\.100\."
}

# ルートを削除
remove_routes() {
    echo -e "${CYAN}Nebula ネットワークへのルートを削除しています...${NC}"

    if ip route | grep -q "^10\.100\.0\.0/16"; then
        sudo ip route del $NEBULA_NETWORK 2>/dev/null || true
        echo -e "  ${GREEN}削除完了${NC}"
    else
        echo -e "  ${YELLOW}削除するルートがありません${NC}"
    fi
}

# 接続テスト
# Usage: test_connection [additional_host_ips...]
test_connection() {
    local windows_ip=$(get_windows_ip)
    local extra_hosts=("$@")

    echo -e "${CYAN}Flatnet 接続テスト${NC}"
    echo -e "${CYAN}==================${NC}"
    echo ""

    # Windows への疎通確認
    echo -e "${YELLOW}1. Windows Gateway への疎通確認:${NC}"
    if ping -c 2 -W 2 "$windows_ip" > /dev/null 2>&1; then
        echo -e "   ping $windows_ip: ${GREEN}成功${NC}"
    else
        echo -e "   ping $windows_ip: ${RED}失敗${NC}"
        echo -e "   ${RED}Windows への疎通ができません${NC}"
        return 1
    fi
    echo ""

    # Lighthouse への疎通確認
    echo -e "${YELLOW}2. Lighthouse への疎通確認 (Nebula 経由):${NC}"
    if ip route | grep -q "^10\.100\.0\.0/16"; then
        if ping -c 2 -W 3 "$LIGHTHOUSE_IP" > /dev/null 2>&1; then
            echo -e "   ping $LIGHTHOUSE_IP: ${GREEN}成功${NC}"
        else
            echo -e "   ping $LIGHTHOUSE_IP: ${RED}失敗${NC}"
            echo ""
            echo -e "${YELLOW}トラブルシューティング:${NC}"
            echo "  1. Windows 側で Nebula サービスが起動しているか確認"
            echo "     > Get-Service Nebula"
            echo "  2. Windows 側で IP Forwarding が有効か確認"
            echo "     > .\\setup-routing.ps1 -ShowStatus"
            echo "  3. Windows Firewall で ICMP が許可されているか確認"
        fi
    else
        echo -e "   ${YELLOW}ルートが設定されていません${NC}"
        echo "   先に './wsl-routing.sh add' を実行してください"
    fi
    echo ""

    # その他のホストへの疎通確認（引数があれば）
    if [ ${#extra_hosts[@]} -gt 0 ]; then
        echo -e "${YELLOW}3. 追加ホストへの疎通確認:${NC}"
        for host_ip in "${extra_hosts[@]}"; do
            if ping -c 2 -W 3 "$host_ip" > /dev/null 2>&1; then
                echo -e "   ping $host_ip: ${GREEN}成功${NC}"
            else
                echo -e "   ping $host_ip: ${RED}失敗${NC}"
            fi
        done
        echo ""
    fi
}

# ヘルプ表示
show_help() {
    echo "Flatnet WSL2 Routing Setup Script"
    echo ""
    echo "Usage:"
    echo "  $0           - 現在の状態を表示"
    echo "  $0 add       - Nebula ネットワークへのルートを追加"
    echo "  $0 remove    - ルートを削除"
    echo "  $0 test      - 接続テスト"
    echo "  $0 test <IP> - 特定ホストへの接続テスト"
    echo ""
    echo "Examples:"
    echo "  $0 add                    # ルートを追加"
    echo "  $0 test                   # Lighthouse への接続テスト"
    echo "  $0 test 10.100.2.1        # Host B への接続テスト"
    echo ""
    echo "Note:"
    echo "  このスクリプトを実行する前に、Windows 側で以下を確認してください:"
    echo "  1. Nebula サービスが起動している"
    echo "  2. IP Forwarding が有効化されている"
    echo "     > .\\setup-routing.ps1 -EnableForwarding"
}

# メイン
case "${1:-status}" in
    add)
        add_routes
        ;;
    remove)
        remove_routes
        ;;
    test)
        shift 2>/dev/null || true
        test_connection "$@"
        ;;
    status)
        show_status
        ;;
    -h|--help|help)
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo ""
        show_help
        exit 1
        ;;
esac
