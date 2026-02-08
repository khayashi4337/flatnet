#!/bin/bash
# Flatnet Phase 4 Health Check Script
# Stage 5: Validation
#
# This script verifies the health of all Flatnet system components.
# It checks Gateway, Prometheus, Grafana, Alertmanager, Loki, disk space,
# and memory usage.
#
# Exit codes:
#   0 - All checks passed
#   1 - One or more checks failed
#   2 - One or more checks warning
#
# Usage:
#   ./health-check.sh [OPTIONS]
#
# Options:
#   -q, --quiet         Only output on failure
#   -j, --json          Output results as JSON
#   -v, --verbose       Show detailed check information
#   --no-color          Disable colored output
#   -h, --help          Show this help message
#
# Environment Variables:
#   GATEWAY_IP          Gateway IP address (auto-detected if not set)
#   GATEWAY_PORT        Gateway port (default: 80)
#   PROMETHEUS_PORT     Prometheus port (default: 9090)
#   GRAFANA_PORT        Grafana port (default: 3000)
#   ALERTMANAGER_PORT   Alertmanager port (default: 9093)
#   LOKI_PORT           Loki port (default: 3100)
#   DISK_WARN_PERCENT   Disk usage warning threshold (default: 80)
#   DISK_CRIT_PERCENT   Disk usage critical threshold (default: 90)
#   MEM_WARN_PERCENT    Memory usage warning threshold (default: 85)

set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration
GATEWAY_PORT="${GATEWAY_PORT:-80}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-9090}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
ALERTMANAGER_PORT="${ALERTMANAGER_PORT:-9093}"
LOKI_PORT="${LOKI_PORT:-3100}"
DISK_WARN_PERCENT="${DISK_WARN_PERCENT:-80}"
DISK_CRIT_PERCENT="${DISK_CRIT_PERCENT:-90}"
MEM_WARN_PERCENT="${MEM_WARN_PERCENT:-85}"

# Options
QUIET=0
JSON_OUTPUT=0
VERBOSE=0
NO_COLOR=0

# Colors
setup_colors() {
    if [ "$NO_COLOR" -eq 0 ] && [ -t 1 ]; then
        RED='\033[0;31m'
        GREEN='\033[0;32m'
        YELLOW='\033[1;33m'
        BLUE='\033[0;34m'
        CYAN='\033[0;36m'
        NC='\033[0m'
    else
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        CYAN=''
        NC=''
    fi
}

# Check counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNING=0
CHECKS_TOTAL=0

# Results array for JSON output
RESULTS=()

# Helper functions
log_info() {
    if [ "$QUIET" -eq 0 ] && [ "$JSON_OUTPUT" -eq 0 ]; then
        echo -e "${GREEN}[INFO]${NC} $1"
    fi
}

log_warn() {
    if [ "$JSON_OUTPUT" -eq 0 ]; then
        echo -e "${YELLOW}[WARN]${NC} $1"
    fi
}

log_error() {
    if [ "$JSON_OUTPUT" -eq 0 ]; then
        echo -e "${RED}[ERROR]${NC} $1" >&2
    fi
}

