#!/bin/bash
# Flatnet Phase 3 Basic Functionality Tests
# Stage 5: Integration Test
#
# This script tests basic functionality in a multi-host environment:
# - Container startup with Flatnet IP assignment
# - Cross-host communication
# - Gateway access
#
# Prerequisites:
# - OpenResty running on Windows with Flatnet modules
# - Nebula tunnel established between hosts
# - At least one container running on a remote host
#
# Usage:
#   ./test_basic.sh [GATEWAY_IP] [REMOTE_IP]
#
# Environment Variables:
#   GATEWAY_IP  - Local Gateway IP (default: 10.100.1.1)
#   REMOTE_IP   - Remote container IP for cross-host test (default: 10.100.2.10)
#   API_PORT    - API port (default: 8080)
#   VERBOSE     - Set to 1 for verbose output
#   CURL_TIMEOUT - Timeout for curl/ping commands in seconds (default: 5)

set -e

# Script directory detection (works even when called from another directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Configuration
GATEWAY_IP="${1:-${GATEWAY_IP:-10.100.1.1}}"
REMOTE_IP="${2:-${REMOTE_IP:-10.100.2.10}}"
API_PORT="${API_PORT:-8080}"
BASE_URL="http://${GATEWAY_IP}:${API_PORT}"
VERBOSE="${VERBOSE:-0}"

# Default timeout for curl commands (seconds)
CURL_TIMEOUT="${CURL_TIMEOUT:-5}"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    echo -e "\n${BLUE}=== $1 ===${NC}"
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

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check HTTP response
check_http_status() {
    local url="$1"
    local expected_status="${2:-200}"
    local timeout="${3:-$CURL_TIMEOUT}"

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$timeout" --max-time "$((timeout * 2))" "$url" 2>/dev/null || echo "000")

    if [ "$status" = "$expected_status" ]; then
        return 0
    else
        return 1
    fi
}

# Print test summary
print_summary() {
    echo ""
    echo "=============================================="
    echo "               TEST SUMMARY"
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
        echo -e "\n${GREEN}All tests passed!${NC}"
        return 0
    fi
}

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

echo ""
echo "=============================================="
echo "  Flatnet Phase 3 - Basic Functionality Tests"
echo "=============================================="
echo ""
echo "Configuration:"
echo "  Gateway IP:    $GATEWAY_IP"
echo "  Remote IP:     $REMOTE_IP"
echo "  API Port:      $API_PORT"
echo "  Base URL:      $BASE_URL"
echo ""

# Check prerequisites
log_test "Pre-flight Checks"

if ! command_exists curl; then
    log_error "curl is required but not installed"
    exit 1
fi
log_result PASS "curl is available"

if ! command_exists ping; then
    log_warn "ping is not available - some tests will be skipped"
fi

# =============================================================================
# TEST 1: Gateway Connectivity
# =============================================================================

log_test "Test 1: Gateway Connectivity"

if check_http_status "${BASE_URL}/api/health" 200 "$CURL_TIMEOUT"; then
    log_result PASS "Gateway is reachable at ${BASE_URL}"
else
    log_result FAIL "Cannot reach Gateway at ${BASE_URL}" "Make sure OpenResty is running and Nebula tunnel is established"
    log_error "Cannot continue without Gateway connectivity"
    exit 1
fi

# =============================================================================
# TEST 2: API Status Check
# =============================================================================

log_test "Test 2: API Status Check"

RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/status" 2>/dev/null || echo "")
log_debug "Response: $RESPONSE"

if [ -n "$RESPONSE" ]; then
    log_result PASS "API status endpoint responds"

    # Check for stage information
    if echo "$RESPONSE" | grep -q '"stage"'; then
        stage=$(echo "$RESPONSE" | grep -o '"stage":"[^"]*"' | head -1)
        log_result PASS "Stage information available: $stage"
    else
        log_result SKIP "Stage information not found in response"
    fi
else
    log_result FAIL "API status endpoint did not respond"
fi

# =============================================================================
# TEST 3: Container Registry Status
# =============================================================================

log_test "Test 3: Container Registry Status"

RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/containers" 2>/dev/null || echo "")
log_debug "Response: $RESPONSE"

if [ -n "$RESPONSE" ]; then
    if echo "$RESPONSE" | grep -qE '^\['; then
        count=$(echo "$RESPONSE" | grep -c '"id"' 2>/dev/null || echo 0)
        log_result PASS "Container registry responds (containers: $count)"
    else
        log_result PASS "Container registry responds (empty or different format)"
    fi
else
    log_result FAIL "Container registry did not respond"
fi

# =============================================================================
# TEST 4: Flatnet IP Assignment Check
# =============================================================================

log_test "Test 4: Flatnet IP Assignment (Local)"

# Check if we can query local containers
RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/containers" 2>/dev/null || echo "[]")
log_debug "Response: $RESPONSE"

