#!/bin/bash
# Test script for Flatnet CNI plugin
# Usage: ./scripts/test-cni.sh [binary_path]
#
# This script tests the CNI plugin with various commands and validates
# the output format according to CNI spec 1.0.0.

set -e

# Configuration
# Change to project root first to resolve relative paths correctly
cd "$(dirname "$0")/.."
BINARY="${1:-$(pwd)/src/flatnet-cni/target/release/flatnet}"
CNI_CONFIG='{"cniVersion":"1.0.0","name":"flatnet","type":"flatnet","ipam":{"type":"flatnet-ipam","subnet":"10.87.1.0/24","gateway":"10.87.1.1"}}'
CNI_CONFIG_MINIMAL='{"cniVersion":"1.0.0","name":"flatnet","type":"flatnet"}'

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0

# Test helper functions
pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    FAILED=$((FAILED + 1))
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Build if needed
build_if_needed() {
    if [[ ! -f "$BINARY" ]]; then
        echo "Building flatnet CNI plugin..."
        (cd src/flatnet-cni && cargo build --release --quiet)
    fi
}

# Test functions
test_version() {
    echo ""
    echo "=== Testing VERSION command ==="

    local output
    output=$(echo "$CNI_CONFIG" | \
        CNI_COMMAND=VERSION \
        CNI_PATH=/opt/cni/bin \
        "$BINARY" 2>/dev/null)

    # Check if output is valid JSON
    if echo "$output" | jq . > /dev/null 2>&1; then
        pass "VERSION returns valid JSON"
    else
        fail "VERSION does not return valid JSON: $output"
        return
    fi

    # Check required fields
    if echo "$output" | jq -e '.cniVersion' > /dev/null 2>&1; then
        pass "VERSION contains cniVersion"
    else
        fail "VERSION missing cniVersion"
    fi

    if echo "$output" | jq -e '.supportedVersions' > /dev/null 2>&1; then
        pass "VERSION contains supportedVersions"
    else
        fail "VERSION missing supportedVersions"
    fi

    # Check supported versions include 1.0.0
    if echo "$output" | jq -e '.supportedVersions | index("1.0.0")' > /dev/null 2>&1; then
        pass "VERSION supports 1.0.0"
    else
        fail "VERSION does not support 1.0.0"
    fi
}

test_add() {
    echo ""
    echo "=== Testing ADD command ==="

    local output
    output=$(echo "$CNI_CONFIG" | \
        CNI_COMMAND=ADD \
        CNI_CONTAINERID=test123abc456 \
        CNI_NETNS=/proc/self/ns/net \
        CNI_IFNAME=eth0 \
        CNI_PATH=/opt/cni/bin \
        "$BINARY" 2>/dev/null)

    # Check if output is valid JSON
    if echo "$output" | jq . > /dev/null 2>&1; then
        pass "ADD returns valid JSON"
    else
        fail "ADD does not return valid JSON: $output"
        return
    fi

    # Check required fields
    if echo "$output" | jq -e '.cniVersion' > /dev/null 2>&1; then
        pass "ADD contains cniVersion"
    else
        fail "ADD missing cniVersion"
    fi

    if echo "$output" | jq -e '.interfaces' > /dev/null 2>&1; then
        pass "ADD contains interfaces"
    else
        fail "ADD missing interfaces"
    fi

    if echo "$output" | jq -e '.ips' > /dev/null 2>&1; then
        pass "ADD contains ips"
    else
        fail "ADD missing ips"
    fi

    # Check IP address is from configured subnet
    local ip
    ip=$(echo "$output" | jq -r '.ips[0].address')
    if [[ "$ip" == 10.87.1.* ]]; then
        pass "ADD assigns IP from configured subnet: $ip"
    else
        fail "ADD IP not from configured subnet: $ip"
    fi

    # Check MAC address format
    local mac
    mac=$(echo "$output" | jq -r '.interfaces[0].mac')
    if [[ "$mac" =~ ^02:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}$ ]]; then
        pass "ADD generates valid MAC address: $mac"
    else
        fail "ADD MAC address format invalid: $mac"
    fi
}

test_add_minimal() {
    echo ""
    echo "=== Testing ADD command (minimal config) ==="

    local output
    output=$(echo "$CNI_CONFIG_MINIMAL" | \
        CNI_COMMAND=ADD \
        CNI_CONTAINERID=minimal123 \
        CNI_NETNS=/proc/self/ns/net \
        CNI_IFNAME=eth0 \
        CNI_PATH=/opt/cni/bin \
        "$BINARY" 2>/dev/null)

    # Check if output is valid JSON
    if echo "$output" | jq . > /dev/null 2>&1; then
        pass "ADD (minimal) returns valid JSON"
    else
        fail "ADD (minimal) does not return valid JSON: $output"
        return
    fi

    # Check default IP is used when no IPAM config
    local ip
    ip=$(echo "$output" | jq -r '.ips[0].address')
    if [[ -n "$ip" && "$ip" != "null" ]]; then
        pass "ADD (minimal) assigns default IP: $ip"
    else
        fail "ADD (minimal) missing IP address"
    fi
}