log_debug() {
    if [ "$VERBOSE" -eq 1 ] && [ "$JSON_OUTPUT" -eq 0 ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

show_help() {
    # Extract help text from script header (lines 2-35 to capture all documentation)
    sed -n '2,35p' "$0" | grep -E '^#' | sed 's/^# //' | sed 's/^#//'
    exit 0
}

# Escape string for JSON
json_escape() {
    local str="$1"
    # Escape backslashes, double quotes, and control characters
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

# Record check result
record_result() {
    local name=$1
    local status=$2
    local message=$3
    local details=${4:-""}

    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))

    # Escape message for JSON
    local escaped_message
    escaped_message=$(json_escape "$message")

    case $status in
        ok|pass)
            CHECKS_PASSED=$((CHECKS_PASSED + 1))
            if [ "$QUIET" -eq 0 ] && [ "$JSON_OUTPUT" -eq 0 ]; then
                echo -e "  ${GREEN}[OK]${NC}   $name"
                [ -n "$details" ] && [ "$VERBOSE" -eq 1 ] && echo -e "         ${BLUE}$details${NC}"
            fi
            RESULTS+=("{\"name\":\"$name\",\"status\":\"ok\",\"message\":\"$escaped_message\"}")
            ;;
        warn|warning)
            CHECKS_WARNING=$((CHECKS_WARNING + 1))
            if [ "$JSON_OUTPUT" -eq 0 ]; then
                echo -e "  ${YELLOW}[WARN]${NC} $name: $message"
                [ -n "$details" ] && echo -e "         ${YELLOW}$details${NC}"
            fi
            RESULTS+=("{\"name\":\"$name\",\"status\":\"warning\",\"message\":\"$escaped_message\"}")
            ;;
        fail|error)
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
            if [ "$JSON_OUTPUT" -eq 0 ]; then
                echo -e "  ${RED}[FAIL]${NC} $name: $message"
                [ -n "$details" ] && echo -e "         ${RED}$details${NC}"
            fi
            RESULTS+=("{\"name\":\"$name\",\"status\":\"fail\",\"message\":\"$escaped_message\"}")
            ;;
    esac
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -q|--quiet)
                QUIET=1
                shift
                ;;
            -j|--json)
                JSON_OUTPUT=1
                shift
                ;;
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            --no-color)
                NO_COLOR=1
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

# Auto-detect Gateway IP
detect_gateway_ip() {
    if [ -n "$GATEWAY_IP" ]; then
        echo "$GATEWAY_IP"
        return
    fi

    # Try Windows host IP from WSL2
    if [ -f /etc/resolv.conf ]; then
        local ip
        ip=$(grep nameserver /etc/resolv.conf | head -1 | awk '{print $2}')
        if [ -n "$ip" ]; then
            echo "$ip"
            return
        fi
    fi

    # Default to localhost
    echo "localhost"
}

# Check HTTP endpoint
check_http() {
    local name=$1
    local url=$2
    local expected_status=${3:-200}
    local timeout=${4:-5}

    log_debug "Checking $name at $url"

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$timeout" --max-time "$((timeout * 2))" "$url" 2>/dev/null || echo "000")

    if [ "$status" = "$expected_status" ]; then
        record_result "$name" "ok" "HTTP $status" "URL: $url"
        return 0
    elif [ "$status" = "000" ]; then
        record_result "$name" "fail" "Connection failed" "URL: $url"
        return 1
    else
        record_result "$name" "fail" "HTTP $status (expected $expected_status)" "URL: $url"
        return 1
    fi
}

