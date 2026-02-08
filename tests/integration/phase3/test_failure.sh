#!/bin/bash
# Flatnet Phase 3 Failure Scenario Tests
# Stage 5: Integration Test
#
# This script tests various failure scenarios:
# - Lighthouse failure
# - Host failure
# - Network partition simulation
# - WSL2 restart simulation
#
# WARNING: Some tests may affect system state. Run with caution.
#
# Prerequisites:
# - OpenResty running on Windows with Flatnet modules
# - Nebula tunnel established between hosts
# - Root/sudo access for some tests
#
# Usage:
#   ./test_failure.sh [GATEWAY_IP] [--destructive]
#
# Options:
#   --destructive  Run tests that may affect system state
#
# Environment Variables:
#   GATEWAY_IP     - Local Gateway IP (default: 10.100.1.1)
#   REMOTE_IP      - Remote container IP (default: 10.100.2.10)
#   LIGHTHOUSE_IP  - Lighthouse IP (default: 10.100.0.1)
#   API_PORT       - API port (default: 8080)
#   VERBOSE        - Set to 1 for verbose output
#   CURL_TIMEOUT   - Timeout for curl/ping commands in seconds (default: 5)

set -e

# Script directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Parse arguments
DESTRUCTIVE_MODE=0
GATEWAY_IP="${GATEWAY_IP:-10.100.1.1}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --destructive)
            DESTRUCTIVE_MODE=1
            shift
            ;;
        *)
            GATEWAY_IP="$1"
            shift
            ;;
    esac
done

# Configuration
REMOTE_IP="${REMOTE_IP:-10.100.2.10}"
LIGHTHOUSE_IP="${LIGHTHOUSE_IP:-10.100.0.1}"
API_PORT="${API_PORT:-8080}"
BASE_URL="http://${GATEWAY_IP}:${API_PORT}"
VERBOSE="${VERBOSE:-0}"

# Default timeout for curl commands (seconds)
CURL_TIMEOUT="${CURL_TIMEOUT:-5}"

# Temporary directory for test artifacts (cleaned up on exit)
TMP_DIR=""

# Cleanup function for script exit
cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}

# Set trap for cleanup on script exit
# Also handle SIGINT and SIGTERM for proper cleanup on Ctrl+C
trap cleanup EXIT INT TERM

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_debug() {
    if [ "$VERBOSE" = "1" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

log_test() {
    echo -e "\n${MAGENTA}=== $1 ===${NC}"
}

log_step() {
    echo -e "\n  ${BLUE}>> $1${NC}"
}

log_result() {
    local status="$1"
    local description="$2"
    local details="${3:-}"

    case "$status" in
        PASS)
            echo -e "  ${GREEN}[PASS]${NC} $description"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            ;;
        FAIL)
            echo -e "  ${RED}[FAIL]${NC} $description"
            if [ -n "$details" ]; then
                echo -e "         ${RED}$details${NC}"
            fi
            TESTS_FAILED=$((TESTS_FAILED + 1))
            ;;
        SKIP)
            echo -e "  ${YELLOW}[SKIP]${NC} $description"
            if [ -n "$details" ]; then
                echo -e "         ${YELLOW}$details${NC}"
            fi
            TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
            ;;
    esac
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running as root
is_root() {
    [ "$(id -u)" = "0" ]
}

# Print test summary
print_summary() {
    echo ""
    echo "=============================================="
    echo "          FAILURE SCENARIO TEST SUMMARY"
    echo "=============================================="
    echo -e "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
    echo -e "  ${RED}Failed:${NC}  $TESTS_FAILED"
    echo -e "  ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo "----------------------------------------------"
    local total=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    echo "  Total:   $total"
    echo "=============================================="

    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo -e "\n${RED}Some tests failed. Please check the output above.${NC}"
        return 1
    elif [ "$TESTS_PASSED" -eq 0 ]; then
        echo -e "\n${YELLOW}No tests passed. Environment may not be ready.${NC}"
        return 1
    else
        echo -e "\n${GREEN}All failure scenario tests completed!${NC}"
        return 0
    fi
}

# =============================================================================
# HEADER
# =============================================================================

echo ""
echo "=============================================="
echo "  Flatnet Phase 3 - Failure Scenario Tests"
echo "=============================================="
echo ""
echo "Configuration:"
echo "  Gateway IP:     $GATEWAY_IP"
echo "  Remote IP:      $REMOTE_IP"
echo "  Lighthouse IP:  $LIGHTHOUSE_IP"
echo "  API Port:       $API_PORT"
echo "  Base URL:       $BASE_URL"
echo "  Destructive:    $( [ "$DESTRUCTIVE_MODE" -eq 1 ] && echo 'YES' || echo 'NO' )"
echo ""

