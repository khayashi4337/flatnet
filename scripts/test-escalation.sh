#!/bin/bash
# Flatnet Escalation Test Script
# Phase 3, Stage 4: Graceful Escalation
#
# This script tests the Graceful Escalation functionality.
#
# Prerequisites:
# - OpenResty running on Windows with Flatnet modules
# - Nebula IP is configured (default: 10.100.1.1)
#
# Usage:
#   ./scripts/test-escalation.sh [GATEWAY_IP]

set -e

# Configuration
GATEWAY_IP="${1:-10.100.1.1}"
API_PORT="8080"
BASE_URL="http://${GATEWAY_IP}:${API_PORT}"

# Test container IP (update with actual container IP)
TEST_IP="${TEST_IP:-10.100.2.10}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_test() {
    echo -e "\n${GREEN}=== $1 ===${NC}"
}

check_response() {
    local response="$1"
    local expected="$2"
    local description="$3"

    if echo "$response" | grep -q "$expected"; then
        log_info "PASS: $description"
        return 0
    else
        log_error "FAIL: $description"
        log_error "Expected: $expected"
        log_error "Got: $response"
        return 1
    fi
}

# Check if Gateway is reachable
log_test "Checking Gateway connectivity"
if curl -s --connect-timeout 5 "${BASE_URL}/api/health" | grep -q "OK"; then
    log_info "Gateway is reachable at ${BASE_URL}"
else
    log_error "Cannot reach Gateway at ${BASE_URL}"
    log_warn "Make sure OpenResty is running and Nebula tunnel is established"
    exit 1
fi

# Test 1: API Status
log_test "Test 1: API Status Endpoint"
RESPONSE=$(curl -s "${BASE_URL}/api/status")
echo "Response: $RESPONSE" | head -c 500
echo ""

if echo "$RESPONSE" | grep -q '"stage":"4"'; then
    log_info "PASS: Stage 4 status confirmed"
else
    log_warn "Stage version mismatch or API not updated"
fi

# Test 2: Escalation Stats
log_test "Test 2: Escalation Statistics"
RESPONSE=$(curl -s "${BASE_URL}/api/escalation/stats")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"states"'; then
    log_info "PASS: Escalation stats available"
else
    log_error "FAIL: Escalation stats not available"
fi

# Test 3: Get Escalation State (Initial)
log_test "Test 3: Get Escalation State for ${TEST_IP}"
RESPONSE=$(curl -s "${BASE_URL}/api/escalation/state?ip=${TEST_IP}")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"state":"GATEWAY_ONLY"'; then
    log_info "PASS: Initial state is GATEWAY_ONLY"
else
    log_warn "Initial state may not be GATEWAY_ONLY (could be cached)"
fi

# Test 4: Routing Route
log_test "Test 4: Get Route for ${TEST_IP}"
RESPONSE=$(curl -s "${BASE_URL}/api/routing/route?ip=${TEST_IP}")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"type"'; then
    log_info "PASS: Route info available"
else
    log_error "FAIL: Route info not available"
fi

# Test 5: Attempt P2P
log_test "Test 5: Attempt P2P for ${TEST_IP}"
RESPONSE=$(curl -s -X POST "${BASE_URL}/api/escalation/attempt?ip=${TEST_IP}")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"success":true'; then
    log_info "PASS: P2P attempt initiated"

    # Check state changed
    sleep 1
    RESPONSE=$(curl -s "${BASE_URL}/api/escalation/state?ip=${TEST_IP}")
    echo "State after attempt: $RESPONSE"
elif echo "$RESPONSE" | grep -q '"error"'; then
    log_warn "P2P attempt failed (may be expected based on current state)"
    echo "Error: $RESPONSE"
fi

# Test 6: Healthcheck Status
log_test "Test 6: Healthcheck Status"
RESPONSE=$(curl -s "${BASE_URL}/api/healthcheck/status")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"enabled"'; then
    log_info "PASS: Healthcheck status available"
else
    log_error "FAIL: Healthcheck status not available"
fi

# Test 7: All Escalation States
log_test "Test 7: Get All Escalation States"
RESPONSE=$(curl -s "${BASE_URL}/api/escalation/states")
echo "Response: $RESPONSE"
log_info "All states retrieved"

# Test 8: All Routes
log_test "Test 8: Get All Routes"
RESPONSE=$(curl -s "${BASE_URL}/api/routing/routes")
echo "Response: $RESPONSE"
log_info "All routes retrieved"

# Test 9: Reset Escalation State
log_test "Test 9: Reset Escalation State for ${TEST_IP}"
RESPONSE=$(curl -s -X POST "${BASE_URL}/api/escalation/reset?ip=${TEST_IP}")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"success":true'; then
    log_info "PASS: Escalation state reset"

    # Verify reset
    RESPONSE=$(curl -s "${BASE_URL}/api/escalation/state?ip=${TEST_IP}")
    if echo "$RESPONSE" | grep -q '"state":"GATEWAY_ONLY"'; then
        log_info "PASS: State confirmed as GATEWAY_ONLY after reset"
    fi
else
    log_error "FAIL: Could not reset escalation state"
fi

# Test 10: Manual Healthcheck
log_test "Test 10: Manual Healthcheck for ${TEST_IP}"
RESPONSE=$(curl -s -X POST "${BASE_URL}/api/healthcheck/check?ip=${TEST_IP}")
echo "Response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"ip"'; then
    log_info "PASS: Manual healthcheck executed"
    if echo "$RESPONSE" | grep -q '"success":true'; then
        log_info "Healthcheck succeeded"
    else
        log_warn "Healthcheck failed (container may not be reachable)"
    fi
else
    log_error "FAIL: Could not execute manual healthcheck"
fi

# Summary
log_test "Test Summary"
echo ""
log_info "Escalation API tests completed"
log_info "Gateway: ${BASE_URL}"
log_info "Test IP: ${TEST_IP}"
echo ""
log_warn "Note: Some tests may show warnings if containers are not running"
log_warn "This is expected in a development environment"
echo ""

# Integration test hints
log_test "Integration Test Hints"
cat << 'EOF'
To test the full Graceful Escalation flow:

1. Register a container on another host:
   curl -X POST http://<peer-gateway>:8080/api/containers \
     -H "Content-Type: application/json" \
     -d '{"id":"test-container","ip":"10.100.2.10","hostId":2}'

2. Monitor escalation state during a request:
   watch -n 1 'curl -s http://10.100.1.1:8080/api/escalation/state?ip=10.100.2.10'

3. Make a request to the container (triggers P2P attempt):
   curl -v http://10.100.1.1:8080/api/routing/route?ip=10.100.2.10

4. Simulate P2P failure (stop Nebula on Host B):
   # On Host B: Stop-Service Nebula

5. Verify fallback (request should still succeed):
   curl -v http://10.100.1.1:8080/api/escalation/state?ip=10.100.2.10

6. Restore P2P (restart Nebula on Host B):
   # On Host B: Start-Service Nebula

7. Watch for P2P re-establishment:
   watch -n 1 'curl -s http://10.100.1.1:8080/api/escalation/state?ip=10.100.2.10'
EOF

exit 0