# Check disk space
check_disk() {
    local path=${1:-/}

    log_debug "Checking disk space for $path"

    local usage
    usage=$(df "$path" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')

    if [ -z "$usage" ]; then
        record_result "Disk ($path)" "fail" "Could not determine disk usage"
        return 1
    fi

    if [ "$usage" -ge "$DISK_CRIT_PERCENT" ]; then
        record_result "Disk ($path)" "fail" "${usage}% used (critical threshold: ${DISK_CRIT_PERCENT}%)"
        return 1
    elif [ "$usage" -ge "$DISK_WARN_PERCENT" ]; then
        record_result "Disk ($path)" "warn" "${usage}% used (warning threshold: ${DISK_WARN_PERCENT}%)"
        return 0
    else
        record_result "Disk ($path)" "ok" "${usage}% used"
        return 0
    fi
}

# Check memory usage
check_memory() {
    log_debug "Checking memory usage"

    local mem_info
    mem_info=$(free 2>/dev/null | grep Mem)

    if [ -z "$mem_info" ]; then
        record_result "Memory" "fail" "Could not determine memory usage"
        return 1
    fi

    local total used
    total=$(echo "$mem_info" | awk '{print $2}')
    used=$(echo "$mem_info" | awk '{print $3}')

    if [ "$total" -eq 0 ]; then
        record_result "Memory" "fail" "Invalid memory information"
        return 1
    fi

    local usage_percent
    usage_percent=$((used * 100 / total))

    local used_gb total_gb
    used_gb=$(echo "scale=1; $used / 1024 / 1024" | bc 2>/dev/null || echo "?")
    total_gb=$(echo "scale=1; $total / 1024 / 1024" | bc 2>/dev/null || echo "?")

    if [ "$usage_percent" -ge "$MEM_WARN_PERCENT" ]; then
        record_result "Memory" "warn" "${usage_percent}% used (${used_gb}GB / ${total_gb}GB)"
        return 0
    else
        record_result "Memory" "ok" "${usage_percent}% used (${used_gb}GB / ${total_gb}GB)"
        return 0
    fi
}

# Check if Podman containers are running
check_containers() {
    log_debug "Checking Podman containers"

    if ! command -v podman >/dev/null 2>&1; then
        record_result "Containers" "warn" "Podman not found"
        return 0
    fi

    local running
    running=$(podman ps --format "{{.Names}}" 2>/dev/null | wc -l)

    if [ "$running" -eq 0 ]; then
        record_result "Containers" "warn" "No running containers"
        return 0
    else
        local names
        names=$(podman ps --format "{{.Names}}" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
        record_result "Containers" "ok" "$running running" "$names"
        return 0
    fi
}

# Main health check function
run_health_checks() {
    local gateway_ip
    gateway_ip=$(detect_gateway_ip)

    if [ "$JSON_OUTPUT" -eq 0 ] && [ "$QUIET" -eq 0 ]; then
        echo ""
        echo "=============================================="
        echo "     Flatnet Health Check - Phase 4 Stage 5"
        echo "=============================================="
        echo ""
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Gateway IP: $gateway_ip"
        echo ""
        echo "Checking services..."
        echo ""
    fi

    # Check Gateway
    check_http "Gateway" "http://${gateway_ip}:${GATEWAY_PORT}/" 200 5 || true

    # Check Prometheus
    check_http "Prometheus" "http://localhost:${PROMETHEUS_PORT}/-/ready" 200 3 || true

    # Check Grafana
    check_http "Grafana" "http://localhost:${GRAFANA_PORT}/api/health" 200 3 || true

    # Check Alertmanager
    check_http "Alertmanager" "http://localhost:${ALERTMANAGER_PORT}/-/ready" 200 3 || true

    # Check Loki
    check_http "Loki" "http://localhost:${LOKI_PORT}/ready" 200 3 || true

    if [ "$JSON_OUTPUT" -eq 0 ] && [ "$QUIET" -eq 0 ]; then
        echo ""
        echo "Checking resources..."
        echo ""
    fi

    # Check disk space
    check_disk "/" || true

    # Check memory
    check_memory || true

    # Check containers
    check_containers || true
}

# Print summary
print_summary() {
    if [ "$JSON_OUTPUT" -eq 1 ]; then
        # Output JSON
        local results_json
        results_json=$(printf '%s\n' "${RESULTS[@]}" | jq -s '.')

        cat <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "summary": {
        "total": $CHECKS_TOTAL,
        "passed": $CHECKS_PASSED,
        "failed": $CHECKS_FAILED,
        "warning": $CHECKS_WARNING
    },
    "overall_status": "$(get_overall_status)",
    "checks": $results_json
}
EOF
        return
    fi

    if [ "$QUIET" -eq 1 ] && [ "$CHECKS_FAILED" -eq 0 ] && [ "$CHECKS_WARNING" -eq 0 ]; then
        return
    fi

    echo ""
    echo "=============================================="
    echo "                  SUMMARY"
    echo "=============================================="
    echo -e "  ${GREEN}Passed:${NC}  $CHECKS_PASSED"
    echo -e "  ${YELLOW}Warning:${NC} $CHECKS_WARNING"
    echo -e "  ${RED}Failed:${NC}  $CHECKS_FAILED"
    echo "----------------------------------------------"
    echo "  Total:   $CHECKS_TOTAL"
    echo "=============================================="

    if [ "$CHECKS_FAILED" -gt 0 ]; then
        echo -e "\n${RED}Overall Status: UNHEALTHY${NC}"
    elif [ "$CHECKS_WARNING" -gt 0 ]; then
        echo -e "\n${YELLOW}Overall Status: DEGRADED${NC}"
    else
        echo -e "\n${GREEN}Overall Status: HEALTHY${NC}"
    fi
    echo ""
}

# Get overall status string
get_overall_status() {
    if [ "$CHECKS_FAILED" -gt 0 ]; then
        echo "unhealthy"
    elif [ "$CHECKS_WARNING" -gt 0 ]; then
        echo "degraded"
    else
        echo "healthy"
    fi
}

# Determine exit code
get_exit_code() {
    if [ "$CHECKS_FAILED" -gt 0 ]; then
        return 1
    elif [ "$CHECKS_WARNING" -gt 0 ]; then
        return 2
    else
        return 0
    fi
}

# Validate port number
validate_port() {
    local port=$1
    local name=$2

    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "Invalid $name: $port (must be 1-65535)"
        return 1
    fi
    return 0
}

# Validate threshold values
validate_thresholds() {
    local valid=1

    # Validate ports
    validate_port "$GATEWAY_PORT" "GATEWAY_PORT" || valid=0
    validate_port "$PROMETHEUS_PORT" "PROMETHEUS_PORT" || valid=0
    validate_port "$GRAFANA_PORT" "GRAFANA_PORT" || valid=0
    validate_port "$ALERTMANAGER_PORT" "ALERTMANAGER_PORT" || valid=0
    validate_port "$LOKI_PORT" "LOKI_PORT" || valid=0

    # Validate disk thresholds
    if ! [[ "$DISK_WARN_PERCENT" =~ ^[0-9]+$ ]] || [ "$DISK_WARN_PERCENT" -lt 0 ] || [ "$DISK_WARN_PERCENT" -gt 100 ]; then
        log_error "DISK_WARN_PERCENT must be 0-100 (got: $DISK_WARN_PERCENT)"
        valid=0
    fi

    if ! [[ "$DISK_CRIT_PERCENT" =~ ^[0-9]+$ ]] || [ "$DISK_CRIT_PERCENT" -lt 0 ] || [ "$DISK_CRIT_PERCENT" -gt 100 ]; then
        log_error "DISK_CRIT_PERCENT must be 0-100 (got: $DISK_CRIT_PERCENT)"
        valid=0
    fi

    if [ "$valid" -eq 1 ] && [ "$DISK_WARN_PERCENT" -ge "$DISK_CRIT_PERCENT" ]; then
        log_error "DISK_WARN_PERCENT ($DISK_WARN_PERCENT) must be less than DISK_CRIT_PERCENT ($DISK_CRIT_PERCENT)"
        valid=0
    fi

    # Validate memory threshold
    if ! [[ "$MEM_WARN_PERCENT" =~ ^[0-9]+$ ]] || [ "$MEM_WARN_PERCENT" -lt 0 ] || [ "$MEM_WARN_PERCENT" -gt 100 ]; then
        log_error "MEM_WARN_PERCENT must be 0-100 (got: $MEM_WARN_PERCENT)"
        valid=0
    fi

    if [ "$valid" -eq 0 ]; then
        exit 1
    fi
}

# Main function
main() {
    parse_args "$@"
    setup_colors
    validate_thresholds

    run_health_checks
    print_summary

    get_exit_code
}

# Run main function
main "$@"
