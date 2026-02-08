#!/bin/bash
# Flatnet Cross-Host Routing Configuration
# Phase 3, Stage 3: CNI Plugin Multihost Extension
#
# This script configures routing in WSL2 to enable cross-host container
# communication via the Windows Nebula gateway.
#
# Usage:
#   ./cross-host-routing.sh [options]
#
# Options:
#   --host-id ID        This host's ID (1-254)
#   --gateway IP        Windows Nebula gateway IP
#   --peers "ID1,ID2"   Comma-separated list of peer host IDs
#   --add               Add routes (default)
#   --del               Remove routes
#   --show              Show current routes
#   --help              Show this help
#
# Examples:
#   # Add routes for hosts 2 and 3 (this is host 1)
#   ./cross-host-routing.sh --host-id 1 --gateway 172.17.0.1 --peers "2,3"
#
#   # Remove routes
#   ./cross-host-routing.sh --del --peers "2,3" --gateway 172.17.0.1

set -e

#==============================================================================
# Configuration
#==============================================================================

# Flatnet multihost subnet base
SUBNET_BASE="10.100"

# Default gateway (Windows side, accessible from WSL2)
# This is typically the WSL2 gateway address
DEFAULT_GATEWAY=""

# This host's ID
HOST_ID=""

# Peer host IDs
PEERS=""

# Action: add, del, or show
ACTION="add"

#==============================================================================
# Functions
#==============================================================================

usage() {
    cat << EOF
Flatnet Cross-Host Routing Configuration
Phase 3, Stage 3: CNI Plugin Multihost Extension

Usage:
    $(basename "$0") [options]

Options:
    --host-id ID        This host's ID (1-254)
    --gateway IP        Windows Nebula gateway IP (or WSL2 gateway)
    --peers "ID1,ID2"   Comma-separated list of peer host IDs
    --add               Add routes (default)
    --del               Remove routes
    --show              Show current flatnet routes
    --help              Show this help

Multihost IP Scheme:
    Each host gets subnet 10.100.<host-id>.0/24
    Gateway for each host: 10.100.<host-id>.1
    Container IPs: 10.100.<host-id>.10-254

Examples:
    # Host 1: Add routes to hosts 2 and 3
    $(basename "$0") --host-id 1 --gateway 172.17.0.1 --peers "2,3"

    # Remove routes
    $(basename "$0") --del --gateway 172.17.0.1 --peers "2,3"

    # Show current flatnet routes
    $(basename "$0") --show

Notes:
    - Requires root/sudo privileges for route modification
    - Gateway should be accessible from WSL2 (typically Windows IP)
    - Ensure Nebula tunnel is established before adding routes
EOF
}

log_info() {
    echo "[INFO] $*"
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

# Detect WSL2 gateway (Windows IP as seen from WSL2)
detect_gateway() {
    # Method 1: Check /etc/resolv.conf (WSL2 default)
    if [ -f /etc/resolv.conf ]; then
        local gateway
        gateway=$(grep nameserver /etc/resolv.conf | head -1 | awk '{print $2}')
        if [ -n "$gateway" ]; then
            echo "$gateway"
            return 0
        fi
    fi

    # Method 2: Check default route
    local default_gw
    default_gw=$(ip route | grep default | head -1 | awk '{print $3}')
    if [ -n "$default_gw" ]; then
        echo "$default_gw"
        return 0
    fi

    return 1
}

# Add route to peer host's subnet
add_route() {
    local peer_id=$1
    local gateway=$2
    local subnet="${SUBNET_BASE}.${peer_id}.0/24"

    if [ "$peer_id" = "$HOST_ID" ]; then
        log_warn "Skipping route to own subnet (host ID $peer_id)"
        return 0
    fi

    # Check if route already exists
    if ip route show "$subnet" 2>/dev/null | grep -q "$subnet"; then
        log_info "Route to $subnet already exists"
        return 0
    fi

    log_info "Adding route: $subnet via $gateway"
    if sudo ip route add "$subnet" via "$gateway"; then
        log_info "Route added successfully"
    else
        log_error "Failed to add route to $subnet"
        return 1
    fi
}

# Remove route to peer host's subnet
del_route() {
    local peer_id=$1
    local gateway=$2
    local subnet="${SUBNET_BASE}.${peer_id}.0/24"

    # Check if route exists
    if ! ip route show "$subnet" 2>/dev/null | grep -q "$subnet"; then
        log_info "Route to $subnet does not exist, nothing to remove"
        return 0
    fi

    log_info "Removing route: $subnet"
    if sudo ip route del "$subnet"; then
        log_info "Route removed successfully"
    else
        log_error "Failed to remove route to $subnet"
        return 1
    fi
}

# Show current flatnet routes
show_routes() {
    log_info "Current Flatnet routes (${SUBNET_BASE}.*.0/24):"
    echo ""
    ip route | grep "${SUBNET_BASE}" || echo "  (no flatnet routes found)"
    echo ""

    log_info "Local Flatnet interfaces:"
    ip addr | grep -A2 "${SUBNET_BASE}" || echo "  (no flatnet interfaces found)"
}

#==============================================================================
# Main
#==============================================================================

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --host-id)
            HOST_ID="$2"
            shift 2
            ;;
        --gateway)
            DEFAULT_GATEWAY="$2"
            shift 2
            ;;
        --peers)
            PEERS="$2"
            shift 2
            ;;
        --add)
            ACTION="add"
            shift
            ;;
        --del)
            ACTION="del"
            shift
            ;;
        --show)
            ACTION="show"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Handle show action early
if [ "$ACTION" = "show" ]; then
    show_routes
    exit 0
fi

# Validate required parameters for add/del
if [ -z "$PEERS" ]; then
    log_error "Peer host IDs required (--peers)"
    usage
    exit 1
fi

# Auto-detect gateway if not specified
if [ -z "$DEFAULT_GATEWAY" ]; then
    log_info "Gateway not specified, attempting auto-detection..."
    if DEFAULT_GATEWAY=$(detect_gateway); then
        log_info "Detected gateway: $DEFAULT_GATEWAY"
    else
        log_error "Could not detect gateway, please specify with --gateway"
        exit 1
    fi
fi

# Validate gateway is reachable
if ! ping -c 1 -W 2 "$DEFAULT_GATEWAY" >/dev/null 2>&1; then
    log_warn "Gateway $DEFAULT_GATEWAY may not be reachable"
fi

# Process peer list
IFS=',' read -ra PEER_ARRAY <<< "$PEERS"

log_info "Action: $ACTION"
log_info "Gateway: $DEFAULT_GATEWAY"
log_info "Peers: ${PEER_ARRAY[*]}"
[ -n "$HOST_ID" ] && log_info "This host ID: $HOST_ID"
echo ""

# Execute action for each peer
for peer_id in "${PEER_ARRAY[@]}"; do
    # Trim whitespace
    peer_id=$(echo "$peer_id" | tr -d ' ')

    # Validate peer ID
    if ! [[ "$peer_id" =~ ^[0-9]+$ ]] || [ "$peer_id" -lt 1 ] || [ "$peer_id" -gt 254 ]; then
        log_warn "Invalid peer ID: $peer_id (must be 1-254), skipping"
        continue
    fi

    case "$ACTION" in
        add)
            add_route "$peer_id" "$DEFAULT_GATEWAY"
            ;;
        del)
            del_route "$peer_id" "$DEFAULT_GATEWAY"
            ;;
    esac
done

echo ""
log_info "Routing configuration complete"

# Show final state
show_routes