if echo "$RESPONSE" | grep -qE '"ip"[ 	]*:[ 	]*"10\.[0-9]+\.[0-9]+\.[0-9]+"'; then
    log_result PASS "Containers have Flatnet IP addresses assigned"

    # Extract first IP for display
    first_ip=$(echo "$RESPONSE" | grep -o '"ip":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$first_ip" ]; then
        log_info "  Sample IP: $first_ip"
    fi
else
    log_result SKIP "No containers with Flatnet IPs found" "This may be normal if no containers are running"
fi

# =============================================================================
# TEST 5: Cross-Host Communication Check
# =============================================================================

log_test "Test 5: Cross-Host Communication"

# First, check if remote IP is reachable via ping
if command_exists ping; then
    if ping -c 1 -W "$CURL_TIMEOUT" "$REMOTE_IP" >/dev/null 2>&1; then
        log_result PASS "Remote host $REMOTE_IP is reachable (ping)"
    else
        log_result SKIP "Remote host $REMOTE_IP is not reachable via ping" "This may be expected if ICMP is blocked"
    fi
else
    log_result SKIP "ping not available"
fi

# Check routing information for remote IP
RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/routing/route?ip=${REMOTE_IP}" 2>/dev/null || echo "")
log_debug "Response: $RESPONSE"

if [ -n "$RESPONSE" ]; then
    if echo "$RESPONSE" | grep -q '"type"'; then
        route_type=$(echo "$RESPONSE" | grep -o '"type":"[^"]*"' | head -1 | cut -d'"' -f4)
        log_result PASS "Routing information available for $REMOTE_IP (type: $route_type)"
    else
        log_result PASS "Routing query responded"
    fi
else
    log_result FAIL "Routing query for $REMOTE_IP did not respond"
fi

# =============================================================================
# TEST 6: Gateway Access (Proxy)
# =============================================================================

log_test "Test 6: Gateway Access (HTTP Proxy)"

# Check if we can get escalation state (indicates gateway is properly configured)
RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/state?ip=${REMOTE_IP}" 2>/dev/null || echo "")
log_debug "Response: $RESPONSE"

if [ -n "$RESPONSE" ]; then
    if echo "$RESPONSE" | grep -q '"state"'; then
        state=$(echo "$RESPONSE" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
        log_result PASS "Escalation state for $REMOTE_IP: $state"
    else
        log_result PASS "Escalation API responded"
    fi
else
    log_result FAIL "Escalation API did not respond"
fi

# =============================================================================
# TEST 7: Sync Status Check
# =============================================================================

log_test "Test 7: Sync Status Check"

RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/sync/status" 2>/dev/null || echo "")
log_debug "Response: $RESPONSE"

if [ -n "$RESPONSE" ]; then
    if echo "$RESPONSE" | grep -q '"peer_count"'; then
        peer_count=$(echo "$RESPONSE" | grep -o '"peer_count":[0-9]*' | head -1 | cut -d':' -f2)
        log_result PASS "Sync status available (peers: ${peer_count:-0})"
    else
        log_result PASS "Sync status endpoint responds"
    fi
else
    log_result SKIP "Sync status endpoint not available" "Multi-host sync may not be configured"
fi

# =============================================================================
# TEST 8: Health Check System
# =============================================================================

log_test "Test 8: Health Check System"

RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/healthcheck/status" 2>/dev/null || echo "")
log_debug "Response: $RESPONSE"

if [ -n "$RESPONSE" ]; then
    if echo "$RESPONSE" | grep -q '"enabled"'; then
        enabled=$(echo "$RESPONSE" | grep -o '"enabled":[^,}]*' | head -1 | cut -d':' -f2)
        log_result PASS "Health check system status: enabled=$enabled"
    else
        log_result PASS "Health check status endpoint responds"
    fi
else
    log_result FAIL "Health check status endpoint did not respond"
fi

# =============================================================================
# TEST 9: All Routes Query
# =============================================================================

log_test "Test 9: All Routes Query"

RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/routing/routes" 2>/dev/null || echo "")
log_debug "Response: $RESPONSE"

if [ -n "$RESPONSE" ]; then
    if echo "$RESPONSE" | grep -qE '^\{'; then
        route_count=$(echo "$RESPONSE" | grep -c '"type"' 2>/dev/null || echo 0)
        log_result PASS "All routes query successful (routes: $route_count)"
    else
        log_result PASS "Routes endpoint responds"
    fi
else
    log_result SKIP "Routes endpoint did not respond" "No routes may be registered"
fi

# =============================================================================
# TEST 10: Escalation Statistics
# =============================================================================

log_test "Test 10: Escalation Statistics"

RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/stats" 2>/dev/null || echo "")
log_debug "Response: $RESPONSE"

if [ -n "$RESPONSE" ]; then
    if echo "$RESPONSE" | grep -q '"states"'; then
        log_result PASS "Escalation statistics available"

        # Display state counts
        for state in GATEWAY_ONLY P2P_ATTEMPTING P2P_ACTIVE GATEWAY_FALLBACK; do
            count=$(echo "$RESPONSE" | grep -o "\"$state\":[0-9]*" | head -1 | cut -d':' -f2)
            if [ -n "$count" ]; then
                log_info "  $state: $count"
            fi
        done
    else
        log_result PASS "Escalation stats endpoint responds"
    fi
else
    log_result FAIL "Escalation stats endpoint did not respond"
fi

# =============================================================================
# SUMMARY
# =============================================================================

if ! print_summary; then
    exit 1
fi
# Explicitly exit with success (trap cleanup runs automatically)
exit 0