test_del() {
    echo ""
    echo "=== Testing DEL command ==="

    local output
    local exit_code
    output=$(echo "$CNI_CONFIG" | \
        CNI_COMMAND=DEL \
        CNI_CONTAINERID=test123 \
        CNI_NETNS=/proc/self/ns/net \
        CNI_IFNAME=eth0 \
        CNI_PATH=/opt/cni/bin \
        "$BINARY" 2>/dev/null)
    exit_code=$?

    # DEL should succeed with exit code 0
    if [[ $exit_code -eq 0 ]]; then
        pass "DEL exits with code 0"
    else
        fail "DEL exits with code $exit_code"
    fi

    # DEL should output nothing on success
    if [[ -z "$output" ]]; then
        pass "DEL outputs nothing on success"
    else
        warn "DEL produced output (should be empty): $output"
    fi
}

test_check() {
    echo ""
    echo "=== Testing CHECK command ==="

    local output
    local exit_code
    output=$(echo "$CNI_CONFIG" | \
        CNI_COMMAND=CHECK \
        CNI_CONTAINERID=test123 \
        CNI_NETNS=/proc/self/ns/net \
        CNI_IFNAME=eth0 \
        CNI_PATH=/opt/cni/bin \
        "$BINARY" 2>/dev/null)
    exit_code=$?

    # CHECK should succeed with exit code 0
    if [[ $exit_code -eq 0 ]]; then
        pass "CHECK exits with code 0"
    else
        fail "CHECK exits with code $exit_code"
    fi

    # CHECK should output nothing on success
    if [[ -z "$output" ]]; then
        pass "CHECK outputs nothing on success"
    else
        warn "CHECK produced output (should be empty): $output"
    fi
}

test_invalid_command() {
    echo ""
    echo "=== Testing INVALID command ==="

    local stderr_output
    local exit_code=0
    stderr_output=$(echo "$CNI_CONFIG" | \
        CNI_COMMAND=INVALID \
        CNI_PATH=/opt/cni/bin \
        "$BINARY" 2>&1 >/dev/null) || exit_code=$?

    # Should fail with non-zero exit code
    if [[ $exit_code -ne 0 ]]; then
        pass "INVALID command exits with non-zero code"
    else
        fail "INVALID command should fail"
    fi

    # Error should be valid JSON
    if echo "$stderr_output" | jq . > /dev/null 2>&1; then
        pass "Error output is valid JSON"
    else
        fail "Error output is not valid JSON: $stderr_output"
    fi

    # Error should contain code and msg
    if echo "$stderr_output" | jq -e '.code' > /dev/null 2>&1; then
        pass "Error contains code"
    else
        fail "Error missing code"
    fi

    if echo "$stderr_output" | jq -e '.msg' > /dev/null 2>&1; then
        pass "Error contains msg"
    else
        fail "Error missing msg"
    fi
}

test_missing_env() {
    echo ""
    echo "=== Testing missing environment variables ==="

    local stderr_output
    local exit_code=0

    # Missing CNI_COMMAND
    stderr_output=$(echo "$CNI_CONFIG" | \
        "$BINARY" 2>&1 >/dev/null) || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        pass "Missing CNI_COMMAND fails"
    else
        fail "Missing CNI_COMMAND should fail"
    fi

    # Missing CNI_CONTAINERID for ADD
    exit_code=0
    stderr_output=$(echo "$CNI_CONFIG" | \
        CNI_COMMAND=ADD \
        CNI_NETNS=/proc/self/ns/net \
        CNI_IFNAME=eth0 \
        CNI_PATH=/opt/cni/bin \
        "$BINARY" 2>&1 >/dev/null) || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        pass "ADD without CNI_CONTAINERID fails"
    else
        fail "ADD without CNI_CONTAINERID should fail"
    fi
}

# Main
echo "========================================"
echo "Flatnet CNI Plugin Test Suite"
echo "========================================"

# Build if needed
build_if_needed

# Check binary exists
if [[ ! -f "$BINARY" ]]; then
    echo -e "${RED}Error: Binary not found at $BINARY${NC}"
    exit 1
fi

echo "Binary: $BINARY"
echo "CNI Config: $CNI_CONFIG"

# Run tests
test_version
test_add
test_add_minimal
test_del
test_check
test_invalid_command
test_missing_env

# Summary
echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi

echo ""
echo "All tests passed!"
