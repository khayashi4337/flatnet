#!/bin/bash
# Flatnet Phase 4 Load Test Script
# Stage 5: Validation
#
# This script performs load testing using wrk or hey (with fallback).
# It tests multiple load levels and outputs results in both human-readable
# and JSON formats.
#
# Prerequisites:
# - wrk or hey installed
# - Gateway running and accessible
#
# Usage:
#   ./load-test.sh [OPTIONS]
#
# Options:
#   -u, --url URL       Target URL (default: auto-detect Gateway)
#   -d, --duration SEC  Duration per test in seconds (default: 30)
#   -o, --output DIR    Output directory for results (default: ./results)
#   -l, --levels LIST   Comma-separated concurrency levels (default: 10,50,100,200)
#   -t, --threads NUM   Number of threads for wrk (default: auto)
#   -j, --json          Output JSON only (no human-readable summary)
#   -h, --help          Show this help message
#
# Environment Variables:
#   GATEWAY_IP          Gateway IP address
#   GATEWAY_PORT        Gateway port (default: 80)
#
# Exit Codes:
#   0 - All tests completed successfully
#   1 - Error (missing tools, unreachable target, etc.)
#
# Error Recovery:
#   - If a test is interrupted (Ctrl+C), partial results are saved
#   - Re-run with same parameters to continue testing
#   - Check ./results directory for individual test results

set -e

# Trap SIGINT for graceful shutdown
INTERRUPTED=0
trap 'INTERRUPTED=1; log_warn "Interrupted by user. Saving partial results..."' INT

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Default configuration
DEFAULT_DURATION=30
DEFAULT_OUTPUT_DIR="${SCRIPT_DIR}/results"
DEFAULT_LEVELS="10,50,100,200"
GATEWAY_PORT="${GATEWAY_PORT:-80}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Global variables
TARGET_URL=""
DURATION="$DEFAULT_DURATION"
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
LEVELS="$DEFAULT_LEVELS"
THREADS=""
JSON_ONLY=0
LOAD_TOOL=""
RESULTS_JSON="[]"

# Helper functions
log_info() {
    if [ "$JSON_ONLY" -eq 0 ]; then
        echo -e "${GREEN}[INFO]${NC} $1"
    fi
}

log_warn() {
    if [ "$JSON_ONLY" -eq 0 ]; then
        echo -e "${YELLOW}[WARN]${NC} $1"
    fi
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_step() {
    if [ "$JSON_ONLY" -eq 0 ]; then
        echo -e "\n${CYAN}>>> $1${NC}"
    fi
}

show_help() {
    # Extract help text from script header (lines 2-36 to capture all documentation)
    sed -n '2,36p' "$0" | grep -E '^#' | sed 's/^# //' | sed 's/^#//'
    exit 0
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect load testing tool
detect_tool() {
    if command_exists wrk; then
        LOAD_TOOL="wrk"
        log_info "Using wrk for load testing"
    elif command_exists hey; then
        LOAD_TOOL="hey"
        log_info "Using hey for load testing"
    else
        log_error "Neither wrk nor hey is installed."
        echo ""
        echo "Install wrk:"
        echo "  sudo apt install build-essential libssl-dev git"
        echo "  git clone https://github.com/wg/wrk.git"
        echo "  cd wrk && make && sudo cp wrk /usr/local/bin/"
        echo ""
        echo "Or install hey:"
        echo "  go install github.com/rakyll/hey@latest"
        echo "  # Or download binary:"
        echo "  wget https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64"
        echo "  chmod +x hey_linux_amd64 && sudo mv hey_linux_amd64 /usr/local/bin/hey"
        exit 1
    fi
}

# Auto-detect Gateway IP
detect_gateway() {
    local gateway_ip=""

    # Try environment variable
    if [ -n "$GATEWAY_IP" ]; then
        gateway_ip="$GATEWAY_IP"
    # Try Windows host IP from WSL2
    elif [ -f /etc/resolv.conf ]; then
        gateway_ip=$(grep nameserver /etc/resolv.conf | head -1 | awk '{print $2}')
    fi

    if [ -n "$gateway_ip" ]; then
        TARGET_URL="http://${gateway_ip}:${GATEWAY_PORT}/"
        log_info "Auto-detected Gateway: $TARGET_URL"
    else
        log_error "Could not detect Gateway IP. Use -u option to specify URL."
        exit 1
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--url)
                TARGET_URL="$2"
                shift 2
                ;;
            -d|--duration)
                DURATION="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -l|--levels)
                LEVELS="$2"
                shift 2
                ;;
            -t|--threads)
                THREADS="$2"
                shift 2
                ;;
            -j|--json)
                JSON_ONLY=1
                shift
                ;;
            -h|--help)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                ;;
        esac
    done
}