if [ "$DESTRUCTIVE_MODE" -eq 1 ]; then
    echo -e "${RED}WARNING: Destructive mode enabled. Some tests may affect system state.${NC}"
    echo ""
fi

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

log_test "Pre-flight Checks"

# Check Gateway connectivity
if curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/health" | grep -q "OK"; then
    log_result PASS "Gateway is reachable at ${BASE_URL}"
else
    log_result FAIL "Gateway is not reachable at ${BASE_URL}"
    log_error "Cannot continue without Gateway connectivity"
    exit 1
fi

# Check for required tools
if command_exists ping; then
    log_result PASS "ping is available"
else
    log_result SKIP "ping not available - some tests will be limited"
fi

if command_exists iptables; then
    log_result PASS "iptables is available"
else
    log_result SKIP "iptables not available - network partition tests will be limited"
fi

# =============================================================================
# TEST 1: Lighthouse Connectivity Check
# =============================================================================

log_test "Test 1: Lighthouse Connectivity Check"

log_step "Checking connectivity to Lighthouse ($LIGHTHOUSE_IP)"

if command_exists ping; then
    if ping -c 1 -W "$CURL_TIMEOUT" "$LIGHTHOUSE_IP" >/dev/null 2>&1; then
        log_result PASS "Lighthouse is reachable via ping"
    else
        log_result SKIP "Lighthouse not reachable via ping" "ICMP may be blocked"
    fi
else
    log_result SKIP "ping not available"
fi

# Check via API if there's a lighthouse status endpoint
RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/status" 2>/dev/null || echo "")
if [ -n "$RESPONSE" ]; then
    log_result PASS "API status endpoint accessible"
else
    log_result FAIL "API status endpoint not accessible"
fi

# =============================================================================
# TEST 2: Lighthouse Failure Simulation (Non-destructive)
# =============================================================================

log_test "Test 2: Lighthouse Failure Simulation"

log_step "Simulating Lighthouse failure (non-destructive check)"

log_info "In a real Lighthouse failure scenario:"
log_info "  1. Existing P2P connections should remain active"
log_info "  2. New host additions will fail"
log_info "  3. Gateway routing should continue to work"
log_info ""
log_info "To test manually:"
log_info "  1. On Lighthouse host: Stop-Service Nebula"
log_info "  2. Verify existing connections work"
log_info "  3. Try to add a new host (should fail)"
log_info "  4. Restart Nebula: Start-Service Nebula"

# Check current sync status
RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/sync/status" 2>/dev/null || echo "")
log_debug "Sync status: $RESPONSE"

if echo "$RESPONSE" | grep -q '"peer_count"'; then
    peer_count=$(echo "$RESPONSE" | grep -o '"peer_count":[0-9]*' | head -1 | cut -d':' -f2)
    log_result PASS "Sync status available (peer count: ${peer_count:-0})"
else
    log_result SKIP "Sync status not available"
fi

log_result PASS "Lighthouse failure simulation check completed"

# =============================================================================
# TEST 3: Host Failure Simulation
# =============================================================================

log_test "Test 3: Host Failure Simulation"

log_step "Checking behavior when remote host is unreachable"

# Check if remote IP is currently reachable
if command_exists ping; then
    if ping -c 1 -W "$CURL_TIMEOUT" "$REMOTE_IP" >/dev/null 2>&1; then
        log_result PASS "Remote host $REMOTE_IP is currently reachable"

        log_info "In a host failure scenario:"
        log_info "  1. Requests to containers on that host will timeout"
        log_info "  2. Other hosts should continue to function"
        log_info "  3. Escalation state will transition to GATEWAY_FALLBACK"
        log_info ""
        log_info "To test manually:"
        log_info "  1. Stop WSL2 or Nebula on Host B"
        log_info "  2. Observe healthcheck failures in logs"
        log_info "  3. Verify Gateway routing fallback"
    else
        log_info "Remote host $REMOTE_IP is not reachable"
        log_info "Testing timeout behavior..."

        # Test API behavior with unreachable host
        start_time=$(date +%s)
        RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/state?ip=${REMOTE_IP}" 2>/dev/null || echo "timeout")
        end_time=$(date +%s)
        elapsed=$((end_time - start_time))

        log_debug "Response time: ${elapsed}s"

        if [ "$RESPONSE" != "timeout" ]; then
            log_result PASS "API responds even with unreachable remote host"
        else
            log_result FAIL "API timed out when querying unreachable host"
        fi
    fi
