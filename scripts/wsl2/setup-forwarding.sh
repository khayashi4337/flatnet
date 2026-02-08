#!/bin/bash
# Flatnet IP Forwarding Setup Script for WSL2
# Phase 2, Stage 4: Integration
#
# This script enables IP forwarding and configures iptables rules
# to allow traffic to reach Flatnet containers from Windows.
#
# Usage:
#   sudo ./setup-forwarding.sh           # Enable forwarding
#   sudo ./setup-forwarding.sh --status  # Check current status
#   sudo ./setup-forwarding.sh --persist # Enable and persist settings
#
# Prerequisites:
#   - Run as root (sudo)
#   - flatnet-br0 bridge should exist

set -e

#==============================================================================
# Configuration
#==============================================================================

FLATNET_BRIDGE="flatnet-br0"
FLATNET_SUBNET="10.87.1.0/24"
SYSCTL_CONF="/etc/sysctl.d/99-flatnet.conf"

#==============================================================================
# Helper Functions
#==============================================================================

log_info() {
    echo "[INFO] $1"
}

log_ok() {
    echo "[OK] $1"
}

log_warn() {
    echo "[WARN] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_bridge() {
    if ip link show "$FLATNET_BRIDGE" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

show_status() {
    echo "=== Flatnet Forwarding Status ==="
    echo ""

    # IP Forwarding
    local forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
    if [[ "$forward" == "1" ]]; then
        log_ok "IP forwarding: enabled"
    else
        log_warn "IP forwarding: disabled"
    fi

    # Bridge
    if check_bridge; then
        local bridge_ip=$(ip addr show "$FLATNET_BRIDGE" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
        log_ok "Bridge $FLATNET_BRIDGE: exists (IP: ${bridge_ip:-none})"
    else
        log_warn "Bridge $FLATNET_BRIDGE: not found"
    fi

    # iptables FORWARD chain
    echo ""
    echo "iptables FORWARD rules for $FLATNET_BRIDGE:"
    iptables -L FORWARD -n -v 2>/dev/null | grep -E "(flatnet|$FLATNET_BRIDGE|RELATED,ESTABLISHED)" || echo "  (no specific rules found)"

    # Persistent settings
    echo ""
    echo "Persistent settings:"
    if [[ -f "$SYSCTL_CONF" ]]; then
        log_ok "sysctl config: $SYSCTL_CONF exists"
        cat "$SYSCTL_CONF" | sed 's/^/  /'
    else
        log_warn "sysctl config: $SYSCTL_CONF not found"
    fi
}

show_help() {
    cat << 'EOF'
Flatnet IP Forwarding Setup Script
===================================

This script configures WSL2 to forward traffic from Windows to Flatnet containers.

USAGE:
    sudo ./setup-forwarding.sh [OPTIONS]

OPTIONS:
    --status    Show current forwarding status
    --persist   Enable forwarding and persist settings across reboots
    --help      Show this help message
    (no option) Enable forwarding for current session only

WHAT IT DOES:
    1. Enables net.ipv4.ip_forward
    2. Adds iptables FORWARD rules for flatnet-br0
    3. (with --persist) Saves settings to /etc/sysctl.d/

PREREQUISITES:
    - Run as root (sudo)
    - The flatnet-br0 bridge should exist (created by Flatnet CNI)

TROUBLESHOOTING:
    If Windows cannot reach containers after setup:
    1. Check bridge exists: ip addr show flatnet-br0
    2. Check forwarding: sysctl net.ipv4.ip_forward
    3. Check iptables: iptables -L FORWARD -n
    4. Check Windows route: route print | Select-String "10.87.1.0"
EOF
}

#==============================================================================
# Setup Functions
#==============================================================================

enable_forwarding() {
    log_info "Enabling IP forwarding..."
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    log_ok "IP forwarding enabled"
}

setup_iptables() {
    log_info "Configuring iptables FORWARD rules..."

    # Check if rules already exist
    if iptables -C FORWARD -i "$FLATNET_BRIDGE" -j ACCEPT 2>/dev/null; then
        log_info "FORWARD rule for incoming traffic already exists"
    else
        iptables -A FORWARD -i "$FLATNET_BRIDGE" -j ACCEPT
        log_ok "Added FORWARD rule for incoming traffic"
    fi

    if iptables -C FORWARD -o "$FLATNET_BRIDGE" -j ACCEPT 2>/dev/null; then
        log_info "FORWARD rule for outgoing traffic already exists"
    else
        iptables -A FORWARD -o "$FLATNET_BRIDGE" -j ACCEPT
        log_ok "Added FORWARD rule for outgoing traffic"
    fi

    # Also add rules for related/established connections (using conntrack, not deprecated state)
    if ! iptables -C FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
        # Insert at the beginning for efficiency (most packets match this rule)
        iptables -I FORWARD 1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
        log_ok "Added FORWARD rule for established connections"
    fi
}

persist_settings() {
    log_info "Persisting settings..."

    # Create sysctl config
    cat > "$SYSCTL_CONF" << 'EOF'
# Flatnet IP forwarding configuration
# Created by setup-forwarding.sh
net.ipv4.ip_forward=1
EOF
    log_ok "Created $SYSCTL_CONF"

    # Check if iptables-persistent is available
    if command -v netfilter-persistent &>/dev/null; then
        log_info "Saving iptables rules with netfilter-persistent..."
        netfilter-persistent save
        log_ok "iptables rules saved"
    else
        log_warn "iptables-persistent not installed"
        echo "  To persist iptables rules, install iptables-persistent:"
        echo "    sudo apt-get install -y iptables-persistent"
        echo "    sudo netfilter-persistent save"
    fi
}

#==============================================================================
# Main Logic
#==============================================================================

case "${1:-}" in
    --status)
        show_status
        exit 0
        ;;
    --help|-h)
        show_help
        exit 0
        ;;
    --persist)
        check_root
        if ! check_bridge; then
            log_warn "Bridge $FLATNET_BRIDGE does not exist yet"
            log_info "Run this script again after creating the Flatnet network"
        fi
        enable_forwarding
        setup_iptables
        persist_settings
        echo ""
        log_ok "Setup complete (persistent)"
        ;;
    "")
        check_root
        if ! check_bridge; then
            log_warn "Bridge $FLATNET_BRIDGE does not exist yet"
            log_info "iptables rules will be added, but may not be effective until bridge is created"
        fi
        enable_forwarding
        setup_iptables
        echo ""
        log_ok "Setup complete (session only)"
        echo ""
        echo "Note: These settings will be lost after WSL2 restart."
        echo "Use --persist to make them permanent."
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
