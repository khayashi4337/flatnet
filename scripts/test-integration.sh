#!/bin/bash
# Flatnet Phase 2 Integration Test Script
# Phase 2, Stage 4: Integration
#
# This script tests the complete integration of:
# - Flatnet CNI plugin
# - IP allocation and network setup
# - Host-container communication
# - Container-container communication
#
# Usage:
#   sudo ./scripts/test-integration.sh           # Run all tests
#   sudo ./scripts/test-integration.sh --quick   # Quick connectivity test only
#   sudo ./scripts/test-integration.sh --clean   # Clean up test containers only
#
# Prerequisites:
#   - Run as root (sudo)
#   - Flatnet network created (podman network create flatnet)
#   - nginx:alpine image available

set -e

#==============================================================================
# Configuration
#==============================================================================

NETWORK="flatnet"
TEST_PREFIX="flatnet-integ"
CONTAINER_WEB1="${TEST_PREFIX}-web1"
CONTAINER_WEB2="${TEST_PREFIX}-web2"
CONTAINER_WEB3="${TEST_PREFIX}-web3"
IMAGE="nginx:alpine"
BRIDGE="flatnet-br0"
FLATNET_GATEWAY="10.87.1.1"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASSED=0
FAILED=0
SKIPPED=0

#==============================================================================
# Helper Functions
#==============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
    PASSED=$((PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    FAILED=$((FAILED + 1))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    SKIPPED=$((SKIPPED + 1))
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} This script must be run as root (use sudo)"
        exit 1
    fi
}

cleanup() {
    log_info "Cleaning up test containers..."
    podman rm -f "$CONTAINER_WEB1" "$CONTAINER_WEB2" "$CONTAINER_WEB3" 2>/dev/null || true
}

show_help() {
    cat << 'EOF'
Flatnet Phase 2 Integration Test Script
========================================

This script tests the complete Flatnet integration.

USAGE:
    sudo ./scripts/test-integration.sh [OPTIONS]

OPTIONS:
    --quick     Run quick connectivity test only
    --clean     Clean up test containers only
    --help      Show this help message
    (no option) Run full test suite

TESTS PERFORMED:
    1. Network existence check
    2. Multiple container startup
    3. IP allocation verification
    4. Host-container HTTP access
    5. Container-container communication
    6. Container lifecycle (stop/start/restart)
    7. IP reuse after container removal
    8. DNS resolution
    9. Concurrent container startup (race condition check)

PREREQUISITES:
    - Run as root (sudo)
    - Flatnet network must exist
    - nginx:alpine image available
    - WSL2 IP forwarding enabled
EOF
}

#==============================================================================
# Test Functions
#==============================================================================

test_prerequisites() {
    echo ""
    echo "=== Testing Prerequisites ==="

    # Check network exists
    if podman network exists "$NETWORK" 2>/dev/null; then
        log_ok "Network '$NETWORK' exists"
    else
        log_fail "Network '$NETWORK' does not exist"
        echo "  Create it with: sudo podman network create flatnet"
        return 1
    fi

    # Check bridge exists
    if ip link show "$BRIDGE" &>/dev/null; then
        local bridge_ip=$(ip addr show "$BRIDGE" 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1)
        log_ok "Bridge '$BRIDGE' exists (IP: ${bridge_ip:-none})"
    else
        log_warn "Bridge '$BRIDGE' does not exist yet (will be created on first container)"
    fi

    # Check IP forwarding
    local forward=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
    if [[ "$forward" == "1" ]]; then
        log_ok "IP forwarding enabled"
    else
        log_warn "IP forwarding disabled (run scripts/wsl2/setup-forwarding.sh)"
    fi

    # Check image exists
    if podman image exists "$IMAGE" 2>/dev/null; then
        log_ok "Image '$IMAGE' available"
    else
        log_info "Pulling image '$IMAGE'..."
        podman pull "$IMAGE"
        log_ok "Image '$IMAGE' pulled"
    fi
}

test_container_startup() {
    echo ""
    echo "=== Testing Container Startup ==="

    # Start first container
    log_info "Starting $CONTAINER_WEB1..."
    if podman run -d --name "$CONTAINER_WEB1" --network "$NETWORK" "$IMAGE" >/dev/null 2>&1; then
        log_ok "Container $CONTAINER_WEB1 started"
    else
        log_fail "Failed to start $CONTAINER_WEB1"
        return 1
    fi

    # Start second container
    log_info "Starting $CONTAINER_WEB2..."
    if podman run -d --name "$CONTAINER_WEB2" --network "$NETWORK" "$IMAGE" >/dev/null 2>&1; then
        log_ok "Container $CONTAINER_WEB2 started"
    else
        log_fail "Failed to start $CONTAINER_WEB2"
        return 1
    fi

    # Start third container
    log_info "Starting $CONTAINER_WEB3..."
    if podman run -d --name "$CONTAINER_WEB3" --network "$NETWORK" "$IMAGE" >/dev/null 2>&1; then
        log_ok "Container $CONTAINER_WEB3 started"
    else
        log_fail "Failed to start $CONTAINER_WEB3"
        return 1
    fi

    # Wait for containers to be ready
    sleep 2
}