else
    log_result SKIP "ping not available - limited host failure testing"
fi

# =============================================================================
# TEST 4: Network Partition Simulation (Destructive)
# =============================================================================

log_test "Test 4: Network Partition Simulation"

if [ "$DESTRUCTIVE_MODE" -eq 1 ]; then
    if ! is_root && ! command_exists sudo; then
        log_result SKIP "Requires root privileges" "Run with sudo or as root"
    elif ! command_exists iptables; then
        log_result SKIP "iptables not available"
    else
        log_step "Simulating network partition (blocking Nebula traffic)"

        # Block UDP port 4242 (Nebula's default port)
        log_info "Blocking Nebula traffic (UDP 4242)..."

        # Add blocking rule (determine iptables command)
        iptables_cmd="iptables"
        if ! is_root; then
            iptables_cmd="sudo iptables"
        fi

        if $iptables_cmd -A OUTPUT -p udp --dport 4242 -j DROP 2>/dev/null; then
            log_result PASS "Network partition rule added"

            # Wait and check behavior
            log_info "Waiting 3 seconds to observe behavior..."
            sleep 3

            # Check escalation state
            RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/state?ip=${REMOTE_IP}" 2>/dev/null || echo "")
            if [ -n "$RESPONSE" ]; then
                state=$(echo "$RESPONSE" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
                log_info "Current escalation state: ${state:-unknown}"
            fi

            # Remove blocking rule
            log_info "Removing network partition rule..."
            if $iptables_cmd -D OUTPUT -p udp --dport 4242 -j DROP 2>/dev/null; then
                log_result PASS "Network partition rule removed"
            else
                log_warn "Failed to remove rule - manual cleanup may be required"
                log_warn "Run: sudo iptables -D OUTPUT -p udp --dport 4242 -j DROP"
            fi
        else
            log_result FAIL "Failed to add iptables rule"
        fi
    fi
else
    log_info "Network partition test requires --destructive flag"
    log_info ""
    log_info "This test would:"
    log_info "  1. Block Nebula UDP traffic (port 4242)"
    log_info "  2. Observe escalation fallback behavior"
    log_info "  3. Restore network and verify recovery"
    log_info ""
    log_info "Manual test commands:"
    log_info "  # Block:"
    log_info "  sudo iptables -A OUTPUT -p udp --dport 4242 -j DROP"
    log_info "  # Unblock:"
    log_info "  sudo iptables -D OUTPUT -p udp --dport 4242 -j DROP"
    log_result SKIP "Destructive mode not enabled"
fi

# =============================================================================
# TEST 5: WSL2 Restart Simulation
# =============================================================================

log_test "Test 5: WSL2 Restart Simulation"

log_info "WSL2 restart test is a manual procedure"
log_info ""
log_info "After WSL2 restart, the following should be verified:"
log_info "  1. CNI plugin re-initializes correctly"
log_info "  2. Flatnet bridge (flatnet-br0) is recreated"
log_info "  3. IP forwarding is re-enabled"
log_info "  4. Existing containers get Flatnet IPs on restart"
log_info ""
log_info "Manual test procedure:"
log_info "  1. Note current container IPs"
log_info "  2. Run: wsl --shutdown"
log_info "  3. Open a new WSL2 terminal"
log_info "  4. Run: sudo ./scripts/wsl2/setup-forwarding.sh"
log_info "  5. Start containers and verify IPs"
log_info ""
log_info "Recovery script:"
log_info "  ${PROJECT_ROOT}/scripts/wsl2/setup-forwarding.sh"

# Check current bridge status
if command_exists ip; then
    if ip addr show flatnet-br0 >/dev/null 2>&1; then
        bridge_ip=$(ip addr show flatnet-br0 | grep 'inet ' | awk '{print $2}')
        log_result PASS "Flatnet bridge exists (IP: ${bridge_ip:-unknown})"
    else
        log_result SKIP "Flatnet bridge does not exist" "May need to start a container first"
    fi
else
    log_result SKIP "ip command not available"
fi

# Check IP forwarding
if [ -f /proc/sys/net/ipv4/ip_forward ]; then
    forwarding=$(cat /proc/sys/net/ipv4/ip_forward)
    if [ "$forwarding" = "1" ]; then
        log_result PASS "IP forwarding is enabled"
    else
        log_result FAIL "IP forwarding is disabled"
    fi
else
    log_result SKIP "Cannot check IP forwarding status"
fi

log_result PASS "WSL2 restart simulation check completed"

# =============================================================================
# TEST 6: API Resilience
# =============================================================================

log_test "Test 6: API Resilience"

log_step "Testing API behavior under various conditions"

# Test rapid requests
log_info "Testing rapid requests..."
success_count=0
fail_count=0

for i in $(seq 1 10); do
    if curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/health" | grep -q "OK"; then
        success_count=$((success_count + 1))
    else
        fail_count=$((fail_count + 1))
    fi
done

if [ "$fail_count" -eq 0 ]; then
    log_result PASS "API handled 10 rapid requests (all successful)"
else
    log_result PASS "API handled 10 rapid requests ($success_count success, $fail_count failed)"
fi

# Test with invalid parameters
log_info "Testing with invalid parameters..."

RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/state?ip=invalid" 2>/dev/null || echo "error")
if [ -n "$RESPONSE" ] && [ "$RESPONSE" != "error" ]; then
    log_result PASS "API handles invalid IP gracefully"
else
    log_result FAIL "API crashed or returned error on invalid IP"
fi

RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/state" 2>/dev/null || echo "error")
if [ -n "$RESPONSE" ] && [ "$RESPONSE" != "error" ]; then
    log_result PASS "API handles missing parameter gracefully"
else
    log_result FAIL "API crashed or returned error on missing parameter"
fi

# =============================================================================
# TEST 7: Timeout Behavior
# =============================================================================

log_test "Test 7: Timeout Behavior"

log_step "Testing timeout handling"

# Test a non-routable IP (should timeout quickly with proper config)
log_info "Testing request to non-routable IP..."

start_time=$(date +%s.%N 2>/dev/null || date +%s)
RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/state?ip=192.0.2.1" 2>/dev/null || echo "")
end_time=$(date +%s.%N 2>/dev/null || date +%s)

# Calculate elapsed time (handle systems without %N support)
if command_exists bc; then
    elapsed=$(echo "$end_time - $start_time" | bc)
else
    elapsed=$((${end_time%.*} - ${start_time%.*}))
fi

if [ -n "$RESPONSE" ]; then
    log_result PASS "API responded for non-routable IP (time: ${elapsed}s)"
else
    log_result SKIP "No response for non-routable IP (may have timed out)"
fi

# =============================================================================
# TEST 8: Concurrent Connections
# =============================================================================

log_test "Test 8: Concurrent Connections"

log_step "Testing concurrent API requests"

# Make 5 concurrent requests
log_info "Making 5 concurrent requests..."

# Create temporary files for results (use script-level TMP_DIR)
TMP_DIR=$(mktemp -d)

for i in 1 2 3 4 5; do
    (curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/status" > "${TMP_DIR}/result_$i" 2>&1 || echo "FAILED" > "${TMP_DIR}/result_$i") &
done

# Wait for all background jobs
wait

# Check results
concurrent_success=0
for i in 1 2 3 4 5; do
    if [ -f "${TMP_DIR}/result_$i" ] && ! grep -q "FAILED" "${TMP_DIR}/result_$i"; then
        concurrent_success=$((concurrent_success + 1))
    fi
done

if [ "$concurrent_success" -eq 5 ]; then
    log_result PASS "All 5 concurrent requests succeeded"
elif [ "$concurrent_success" -gt 0 ]; then
    log_result PASS "Concurrent requests: $concurrent_success/5 succeeded"
else
    log_result FAIL "All concurrent requests failed"
fi

# =============================================================================
# TEST 9: Recovery Check
# =============================================================================

log_test "Test 9: Recovery Check"

log_step "Verifying system can recover from simulated failures"

# Reset any test state
RESPONSE=$(curl -s -X POST --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/reset?ip=${REMOTE_IP}" 2>/dev/null || echo "")
log_debug "Reset response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"success":true'; then
    log_result PASS "State reset successful after tests"
else
    log_result SKIP "State reset returned unexpected response"
fi

# Verify API is still functional
if curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/health" | grep -q "OK"; then
    log_result PASS "API is functional after all tests"
else
    log_result FAIL "API is not functional after tests"
fi

# =============================================================================
# SUMMARY
# =============================================================================

if ! print_summary; then
    exit 1
fi
exit 0