# Calculate threads for wrk based on concurrency
calc_threads() {
    local concurrency=$1

    if [ -n "$THREADS" ]; then
        echo "$THREADS"
    elif [ "$concurrency" -le 10 ]; then
        echo 2
    elif [ "$concurrency" -le 50 ]; then
        echo 4
    else
        echo 8
    fi
}

# Run load test with wrk
run_wrk_test() {
    local concurrency=$1
    local duration=$2
    local url=$3
    local threads
    threads=$(calc_threads "$concurrency")

    local output
    output=$(wrk -t"$threads" -c"$concurrency" -d"${duration}s" --latency "$url" 2>&1)

    # Parse wrk output
    local rps avg_latency p50 p75 p90 p99 errors

    rps=$(echo "$output" | grep "Requests/sec" | awk '{print $2}')
    avg_latency=$(echo "$output" | grep "Latency" | head -1 | awk '{print $2}')

    # Parse latency distribution
    p50=$(echo "$output" | grep "50%" | awk '{print $2}')
    p75=$(echo "$output" | grep "75%" | awk '{print $2}')
    p90=$(echo "$output" | grep "90%" | awk '{print $2}')
    p99=$(echo "$output" | grep "99%" | awk '{print $2}')

    # Parse errors (using portable sed instead of grep -oP for compatibility)
    local socket_errors read_errors write_errors timeout_errors
    local socket_line
    socket_line=$(echo "$output" | grep "Socket errors" || echo "")
    socket_errors=$(echo "$socket_line" | sed -n 's/.*connect \([0-9]*\).*/\1/p' || echo "0")
    read_errors=$(echo "$socket_line" | sed -n 's/.*read \([0-9]*\).*/\1/p' || echo "0")
    write_errors=$(echo "$socket_line" | sed -n 's/.*write \([0-9]*\).*/\1/p' || echo "0")
    timeout_errors=$(echo "$socket_line" | sed -n 's/.*timeout \([0-9]*\).*/\1/p' || echo "0")
    # Ensure empty values default to 0
    [ -z "$socket_errors" ] && socket_errors=0
    [ -z "$read_errors" ] && read_errors=0
    [ -z "$write_errors" ] && write_errors=0
    [ -z "$timeout_errors" ] && timeout_errors=0

    local total_requests
    total_requests=$(echo "$output" | grep "requests in" | awk '{print $1}')

    local non_2xx
    non_2xx=$(echo "$output" | grep "Non-2xx" | awk '{print $4}' || echo "0")
    [ -z "$non_2xx" ] && non_2xx=0

    errors=$((socket_errors + read_errors + write_errors + timeout_errors + non_2xx))

    # Calculate error rate
    local error_rate=0
    if [ -n "$total_requests" ] && [ "$total_requests" -gt 0 ]; then
        error_rate=$(echo "scale=4; $errors / $total_requests * 100" | bc 2>/dev/null || echo "0")
    fi

    # Convert latency to ms for consistency
    local avg_ms p50_ms p99_ms
    avg_ms=$(convert_to_ms "$avg_latency")
    p50_ms=$(convert_to_ms "$p50")
    p99_ms=$(convert_to_ms "$p99")

    # Output JSON
    cat <<EOF
{
    "concurrency": $concurrency,
    "duration_seconds": $duration,
    "threads": $threads,
    "tool": "wrk",
    "rps": ${rps:-0},
    "latency": {
        "avg_ms": ${avg_ms:-0},
        "p50_ms": ${p50_ms:-0},
        "p99_ms": ${p99_ms:-0}
    },
    "total_requests": ${total_requests:-0},
    "errors": $errors,
    "error_rate_percent": ${error_rate:-0},
    "raw_output": $(echo "$output" | jq -Rs .)
}
EOF
}