test_ip_allocation() {
    echo ""
    echo "=== Testing IP Allocation ==="

    # Get IPs
    IP1=$(podman inspect "$CONTAINER_WEB1" 2>/dev/null | jq -r ".[0].NetworkSettings.Networks.${NETWORK}.IPAddress")
    IP2=$(podman inspect "$CONTAINER_WEB2" 2>/dev/null | jq -r ".[0].NetworkSettings.Networks.${NETWORK}.IPAddress")
    IP3=$(podman inspect "$CONTAINER_WEB3" 2>/dev/null | jq -r ".[0].NetworkSettings.Networks.${NETWORK}.IPAddress")

    echo "  $CONTAINER_WEB1: $IP1"
    echo "  $CONTAINER_WEB2: $IP2"
    echo "  $CONTAINER_WEB3: $IP3"

    # Check IPs are in correct subnet
    if [[ "$IP1" == 10.87.1.* ]]; then
        log_ok "$CONTAINER_WEB1 has valid Flatnet IP"
    else
        log_fail "$CONTAINER_WEB1 IP not in Flatnet subnet: $IP1"
    fi

    if [[ "$IP2" == 10.87.1.* ]]; then
        log_ok "$CONTAINER_WEB2 has valid Flatnet IP"
    else
        log_fail "$CONTAINER_WEB2 IP not in Flatnet subnet: $IP2"
    fi

    if [[ "$IP3" == 10.87.1.* ]]; then
        log_ok "$CONTAINER_WEB3 has valid Flatnet IP"
    else
        log_fail "$CONTAINER_WEB3 IP not in Flatnet subnet: $IP3"
    fi

    # Check IPs are unique
    if [[ "$IP1" != "$IP2" && "$IP2" != "$IP3" && "$IP1" != "$IP3" ]]; then
        log_ok "All IPs are unique"
    else
        log_fail "Duplicate IPs detected"
    fi
}

test_host_to_container() {
    echo ""
    echo "=== Testing Host -> Container Connectivity ==="

    # Ping containers from host
    if ping -c 1 -W 2 "$IP1" >/dev/null 2>&1; then
        log_ok "Ping to $CONTAINER_WEB1 ($IP1) successful"
    else
        log_fail "Ping to $CONTAINER_WEB1 ($IP1) failed"
    fi

    # HTTP access
    if curl -s --connect-timeout 5 "http://$IP1/" >/dev/null 2>&1; then
        log_ok "HTTP to $CONTAINER_WEB1 ($IP1) successful"
    else
        log_fail "HTTP to $CONTAINER_WEB1 ($IP1) failed"
    fi

    if curl -s --connect-timeout 5 "http://$IP2/" >/dev/null 2>&1; then
        log_ok "HTTP to $CONTAINER_WEB2 ($IP2) successful"
    else
        log_fail "HTTP to $CONTAINER_WEB2 ($IP2) failed"
    fi

    if curl -s --connect-timeout 5 "http://$IP3/" >/dev/null 2>&1; then
        log_ok "HTTP to $CONTAINER_WEB3 ($IP3) successful"
    else
        log_fail "HTTP to $CONTAINER_WEB3 ($IP3) failed"
    fi
}

test_container_to_container() {
    echo ""
    echo "=== Testing Container -> Container Connectivity ==="

    # Container 1 -> Container 2
    if podman exec "$CONTAINER_WEB1" wget -q -O /dev/null --timeout=5 "http://$IP2/" 2>/dev/null; then
        log_ok "$CONTAINER_WEB1 -> $CONTAINER_WEB2 HTTP successful"
    else
        log_fail "$CONTAINER_WEB1 -> $CONTAINER_WEB2 HTTP failed"
    fi

    # Container 2 -> Container 3
    if podman exec "$CONTAINER_WEB2" wget -q -O /dev/null --timeout=5 "http://$IP3/" 2>/dev/null; then
        log_ok "$CONTAINER_WEB2 -> $CONTAINER_WEB3 HTTP successful"
    else
        log_fail "$CONTAINER_WEB2 -> $CONTAINER_WEB3 HTTP failed"
    fi

    # Container 3 -> Container 1
    if podman exec "$CONTAINER_WEB3" wget -q -O /dev/null --timeout=5 "http://$IP1/" 2>/dev/null; then
        log_ok "$CONTAINER_WEB3 -> $CONTAINER_WEB1 HTTP successful"
    else
        log_fail "$CONTAINER_WEB3 -> $CONTAINER_WEB1 HTTP failed"
    fi
}

