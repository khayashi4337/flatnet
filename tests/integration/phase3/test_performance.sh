#!/bin/bash
# Flatnet Phase 3 Performance Tests
# Stage 5: Integration Test
#
# This script measures performance metrics:
# - Latency (ping, curl)
# - Throughput (iperf3 if available, or curl)
# - Escalation switch timing
#
# Prerequisites:
# - OpenResty running on Windows with Flatnet modules
# - Nebula tunnel established between hosts
# - For throughput tests: iperf3 on both hosts (optional)
#
# Usage:
#   ./test_performance.sh [GATEWAY_IP] [REMOTE_IP]
#
# Environment Variables:
#   GATEWAY_IP  - Local Gateway IP (default: 10.100.1.1)
#   REMOTE_IP   - Remote container IP (default: 10.100.2.10)
#   API_PORT    - API port (default: 8080)
#   VERBOSE     - Set to 1 for verbose output
#   ITERATIONS  - Number of iterations for latency tests (default: 10)
#   CURL_TIMEOUT - Timeout for curl/ping commands in seconds (default: 5)

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
ITERATIONS="${ITERATIONS:-10}"

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
trap cleanup EXIT

# Performance thresholds (milliseconds)
LATENCY_EXCELLENT=50
LATENCY_GOOD=100
LATENCY_ACCEPTABLE=200
LATENCY_WARNING=500

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
    echo -e "${RED}[ERROR]${NC} $1"
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

# Format latency with color based on threshold
format_latency() {
    local latency="$1"
    local unit="${2:-ms}"

    # Extract numeric value
    local value
    value=$(echo "$latency" | grep -oE '[0-9]+\.?[0-9]*' | head -1)

    if [ -z "$value" ]; then
        echo "$latency"
        return
    fi

    # Compare and color
    local int_value
    int_value=$(printf "%.0f" "$value" 2>/dev/null || echo "$value")

    if [ "$int_value" -le "$LATENCY_EXCELLENT" ]; then
        echo -e "${GREEN}${latency}${unit}${NC} (excellent)"
    elif [ "$int_value" -le "$LATENCY_GOOD" ]; then
        echo -e "${GREEN}${latency}${unit}${NC} (good)"
    elif [ "$int_value" -le "$LATENCY_ACCEPTABLE" ]; then
        echo -e "${YELLOW}${latency}${unit}${NC} (acceptable)"
    elif [ "$int_value" -le "$LATENCY_WARNING" ]; then
        echo -e "${YELLOW}${latency}${unit}${NC} (slow)"
    else
        echo -e "${RED}${latency}${unit}${NC} (very slow)"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Calculate statistics from a list of values
calc_stats() {
    local values="$1"
    local count=0
    local sum=0
    local min=999999
    local max=0

    for v in $values; do
        # Extract numeric value
        local num
        num=$(echo "$v" | grep -oE '[0-9]+\.?[0-9]*' | head -1)
        if [ -n "$num" ]; then
            count=$((count + 1))
            sum=$(echo "$sum + $num" | bc 2>/dev/null || echo "$sum")

            # Update min/max (integer comparison for simplicity)
            local int_num
            int_num=$(printf "%.0f" "$num" 2>/dev/null || echo "$num")
            if [ "$int_num" -lt "$min" ]; then
                min=$int_num
            fi
            if [ "$int_num" -gt "$max" ]; then
                max=$int_num
            fi
        fi
    done

    if [ $count -gt 0 ]; then
        local avg
        avg=$(echo "scale=2; $sum / $count" | bc 2>/dev/null || echo "N/A")
        echo "min=$min max=$max avg=$avg count=$count"
    else
        echo "min=N/A max=N/A avg=N/A count=0"
    fi
}

# =============================================================================
# HEADER
# =============================================================================

echo ""
echo "=============================================="
echo "    Flatnet Phase 3 - Performance Tests"
echo "=============================================="
echo ""
echo "Configuration:"
echo "  Gateway IP:    $GATEWAY_IP"
echo "  Remote IP:     $REMOTE_IP"
echo "  API Port:      $API_PORT"
echo "  Base URL:      $BASE_URL"
echo "  Iterations:    $ITERATIONS"
echo ""
echo "Latency Thresholds:"
echo "  Excellent:   <= ${LATENCY_EXCELLENT}ms"
echo "  Good:        <= ${LATENCY_GOOD}ms"
echo "  Acceptable:  <= ${LATENCY_ACCEPTABLE}ms"
echo "  Warning:     <= ${LATENCY_WARNING}ms"
echo ""

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

log_test "Pre-flight Checks"

if ! curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/health" | grep -q "OK"; then
    log_error "Gateway is not reachable at ${BASE_URL}"
    exit 1
fi
log_info "Gateway is reachable"

# Check for optional tools
HAVE_PING=0
HAVE_IPERF3=0
HAVE_BC=0
HAVE_TIME=0

if command_exists ping; then
    HAVE_PING=1
    log_info "ping is available"
fi

if command_exists iperf3; then
    HAVE_IPERF3=1
    log_info "iperf3 is available"
else
    log_warn "iperf3 not available - throughput tests will use curl"
fi

if command_exists bc; then
    HAVE_BC=1
    log_info "bc is available (for calculations)"
fi

if command_exists time; then
    HAVE_TIME=1
fi

# =============================================================================
# TEST 1: API Latency (Health Endpoint)
# =============================================================================

log_test "Test 1: API Latency (Health Endpoint)"

log_step "Measuring ${ITERATIONS} requests to /api/health"

latencies=""
for i in $(seq 1 $ITERATIONS); do
    start_time=$(date +%s%3N 2>/dev/null || echo "0")
    if curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/health" >/dev/null 2>&1; then
        end_time=$(date +%s%3N 2>/dev/null || echo "0")
        if [ "$start_time" != "0" ] && [ "$end_time" != "0" ]; then
            latency=$((end_time - start_time))
            latencies="$latencies $latency"
            log_debug "Request $i: ${latency}ms"
        fi
    fi
done

if [ -n "$latencies" ] && [ $HAVE_BC -eq 1 ]; then
    stats=$(calc_stats "$latencies")
    eval "$stats"
    echo ""
    echo "  Results:"
    echo "    Minimum: $(format_latency "$min")"
    echo "    Maximum: $(format_latency "$max")"
    echo "    Average: $(format_latency "$avg")"
    echo "    Samples: $count"
else
    log_warn "Could not calculate statistics (bc not available or no successful requests)"
fi

# =============================================================================
# TEST 2: Ping Latency
# =============================================================================

log_test "Test 2: Ping Latency"

if [ $HAVE_PING -eq 1 ]; then
    log_step "Measuring ping latency to Gateway ($GATEWAY_IP)"

    ping_output=$(ping -c "$ITERATIONS" -q "$GATEWAY_IP" 2>/dev/null || echo "failed")
    log_debug "Ping output: $ping_output"

    if echo "$ping_output" | grep -q "rtt"; then
        # Extract statistics
        rtt_stats=$(echo "$ping_output" | grep "rtt" | sed 's/.*= //')
        echo ""
        echo "  Results: $rtt_stats"

        # Parse min/avg/max
        min_rtt=$(echo "$rtt_stats" | cut -d'/' -f1)
        avg_rtt=$(echo "$rtt_stats" | cut -d'/' -f2)
        max_rtt=$(echo "$rtt_stats" | cut -d'/' -f3)

        echo "    Minimum: $(format_latency "$min_rtt")"
        echo "    Average: $(format_latency "$avg_rtt")"
        echo "    Maximum: $(format_latency "$max_rtt")"
    else
        log_warn "Ping to Gateway failed"
    fi

    log_step "Measuring ping latency to Remote ($REMOTE_IP)"

    ping_output=$(ping -c "$ITERATIONS" -q "$REMOTE_IP" 2>/dev/null || echo "failed")
    log_debug "Ping output: $ping_output"

    if echo "$ping_output" | grep -q "rtt"; then
        rtt_stats=$(echo "$ping_output" | grep "rtt" | sed 's/.*= //')
        echo ""
        echo "  Results: $rtt_stats"

        min_rtt=$(echo "$rtt_stats" | cut -d'/' -f1)
        avg_rtt=$(echo "$rtt_stats" | cut -d'/' -f2)
        max_rtt=$(echo "$rtt_stats" | cut -d'/' -f3)

        echo "    Minimum: $(format_latency "$min_rtt")"
        echo "    Average: $(format_latency "$avg_rtt")"
        echo "    Maximum: $(format_latency "$max_rtt")"
    else
        log_warn "Ping to Remote failed (ICMP may be blocked)"
    fi
else
    log_warn "ping not available - skipping"
fi

# =============================================================================
# TEST 3: HTTP Latency via curl
# =============================================================================

log_test "Test 3: HTTP Latency via curl"

log_step "Measuring HTTP latency with curl timing"

# Get detailed timing info from curl
for target in "Gateway:${GATEWAY_IP}" "Remote:${REMOTE_IP}"; do
    name=$(echo "$target" | cut -d':' -f1)
    ip=$(echo "$target" | cut -d':' -f2)

    echo ""
    echo "  $name ($ip):"

    timing=$(curl -s -o /dev/null -w "dns=%{time_namelookup}s connect=%{time_connect}s ttfb=%{time_starttransfer}s total=%{time_total}s" \
        --connect-timeout "$CURL_TIMEOUT" "http://${ip}:${API_PORT}/api/health" 2>/dev/null || echo "failed")

    if [ "$timing" != "failed" ]; then
        log_debug "Timing: $timing"

        # Parse timing values
        dns=$(echo "$timing" | grep -o 'dns=[0-9.]*' | cut -d'=' -f2)
        connect=$(echo "$timing" | grep -o 'connect=[0-9.]*' | cut -d'=' -f2)
        ttfb=$(echo "$timing" | grep -o 'ttfb=[0-9.]*' | cut -d'=' -f2)
        total=$(echo "$timing" | grep -o 'total=[0-9.]*' | cut -d'=' -f2)

        # Convert to milliseconds
        if [ $HAVE_BC -eq 1 ]; then
            dns_ms=$(echo "$dns * 1000" | bc 2>/dev/null || echo "N/A")
            connect_ms=$(echo "$connect * 1000" | bc 2>/dev/null || echo "N/A")
            ttfb_ms=$(echo "$ttfb * 1000" | bc 2>/dev/null || echo "N/A")
            total_ms=$(echo "$total * 1000" | bc 2>/dev/null || echo "N/A")

            echo "    DNS lookup:       ${dns_ms}ms"
            echo "    TCP connect:      ${connect_ms}ms"
            echo "    Time to first byte: ${ttfb_ms}ms"
            echo "    Total time:       $(format_latency "${total_ms%.*}")"
        else
            echo "    DNS lookup:       ${dns}s"
            echo "    TCP connect:      ${connect}s"
            echo "    Time to first byte: ${ttfb}s"
            echo "    Total time:       ${total}s"
        fi
    else
        log_warn "Could not connect to $name"
    fi
done

# =============================================================================
# TEST 4: Throughput Measurement
# =============================================================================

log_test "Test 4: Throughput Measurement"

if [ $HAVE_IPERF3 -eq 1 ]; then
    log_step "Measuring throughput with iperf3"
    log_info "Note: iperf3 server must be running on remote host"
    log_info "  Remote: iperf3 -s"
    log_info ""

    # Try to connect to iperf3 server
    iperf_result=$(timeout 10 iperf3 -c "$REMOTE_IP" -t 5 -J 2>/dev/null || echo "failed")

    if [ "$iperf_result" != "failed" ] && echo "$iperf_result" | grep -q "bits_per_second"; then
        # Parse JSON output
        sent_bps=$(echo "$iperf_result" | grep -o '"bits_per_second":[0-9.]*' | head -1 | cut -d':' -f2)
        recv_bps=$(echo "$iperf_result" | grep -o '"bits_per_second":[0-9.]*' | tail -1 | cut -d':' -f2)

        if [ $HAVE_BC -eq 1 ] && [ -n "$sent_bps" ]; then
            sent_mbps=$(echo "scale=2; $sent_bps / 1000000" | bc)
            recv_mbps=$(echo "scale=2; $recv_bps / 1000000" | bc)
            echo ""
            echo "  Results:"
            echo "    Send: ${sent_mbps} Mbps"
            echo "    Receive: ${recv_mbps} Mbps"
        else
            log_warn "Could not parse iperf3 results"
        fi
    else
        log_warn "iperf3 server not reachable on $REMOTE_IP"
        log_info "To enable throughput testing:"
        log_info "  On remote host: iperf3 -s"
    fi
else
    log_step "Measuring throughput with curl (iperf3 not available)"
    log_info "Downloading from API status endpoint..."

    # Measure download speed using curl
    for i in $(seq 1 3); do
        speed=$(curl -s -o /dev/null -w "%{speed_download}" --connect-timeout "$CURL_TIMEOUT" \
            "${BASE_URL}/api/status" 2>/dev/null || echo "0")
        log_debug "Speed test $i: $speed bytes/sec"
    done

    if [ -n "$speed" ] && [ "$speed" != "0" ]; then
        if [ $HAVE_BC -eq 1 ]; then
            speed_kbps=$(echo "scale=2; $speed / 1024" | bc)
            echo ""
            echo "  Results: ~${speed_kbps} KB/s (limited by small response size)"
        else
            echo ""
            echo "  Results: ~${speed} bytes/s"
        fi
    fi
fi

# =============================================================================
# TEST 5: Escalation Switch Timing
# =============================================================================

log_test "Test 5: Escalation Switch Timing"

log_step "Measuring escalation state transition times"

# Reset state first
curl -s -X POST --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/reset?ip=${REMOTE_IP}" >/dev/null

echo ""
echo "  GATEWAY_ONLY -> P2P_ATTEMPTING:"

# Measure time to initiate P2P attempt
start_time=$(date +%s%3N 2>/dev/null || echo "0")
curl -s -X POST --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/attempt?ip=${REMOTE_IP}" >/dev/null
end_time=$(date +%s%3N 2>/dev/null || echo "0")

if [ "$start_time" != "0" ] && [ "$end_time" != "0" ]; then
    transition_time=$((end_time - start_time))
    echo "    Transition time: $(format_latency "$transition_time")"
fi

# Wait and check P2P establishment
echo ""
echo "  P2P_ATTEMPTING -> P2P_ACTIVE:"
echo "    (Waiting up to 10 seconds for P2P establishment...)"

start_time=$(date +%s%3N 2>/dev/null || echo "0")
p2p_established=0

for i in $(seq 1 10); do
    state=$(curl -s --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/state?ip=${REMOTE_IP}" 2>/dev/null | \
        grep -o '"state":"[^"]*"' | cut -d'"' -f4)

    if [ "$state" = "P2P_ACTIVE" ]; then
        end_time=$(date +%s%3N 2>/dev/null || echo "0")
        p2p_established=1
        break
    fi
    sleep 1
done

if [ $p2p_established -eq 1 ]; then
    if [ "$start_time" != "0" ] && [ "$end_time" != "0" ]; then
        transition_time=$((end_time - start_time))
        echo "    P2P established in: $(format_latency "$transition_time")"
    else
        echo "    P2P established"
    fi
else
    echo "    P2P not established within 10 seconds"
    echo "    (This may be normal if remote is not reachable via P2P)"
fi

# Cleanup
curl -s -X POST --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/escalation/reset?ip=${REMOTE_IP}" >/dev/null

# =============================================================================
# TEST 6: Healthcheck Latency
# =============================================================================

log_test "Test 6: Healthcheck Latency"

log_step "Measuring manual healthcheck execution time"

latencies=""
for i in $(seq 1 5); do
    start_time=$(date +%s%3N 2>/dev/null || echo "0")
    result=$(curl -s -X POST --connect-timeout "$CURL_TIMEOUT" "${BASE_URL}/api/healthcheck/check?ip=${REMOTE_IP}" 2>/dev/null)
    end_time=$(date +%s%3N 2>/dev/null || echo "0")

    if [ "$start_time" != "0" ] && [ "$end_time" != "0" ]; then
        latency=$((end_time - start_time))
        latencies="$latencies $latency"

        # Also extract the reported latency if available
        reported_latency=$(echo "$result" | grep -o '"latency_ms":[0-9.]*' | head -1 | cut -d':' -f2)
        if [ -n "$reported_latency" ]; then
            log_debug "Request $i: API time=${latency}ms, Reported latency=${reported_latency}ms"
        fi
    fi
done

if [ -n "$latencies" ] && [ $HAVE_BC -eq 1 ]; then
    stats=$(calc_stats "$latencies")
    eval "$stats"
    echo ""
    echo "  API Response Time (includes network + processing):"
    echo "    Minimum: $(format_latency "$min")"
    echo "    Maximum: $(format_latency "$max")"
    echo "    Average: $(format_latency "$avg")"
else
    log_warn "Could not calculate statistics"
fi

# =============================================================================
# TEST 7: Concurrent Request Performance
# =============================================================================

log_test "Test 7: Concurrent Request Performance"

log_step "Measuring performance with concurrent requests"

# Create temp directory (use script-level TMP_DIR)
TMP_DIR=$(mktemp -d)

# Test with different concurrency levels
for concurrency in 1 5 10; do
    echo ""
    echo "  Concurrency: $concurrency"

    start_time=$(date +%s%3N 2>/dev/null || echo "0")

    # Launch concurrent requests
    for i in $(seq 1 $concurrency); do
        (curl -s -o /dev/null -w "%{time_total}" --connect-timeout "$CURL_TIMEOUT" \
            "${BASE_URL}/api/health" > "${TMP_DIR}/time_$i" 2>/dev/null || echo "0" > "${TMP_DIR}/time_$i") &
    done

    # Wait for all
    wait

    end_time=$(date +%s%3N 2>/dev/null || echo "0")

    if [ "$start_time" != "0" ] && [ "$end_time" != "0" ]; then
        total_time=$((end_time - start_time))
        echo "    Total time for $concurrency concurrent requests: ${total_time}ms"

        # Calculate average request time
        total_req_time=0
        for i in $(seq 1 $concurrency); do
            req_time=$(cat "${TMP_DIR}/time_$i" 2>/dev/null || echo "0")
            if [ $HAVE_BC -eq 1 ]; then
                req_time_ms=$(echo "$req_time * 1000" | bc 2>/dev/null || echo "0")
                total_req_time=$(echo "$total_req_time + $req_time_ms" | bc 2>/dev/null || echo "$total_req_time")
            fi
        done

        if [ $HAVE_BC -eq 1 ] && [ "$total_req_time" != "0" ]; then
            avg_req_time=$(echo "scale=2; $total_req_time / $concurrency" | bc)
            echo "    Average request time: ${avg_req_time}ms"
        fi
    fi
done

# =============================================================================
# PERFORMANCE SUMMARY
# =============================================================================

log_test "Performance Summary"

echo ""
echo "  Gateway ($GATEWAY_IP):"
echo "    API endpoint: ${BASE_URL}/api/health"

# Final health check with timing
timing=$(curl -s -o /dev/null -w "total=%{time_total}s" --connect-timeout "$CURL_TIMEOUT" \
    "${BASE_URL}/api/health" 2>/dev/null || echo "total=N/As")
total_time=$(echo "$timing" | grep -o 'total=[0-9.]*' | cut -d'=' -f2)
if [ $HAVE_BC -eq 1 ] && [ -n "$total_time" ]; then
    total_ms=$(echo "$total_time * 1000" | bc 2>/dev/null)
    echo "    Current latency: $(format_latency "${total_ms%.*}")"
fi

echo ""
echo "  Remote ($REMOTE_IP):"
if ping -c 1 -W "$CURL_TIMEOUT" "$REMOTE_IP" >/dev/null 2>&1; then
    echo "    Status: Reachable"
else
    echo "    Status: Not reachable via ICMP"
fi

echo ""
echo "  Recommendations:"
# Use final latency measurement for recommendation
if [ $HAVE_BC -eq 1 ] && [ -n "$total_ms" ]; then
    summary_latency=$(printf "%.0f" "${total_ms%.*}" 2>/dev/null || echo "0")
    if [ "$summary_latency" -le "$LATENCY_EXCELLENT" ]; then
        echo "    - Performance is excellent"
    elif [ "$summary_latency" -le "$LATENCY_GOOD" ]; then
        echo "    - Performance is good"
    elif [ "$summary_latency" -le "$LATENCY_ACCEPTABLE" ]; then
        echo "    - Performance is acceptable"
        echo "    - Consider checking network congestion"
    else
        echo "    - Performance needs improvement"
        echo "    - Check Nebula tunnel status"
        echo "    - Consider network optimization"
    fi
else
    echo "    - Unable to measure latency for recommendations"
fi

echo ""
echo "=============================================="
echo "         Performance Tests Complete"
echo "=============================================="

exit 0