# Run load test with hey
run_hey_test() {
    local concurrency=$1
    local duration=$2
    local url=$3

    local output
    output=$(hey -c "$concurrency" -z "${duration}s" "$url" 2>&1)

    # Parse hey output
    local rps avg_latency p50 p99 total_requests errors

    rps=$(echo "$output" | grep "Requests/sec" | awk '{print $2}')
    avg_latency=$(echo "$output" | grep "Average:" | head -1 | awk '{print $2}')

    # hey outputs latency in seconds
    p50=$(echo "$output" | grep "50%" | awk '{print $2}')
    p99=$(echo "$output" | grep "99%" | awk '{print $2}')

    total_requests=$(echo "$output" | grep "Total:" | head -1 | awk '{print $2}')

    # Count errors from status code distribution
    local status_200
    status_200=$(echo "$output" | grep -E "^\s*\[200\]" | awk '{print $2}' || echo "0")
    [ -z "$status_200" ] && status_200=0
    [ -z "$total_requests" ] && total_requests=0

    errors=$((total_requests - status_200))
    [ "$errors" -lt 0 ] && errors=0

    # Calculate error rate
    local error_rate=0
    if [ "$total_requests" -gt 0 ]; then
        error_rate=$(echo "scale=4; $errors / $total_requests * 100" | bc 2>/dev/null || echo "0")
    fi

    # Convert latency to ms
    local avg_ms p50_ms p99_ms
    avg_ms=$(convert_secs_to_ms "$avg_latency")
    p50_ms=$(convert_secs_to_ms "$p50")
    p99_ms=$(convert_secs_to_ms "$p99")

    # Output JSON
    cat <<EOF
{
    "concurrency": $concurrency,
    "duration_seconds": $duration,
    "tool": "hey",
    "rps": ${rps:-0},
    "latency": {
        "avg_ms": ${avg_ms:-0},
        "p50_ms": ${p50_ms:-0},
        "p99_ms": ${p99_ms:-0}
    },
    "total_requests": ${total_requests:-0},
    "errors": ${errors:-0},
    "error_rate_percent": ${error_rate:-0},
    "raw_output": $(echo "$output" | jq -Rs .)
}
EOF
}

# Convert wrk latency format to milliseconds
convert_to_ms() {
    local value=$1
    [ -z "$value" ] && echo "0" && return

    local num unit
    num=$(echo "$value" | grep -oE '[0-9.]+')
    unit=$(echo "$value" | grep -oE '[a-z]+')

    case $unit in
        us)
            echo "scale=3; $num / 1000" | bc 2>/dev/null || echo "0"
            ;;
        ms)
            echo "$num"
            ;;
        s)
            echo "scale=3; $num * 1000" | bc 2>/dev/null || echo "0"
            ;;
        *)
            echo "$num"
            ;;
    esac
}

# Convert seconds to milliseconds
convert_secs_to_ms() {
    local value=$1
    [ -z "$value" ] && echo "0" && return

    # Remove 's' suffix if present
    value="${value%s}"

    echo "scale=3; $value * 1000" | bc 2>/dev/null || echo "0"
}

# Run a single load test
run_test() {
    local concurrency=$1

    log_step "Testing with $concurrency concurrent connections (${DURATION}s)"

    local result
    if [ "$LOAD_TOOL" = "wrk" ]; then
        result=$(run_wrk_test "$concurrency" "$DURATION" "$TARGET_URL")
    else
        result=$(run_hey_test "$concurrency" "$DURATION" "$TARGET_URL")
    fi

    echo "$result"
}