test_container_to_gateway() {
    echo ""
    echo "=== Testing Container -> Gateway Connectivity ==="

    # Container -> Gateway (bridge)
    if podman exec "$CONTAINER_WEB1" ping -c 1 -W 2 "$FLATNET_GATEWAY" >/dev/null 2>&1; then
        log_ok "$CONTAINER_WEB1 -> Gateway ($FLATNET_GATEWAY) ping successful"
    else
        log_warn "$CONTAINER_WEB1 -> Gateway ($FLATNET_GATEWAY) ping failed (may be expected)"
    fi
}

test_lifecycle() {
    echo ""
    echo "=== Testing Container Lifecycle ==="

    # Stop container
    log_info "Stopping $CONTAINER_WEB1..."
    if podman stop "$CONTAINER_WEB1" >/dev/null 2>&1; then
        log_ok "Container stopped"
    else
        log_fail "Failed to stop container"
        return 1
    fi

    # Start container
    log_info "Starting $CONTAINER_WEB1..."
    if podman start "$CONTAINER_WEB1" >/dev/null 2>&1; then
        log_ok "Container started"
    else
        log_fail "Failed to start container"
        return 1
    fi

    sleep 2

    # Check IP after restart
    IP1_NEW=$(podman inspect "$CONTAINER_WEB1" 2>/dev/null | jq -r ".[0].NetworkSettings.Networks.${NETWORK}.IPAddress")
    if [[ "$IP1_NEW" == 10.87.1.* ]]; then
        log_ok "IP after restart: $IP1_NEW"
        if [[ "$IP1" == "$IP1_NEW" ]]; then
            log_info "  (IP preserved)"
        else
            log_info "  (IP changed from $IP1)"
        fi
    else
        log_fail "Invalid IP after restart: $IP1_NEW"
    fi

    # Verify connectivity after restart
    if curl -s --connect-timeout 5 "http://$IP1_NEW/" >/dev/null 2>&1; then
        log_ok "HTTP works after restart"
    else
        log_fail "HTTP failed after restart"
    fi

    # Restart container
    log_info "Restarting $CONTAINER_WEB2..."
    if podman restart "$CONTAINER_WEB2" >/dev/null 2>&1; then
        log_ok "Container restarted"
        sleep 2
        if curl -s --connect-timeout 5 "http://$IP2/" >/dev/null 2>&1; then
            log_ok "HTTP works after restart"
        else
            log_fail "HTTP failed after restart"
        fi
    else
        log_fail "Failed to restart container"
    fi
}

test_ip_reuse() {
    echo ""
    echo "=== Testing IP Reuse ==="

    # Remove container 3
    log_info "Removing $CONTAINER_WEB3..."
    podman rm -f "$CONTAINER_WEB3" >/dev/null 2>&1

    # Create new container - should get recycled IP
    log_info "Creating new container..."
    if podman run -d --name "$CONTAINER_WEB3" --network "$NETWORK" "$IMAGE" >/dev/null 2>&1; then
        IP3_NEW=$(podman inspect "$CONTAINER_WEB3" 2>/dev/null | jq -r ".[0].NetworkSettings.Networks.${NETWORK}.IPAddress")
        log_ok "New container created with IP: $IP3_NEW"
        if [[ "$IP3_NEW" == 10.87.1.* ]]; then
            log_ok "IP in correct subnet"
        else
            log_fail "IP not in Flatnet subnet"
        fi
    else
        log_fail "Failed to create new container"
    fi
}

test_dns_resolution() {
    echo ""
    echo "=== Testing DNS Resolution ==="

    # Test container can resolve external DNS
    if podman exec "$CONTAINER_WEB1" nslookup google.com >/dev/null 2>&1; then
        log_ok "External DNS resolution works"
    else
        # Try with wget instead (nslookup may not be available)
        if podman exec "$CONTAINER_WEB1" wget -q -O /dev/null --timeout=5 "http://www.google.com/" 2>/dev/null; then
            log_ok "External network access works (DNS implied)"
        else
            log_warn "External DNS/network access failed (may be expected in isolated environments)"
        fi
    fi

    # Test container name resolution (if supported by CNI)
    if podman exec "$CONTAINER_WEB1" ping -c 1 -W 2 "$CONTAINER_WEB2" >/dev/null 2>&1; then
        log_ok "Container name resolution works"
    else
        log_info "Container name resolution not available (expected with bridge network)"
    fi
}

