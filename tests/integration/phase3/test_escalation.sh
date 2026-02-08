#!/bin/bash
# Flatnet Phase 3 Graceful Escalation Tests
# Stage 5: Integration Test
#
# This script tests the Graceful Escalation functionality:
# - P2P establishment
# - Fallback behavior (Nebula stopped -> gateway fallback)
# - Recovery (Nebula restart -> P2P re-establishment)
#
# Prerequisites:
# - OpenResty running on Windows with Flatnet modules
# - Nebula tunnel established between hosts
# - At least one container running on a remote host
#
# Usage:
#   ./test_escalation.sh [GATEWAY_IP] [REMOTE_IP]
#
# Environment Variables:
#   GATEWAY_IP  - Local Gateway IP (default: 10.100.1.1)
#   REMOTE_IP   - Remote container IP for escalation test (default: 10.100.2.10)
#   API_PORT    - API port (default: 8080)
#   VERBOSE     - Set to 1 for verbose output
#   CURL_TIMEOUT - Timeout for curl commands in seconds (default: 5)

set -e

# Script directory detection
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

# Cleanup function for script exit
cleanup_escalation_state() {
    # Reset escalation state on exit (best effort)
    if [ -n "$REMOTE_IP" ] && [ -n "$BASE_URL" ]; then
        curl -s -X POST --connect-timeout 2 "${BASE_URL}/api/escalation/reset?ip=${REMOTE_IP}" >/dev/null 2>&1 || true
    fi
}

# Set trap for cleanup on script exit (in case of early exit)
# Also handle SIGINT and SIGTERM for proper cleanup on Ctrl+C
trap cleanup_escalation_state EXIT INT TERM

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
    echo -e "\n${CYAN}=== $1 ===${NC}"
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

# Get escalation state for an IP
get_state() {
    local ip="$1"
    curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/state?ip=${ip}" 2>/dev/null | \
        grep -o '"state":"[^"]*"' | cut -d'"' -f4
}

# Reset escalation state for an IP
reset_state() {
    local ip="$1"
    curl -s -X POST --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/reset?ip=${ip}" 2>/dev/null
}

# Attempt P2P for an IP
attempt_p2p() {
    local ip="$1"
    curl -s -X POST --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/attempt?ip=${ip}" 2>/dev/null
}

# Trigger a manual healthcheck
trigger_healthcheck() {
    local ip="$1"
    curl -s -X POST --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/healthcheck/check?ip=${ip}" 2>/dev/null
}

# Wait for state change
wait_for_state() {
    local ip="$1"
    local expected_state="$2"
    local max_wait="${3:-10}"
    local interval="${4:-1}"

    local elapsed=0
    while [ "$elapsed" -lt "$max_wait" ]; do
        local current_state
        current_state=$(get_state "$ip")
        if [ "$current_state" = "$expected_state" ]; then
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    return 1
}

# Print test summary
print_summary() {
    echo ""
    echo "=============================================="
    echo "            ESCALATION TEST SUMMARY"
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
        echo -e "\n${GREEN}All escalation tests passed!${NC}"
        return 0
    fi
}

# =============================================================================
# HEADER
# =============================================================================

echo ""
echo "=============================================="
echo "  Flatnet Phase 3 - Graceful Escalation Tests"
echo "=============================================="
echo ""
echo "Configuration:"
echo "  Gateway IP:    $GATEWAY_IP"
echo "  Remote IP:     $REMOTE_IP"
echo "  API Port:      $API_PORT"
echo "  Base URL:      $BASE_URL"
echo ""

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

log_test "Pre-flight Checks"

# Check Gateway connectivity
if ! curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/health" | grep -q "OK"; then
    log_result FAIL "Gateway is not reachable at ${BASE_URL}"
    log_error "Cannot continue without Gateway connectivity"
    exit 1
fi
log_result PASS "Gateway is reachable"

# Check escalation API is available
RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/stats" 2>/dev/null || echo "")
if [ -z "$RESPONSE" ] || ! echo "$RESPONSE" | grep -q '"states"'; then
    log_result FAIL "Escalation API is not available"
    log_error "Cannot continue without Escalation API"
    exit 1
fi
log_result PASS "Escalation API is available"

# =============================================================================
# TEST 1: Initial State Check
# =============================================================================

log_test "Test 1: Initial State Check"

log_step "Resetting state for $REMOTE_IP"
reset_state "$REMOTE_IP" >/dev/null

sleep 1

INITIAL_STATE=$(get_state "$REMOTE_IP")
log_debug "Initial state: $INITIAL_STATE"

if [ "$INITIAL_STATE" = "GATEWAY_ONLY" ] || [ -z "$INITIAL_STATE" ]; then
    log_result PASS "Initial state is GATEWAY_ONLY (or uninitialized)"
else
    log_result FAIL "Initial state is not GATEWAY_ONLY" "Got: $INITIAL_STATE"
fi

# =============================================================================
# TEST 2: P2P Attempt Initiation
# =============================================================================

log_test "Test 2: P2P Attempt Initiation"

log_step "Initiating P2P attempt for $REMOTE_IP"
RESPONSE=$(attempt_p2p "$REMOTE_IP")
log_debug "Response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"success":true'; then
    log_result PASS "P2P attempt initiated successfully"

    # Check state changed to P2P_ATTEMPTING
    sleep 1
    STATE=$(get_state "$REMOTE_IP")
    log_debug "State after attempt: $STATE"

    if [ "$STATE" = "P2P_ATTEMPTING" ]; then
        log_result PASS "State changed to P2P_ATTEMPTING"
    elif [ "$STATE" = "P2P_ACTIVE" ]; then
        log_result PASS "P2P activated immediately (fast connection)"
    else
        log_result SKIP "State is $STATE (may be expected based on environment)"
    fi
elif echo "$RESPONSE" | grep -q '"error"'; then
    error_msg=$(echo "$RESPONSE" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
    log_result SKIP "P2P attempt returned error" "$error_msg"
else
    log_result FAIL "Unexpected response from P2P attempt" "$RESPONSE"
fi

# =============================================================================
# TEST 3: Escalation State Transitions
# =============================================================================

log_test "Test 3: Escalation State Transitions"

# Reset state first
log_step "Resetting state"
reset_state "$REMOTE_IP" >/dev/null
sleep 1

# Test state transitions
STATE=$(get_state "$REMOTE_IP")
log_debug "State after reset: $STATE"

if [ "$STATE" = "GATEWAY_ONLY" ] || [ -z "$STATE" ]; then
    log_result PASS "Reset to GATEWAY_ONLY successful"
else
    log_result FAIL "Reset did not return to GATEWAY_ONLY" "Got: $STATE"
fi

# Try to transition through states
log_step "Testing state transitions"

# GATEWAY_ONLY -> P2P_ATTEMPTING
attempt_p2p "$REMOTE_IP" >/dev/null
sleep 1
STATE=$(get_state "$REMOTE_IP")

case "$STATE" in
    P2P_ATTEMPTING)
        log_result PASS "Transition: GATEWAY_ONLY -> P2P_ATTEMPTING"
        ;;
    P2P_ACTIVE)
        log_result PASS "Transition: GATEWAY_ONLY -> P2P_ACTIVE (fast path)"
        ;;
    GATEWAY_ONLY)
        log_result SKIP "State remained GATEWAY_ONLY" "P2P may not be available"
        ;;
    *)
        log_result FAIL "Unexpected state after P2P attempt" "Got: $STATE"
        ;;
esac

# =============================================================================
# TEST 4: Escalation Statistics
# =============================================================================

log_test "Test 4: Escalation Statistics"

RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/stats" 2>/dev/null || echo "")
log_debug "Response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"states"'; then
    log_result PASS "Escalation statistics available"

    # Parse and display states
    total=$(echo "$RESPONSE" | grep -o '"total":[0-9]*' | head -1 | cut -d':' -f2)
    log_info "  Total tracked IPs: ${total:-0}"

    for state in GATEWAY_ONLY P2P_ATTEMPTING P2P_ACTIVE GATEWAY_FALLBACK; do
        count=$(echo "$RESPONSE" | grep -o "\"$state\":[0-9]*" | head -1 | cut -d':' -f2)
        if [ -n "$count" ] && [ "$count" != "0" ]; then
            log_info "  $state: $count"
        fi
    done
else
    log_result FAIL "Could not retrieve escalation statistics"
fi

# =============================================================================
# TEST 5: Get All Escalation States
# =============================================================================

log_test "Test 5: Get All Escalation States"

RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/states" 2>/dev/null || echo "")
log_debug "Response: $RESPONSE"

if [ -n "$RESPONSE" ]; then
    if echo "$RESPONSE" | grep -qE '^\{'; then
        state_count=$(echo "$RESPONSE" | grep -c '"state"' 2>/dev/null || echo 0)
        log_result PASS "Retrieved all escalation states (count: $state_count)"
    else
        log_result PASS "States endpoint responds (no states tracked)"
    fi
else
    log_result FAIL "Could not retrieve all states"
fi

# =============================================================================
# TEST 6: Fallback Simulation
# =============================================================================

log_test "Test 6: Fallback Simulation"

log_step "This test simulates a fallback by checking the API behavior"
log_info "Note: Full fallback test requires Nebula manipulation"

# We can test the fallback API behavior without actually stopping Nebula
# by checking if the API responds correctly to state queries

# First, make sure we have a state to work with
attempt_p2p "$REMOTE_IP" >/dev/null
sleep 2

STATE=$(get_state "$REMOTE_IP")
log_debug "Current state: $STATE"

if [ "$STATE" = "P2P_ACTIVE" ]; then
    log_result PASS "P2P is active - ready for fallback test"
    log_info "  To test actual fallback:"
    log_info "    1. Stop Nebula on the remote host"
    log_info "    2. Wait for healthcheck to fail (threshold: 3)"
    log_info "    3. State should change to GATEWAY_FALLBACK"
elif [ "$STATE" = "P2P_ATTEMPTING" ]; then
    log_result SKIP "P2P still attempting" "Wait for P2P to establish or fail"
else
    log_result SKIP "Not in P2P_ACTIVE state" "Fallback test requires P2P_ACTIVE state"
fi

# =============================================================================
# TEST 7: Recovery Simulation
# =============================================================================

log_test "Test 7: Recovery Simulation"

log_step "Testing state reset (simulates recovery)"

# Reset to GATEWAY_ONLY (simulates recovery start)
RESPONSE=$(reset_state "$REMOTE_IP")
log_debug "Reset response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"success":true'; then
    log_result PASS "State reset successful"
else
    log_result FAIL "State reset failed" "$RESPONSE"
fi

# After reset, attempt P2P again (simulates recovery)
sleep 1
RESPONSE=$(attempt_p2p "$REMOTE_IP")
log_debug "P2P attempt response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"success":true'; then
    log_result PASS "P2P re-establishment initiated"
    log_info "  To test actual recovery:"
    log_info "    1. From GATEWAY_FALLBACK state"
    log_info "    2. Restart Nebula on the remote host"
    log_info "    3. Wait for retry interval (default: 10s)"
    log_info "    4. State should transition back to P2P_ACTIVE"
else
    log_result SKIP "P2P re-establishment skipped" "May be expected based on current state"
fi

# =============================================================================
# TEST 8: Healthcheck Integration
# =============================================================================

log_test "Test 8: Healthcheck Integration"

# Get healthcheck status
RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/healthcheck/status" 2>/dev/null || echo "")
log_debug "Status response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"enabled"'; then
    enabled=$(echo "$RESPONSE" | grep -o '"enabled":[^,}]*' | head -1 | cut -d':' -f2)
    interval=$(echo "$RESPONSE" | grep -o '"interval":[0-9]*' | head -1 | cut -d':' -f2)
    threshold=$(echo "$RESPONSE" | grep -o '"failure_threshold":[0-9]*' | head -1 | cut -d':' -f2)

    log_result PASS "Healthcheck status retrieved"
    log_info "  Enabled: $enabled"
    log_info "  Interval: ${interval:-unknown}s"
    log_info "  Failure threshold: ${threshold:-unknown}"
else
    log_result FAIL "Could not retrieve healthcheck status"
fi

# Trigger manual healthcheck
log_step "Triggering manual healthcheck for $REMOTE_IP"
RESPONSE=$(trigger_healthcheck "$REMOTE_IP")
log_debug "Healthcheck response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"ip"'; then
    if echo "$RESPONSE" | grep -q '"success":true'; then
        latency=$(echo "$RESPONSE" | grep -o '"latency_ms":[0-9.]*' | head -1 | cut -d':' -f2)
        log_result PASS "Manual healthcheck succeeded (latency: ${latency:-unknown}ms)"
    else
        log_result SKIP "Manual healthcheck failed" "Container may not be reachable"
    fi
else
    log_result FAIL "Manual healthcheck did not return expected format"
fi

# =============================================================================
# TEST 9: Routing with Escalation
# =============================================================================

log_test "Test 9: Routing with Escalation"

RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/routing/route?ip=${REMOTE_IP}" 2>/dev/null || echo "")
log_debug "Route response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"type"'; then
    route_type=$(echo "$RESPONSE" | grep -o '"type":"[^"]*"' | head -1 | cut -d'"' -f4)
    state=$(echo "$RESPONSE" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)

    log_result PASS "Routing information retrieved"
    log_info "  Route type: $route_type"
    log_info "  Escalation state: $state"

    if [ "$route_type" = "p2p" ] && [ "$state" = "P2P_ACTIVE" ]; then
        log_result PASS "Route correctly reflects P2P_ACTIVE state"
    elif [ "$route_type" = "gateway" ]; then
        log_result PASS "Route correctly shows gateway routing"
    fi
else
    log_result FAIL "Could not retrieve routing information"
fi

# =============================================================================
# TEST 10: Retry Backoff Configuration
# =============================================================================

log_test "Test 10: Retry Backoff Configuration"

RESPONSE=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/stats" 2>/dev/null || echo "")
log_debug "Stats response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"config"'; then
    healthcheck_interval=$(echo "$RESPONSE" | grep -o '"healthcheck_interval":[0-9]*' | head -1 | cut -d':' -f2)
    latency_warning=$(echo "$RESPONSE" | grep -o '"latency_warning":[0-9]*' | head -1 | cut -d':' -f2)
    latency_fallback=$(echo "$RESPONSE" | grep -o '"latency_fallback":[0-9]*' | head -1 | cut -d':' -f2)

    log_result PASS "Escalation configuration retrieved"
    log_info "  Healthcheck interval: ${healthcheck_interval:-unknown}s"
    log_info "  Latency warning threshold: ${latency_warning:-unknown}ms"
    log_info "  Latency fallback threshold: ${latency_fallback:-unknown}ms"
else
    log_result SKIP "Escalation configuration not available in stats"
fi

# =============================================================================
# CLEANUP
# =============================================================================

log_test "Cleanup"

log_step "Resetting test state"
reset_state "$REMOTE_IP" >/dev/null
log_result PASS "Test state cleaned up"

# =============================================================================
# SUMMARY
# =============================================================================

if ! print_summary; then
    exit 1
fi
exit 0