# Display summary table
display_summary() {
    local results=$1

    echo ""
    echo "=============================================="
    echo "           LOAD TEST RESULTS SUMMARY"
    echo "=============================================="
    echo ""
    echo "Target: $TARGET_URL"
    echo "Tool:   $LOAD_TOOL"
    echo "Date:   $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    printf "%-12s | %-10s | %-12s | %-12s | %-10s\n" \
        "Concurrency" "RPS" "Avg Latency" "p99 Latency" "Error Rate"
    printf "%-12s-+-%-10s-+-%-12s-+-%-12s-+-%-10s\n" \
        "------------" "----------" "------------" "------------" "----------"

    echo "$results" | jq -r '.[] | "\(.concurrency) \(.rps) \(.latency.avg_ms) \(.latency.p99_ms) \(.error_rate_percent)"' | \
    while read -r conc rps avg p99 err; do
        printf "%-12s | %-10.2f | %-9.2f ms | %-9.2f ms | %-8.2f %%\n" \
            "$conc" "$rps" "$avg" "$p99" "$err"
    done

    echo ""
    echo "----------------------------------------------"

    # Find best RPS
    local best_rps best_conc
    best_rps=$(echo "$results" | jq 'max_by(.rps) | .rps')
    best_conc=$(echo "$results" | jq 'max_by(.rps) | .concurrency')

    echo ""
    echo "Best throughput: ${best_rps} RPS at ${best_conc} concurrent connections"

    # Recommend concurrency level (where error rate is acceptable)
    local recommended
    recommended=$(echo "$results" | jq '[.[] | select(.error_rate_percent < 1)] | max_by(.rps) | .concurrency // 0')

    if [ "$recommended" != "0" ] && [ "$recommended" != "null" ]; then
        echo "Recommended concurrency: ${recommended} (error rate < 1%)"
    else
        log_warn "No concurrency level achieved < 1% error rate"
    fi

    echo ""
    echo "=============================================="
}

# Validate port number
validate_port() {
    local port=$1
    local name=$2

    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "Invalid $name: $port (must be 1-65535)"
        exit 1
    fi
}

# Main function
main() {
    parse_args "$@"

    # Validate port
    validate_port "$GATEWAY_PORT" "GATEWAY_PORT"

    # Detect or validate target URL
    if [ -z "$TARGET_URL" ]; then
        detect_gateway
    fi

    # Check prerequisites
    detect_tool

    if ! command_exists jq; then
        log_error "jq is required for JSON processing. Install with: sudo apt install jq"
        exit 1
    fi

    if ! command_exists bc; then
        log_warn "bc not found - some calculations may not work. Install with: sudo apt install bc"
    fi

    # Check target is reachable
    if ! curl -s --connect-timeout 5 "$TARGET_URL" >/dev/null 2>&1; then
        log_error "Cannot reach target: $TARGET_URL"
        exit 1
    fi

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Run tests
    if [ "$JSON_ONLY" -eq 0 ]; then
        echo ""
        echo "=============================================="
        echo "       Flatnet Load Test - Phase 4 Stage 5"
        echo "=============================================="
        echo ""
        echo "Configuration:"
        echo "  Target URL:  $TARGET_URL"
        echo "  Duration:    ${DURATION}s per level"
        echo "  Levels:      $LEVELS"
        echo "  Tool:        $LOAD_TOOL"
        echo "  Output:      $OUTPUT_DIR"
        echo ""
    fi

    # Convert levels to array
    IFS=',' read -ra LEVEL_ARRAY <<< "$LEVELS"

    # Initialize results array
    local all_results="[]"
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')

    for level in "${LEVEL_ARRAY[@]}"; do
        # Check for interrupt
        if [ "$INTERRUPTED" -eq 1 ]; then
            log_warn "Skipping remaining tests due to interrupt"
            break
        fi

        local result
        result=$(run_test "$level")

        # Add to results array
        all_results=$(echo "$all_results" | jq --argjson new "$result" '. + [$new]')

        # Save individual result
        echo "$result" | jq . > "${OUTPUT_DIR}/load_test_c${level}_${timestamp}.json"

        # Brief pause between tests
        if [ "$JSON_ONLY" -eq 0 ]; then
            log_info "Completed. Waiting 5s before next test..."
        fi
        sleep 5
    done

    # Save combined results
    local combined_file="${OUTPUT_DIR}/load_test_combined_${timestamp}.json"
    cat <<EOF | jq . > "$combined_file"
{
    "metadata": {
        "timestamp": "$(date -Iseconds)",
        "target_url": "$TARGET_URL",
        "duration_per_level": $DURATION,
        "tool": "$LOAD_TOOL",
        "levels": "$LEVELS"
    },
    "results": $all_results
}
EOF

    if [ "$JSON_ONLY" -eq 1 ]; then
        cat "$combined_file"
    else
        display_summary "$all_results"
        log_info "Results saved to: $combined_file"
    fi
}

# Run main function
main "$@"