test_concurrent_startup() {
    echo ""
    echo "=== Testing Concurrent Container Startup ==="

    local CONCURRENT_PREFIX="${TEST_PREFIX}-concurrent"
    local NUM_CONTAINERS=3

    log_info "Starting $NUM_CONTAINERS containers concurrently..."

    # Start containers in parallel using background processes
    local pids=()
    for i in $(seq 1 $NUM_CONTAINERS); do
        podman run -d --name "${CONCURRENT_PREFIX}-${i}" --network "$NETWORK" "$IMAGE" >/dev/null 2>&1 &
        pids+=($!)
    done

    # Wait for all to complete
    local all_success=true
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            all_success=false
        fi
    done

    if $all_success; then
        log_ok "All containers started successfully"
    else
        log_warn "Some containers failed to start"
    fi

    # Verify unique IPs
    local ips=()
    for i in $(seq 1 $NUM_CONTAINERS); do
        local ip=$(podman inspect "${CONCURRENT_PREFIX}-${i}" 2>/dev/null | jq -r ".[0].NetworkSettings.Networks.${NETWORK}.IPAddress")
        if [[ "$ip" == 10.87.1.* ]]; then
            ips+=("$ip")
        fi
    done

    # Check for duplicates
    local unique_count=$(printf '%s\n' "${ips[@]}" | sort -u | wc -l)
    if [[ $unique_count -eq ${#ips[@]} && $unique_count -eq $NUM_CONTAINERS ]]; then
        log_ok "All $NUM_CONTAINERS IPs are unique: ${ips[*]}"
    else
        log_fail "Duplicate IPs detected in concurrent startup"
    fi

    # Cleanup
    for i in $(seq 1 $NUM_CONTAINERS); do
        podman rm -f "${CONCURRENT_PREFIX}-${i}" >/dev/null 2>&1 || true
    done
}

quick_test() {
    echo ""
    echo "=== Quick Connectivity Test ==="

    # Check bridge
    if ip link show "$BRIDGE" &>/dev/null; then
        local bridge_ip=$(ip addr show "$BRIDGE" | grep -oP 'inet \K[\d.]+' | head -1)
        log_ok "Bridge exists: $bridge_ip"
    else
        log_fail "Bridge $BRIDGE not found"
        return 1
    fi

    # List running Flatnet containers
    local containers=$(podman ps --filter "network=$NETWORK" --format "{{.Names}}")
    if [[ -n "$containers" ]]; then
        log_ok "Flatnet containers running:"
        echo "$containers" | while read name; do
            local ip=$(podman inspect "$name" 2>/dev/null | jq -r ".[0].NetworkSettings.Networks.${NETWORK}.IPAddress")
            echo "  - $name: $ip"
        done
    else
        log_warn "No Flatnet containers running"
    fi

    # Test IPAM state
    if [[ -f /var/lib/flatnet/ipam/allocations.json ]]; then
        local count=$(jq '.allocations | length' /var/lib/flatnet/ipam/allocations.json 2>/dev/null || echo 0)
        log_ok "IPAM allocations: $count"
    else
        log_warn "IPAM allocation file not found"
    fi
}

print_summary() {
    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo -e "${GREEN}Passed: $PASSED${NC}"
    echo -e "${RED}Failed: $FAILED${NC}"
    if [[ $SKIPPED -gt 0 ]]; then
        echo -e "${YELLOW}Skipped: $SKIPPED${NC}"
    fi
    echo ""

    if [[ $FAILED -gt 0 ]]; then
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    fi
}

#==============================================================================
# Main
#==============================================================================

echo "========================================"
echo "Flatnet Phase 2 Integration Test"
echo "========================================"

case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --clean)
        check_root
        cleanup
        echo "Cleanup complete."
        exit 0
        ;;
    --quick)
        check_root
        quick_test
        exit 0
        ;;
    "")
        check_root

        # Set trap for cleanup on exit
        trap cleanup EXIT

        # Run tests
        test_prerequisites || exit 1
        test_container_startup || exit 1
        test_ip_allocation
        test_host_to_container
        test_container_to_container
        test_container_to_gateway
        test_lifecycle
        test_ip_reuse
        test_dns_resolution
        test_concurrent_startup

        print_summary
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac
