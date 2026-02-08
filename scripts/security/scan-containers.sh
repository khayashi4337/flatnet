#!/bin/bash
#==============================================================================
# Flatnet Container Vulnerability Scanner
# Phase 4, Stage 3: Security
#
# Scans container images for vulnerabilities using Trivy.
# Generates reports in JSON and human-readable formats.
#==============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORT_DIR="${PROJECT_ROOT}/reports/security"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Default settings
SEVERITY="CRITICAL,HIGH"
OUTPUT_FORMAT="table"
JSON_OUTPUT=false
SCAN_ALL=false
EXIT_ON_VULN=false

# Colors for output
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Images to scan (add your images here)
DEFAULT_IMAGES=(
    "codeberg.org/forgejo/forgejo:9"
)

#------------------------------------------------------------------------------
# Functions
#------------------------------------------------------------------------------

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [IMAGE...]

Scan container images for vulnerabilities using Trivy.

Options:
    -a, --all           Scan all images (including running containers)
    -s, --severity      Severity levels to report (default: CRITICAL,HIGH)
                        Options: UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL
    -j, --json          Output JSON report
    -o, --output DIR    Output directory for reports (default: ${REPORT_DIR})
    -e, --exit-code     Exit with code 1 if vulnerabilities found
    -h, --help          Show this help message

Examples:
    # Scan default images
    $(basename "$0")

    # Scan specific image
    $(basename "$0") myimage:latest

    # Scan all severity levels with JSON output
    $(basename "$0") -s UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL -j

    # Scan all running containers
    $(basename "$0") --all
EOF
    exit 0
}

check_trivy() {
    if ! command -v trivy &> /dev/null; then
        echo -e "${RED}Error: Trivy is not installed.${NC}"
        echo ""
        echo "Install Trivy:"
        echo "  # Ubuntu/Debian"
        echo "  sudo apt-get install wget apt-transport-https gnupg lsb-release"
        echo "  wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -"
        echo "  echo deb https://aquasecurity.github.io/trivy-repo/deb \$(lsb_release -sc) main | sudo tee -a /etc/apt/sources.list.d/trivy.list"
        echo "  sudo apt-get update && sudo apt-get install trivy"
        echo ""
        echo "  # Or via snap"
        echo "  sudo snap install trivy"
        exit 1
    fi
}

get_running_images() {
    podman ps --format "{{.Image}}" 2>/dev/null | sort -u
}

scan_image() {
    local image="$1"
    local report_name
    report_name=$(echo "${image}" | tr '/:' '_')

    echo -e "${YELLOW}Scanning: ${image}${NC}"
    echo "Severity filter: ${SEVERITY}"
    echo ""

    # Create report directory if needed
    if [ "$JSON_OUTPUT" = true ]; then
        mkdir -p "${REPORT_DIR}"
    fi

    # Build trivy command
    local trivy_args=(
        "image"
        "--severity" "${SEVERITY}"
    )

    if [ "${JSON_OUTPUT}" = true ]; then
        local json_file="${REPORT_DIR}/trivy_${report_name}_${TIMESTAMP}.json"
        trivy_args+=("--format" "json" "--output" "${json_file}")
        echo "JSON report: ${json_file}"
    fi

    # Run scan
    local exit_code=0
    if trivy "${trivy_args[@]}" "${image}"; then
        echo -e "${GREEN}Scan completed: ${image}${NC}"
        return 0
    else
        exit_code=$?
        if [ "${exit_code}" -eq 1 ] && [ "${EXIT_ON_VULN}" = true ]; then
            echo -e "${RED}Vulnerabilities found in: ${image}${NC}"
            return 1
        fi
        return "${exit_code}"
    fi
}

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------

IMAGES=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--all)
            SCAN_ALL=true
            shift
            ;;
        -s|--severity)
            SEVERITY="$2"
            shift 2
            ;;
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        -o|--output)
            REPORT_DIR="$2"
            shift 2
            ;;
        -e|--exit-code)
            EXIT_ON_VULN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            IMAGES+=("$1")
            shift
            ;;
    esac
done

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

echo "========================================"
echo "Flatnet Container Vulnerability Scanner"
echo "========================================"
echo ""

# Check Trivy is installed
check_trivy

# Determine images to scan
if [ "${SCAN_ALL}" = true ]; then
    mapfile -t running_images < <(get_running_images)
    IMAGES+=("${running_images[@]}")
fi

if [ "${#IMAGES[@]}" -eq 0 ]; then
    IMAGES=("${DEFAULT_IMAGES[@]}")
fi

# Remove duplicates using mapfile for reliable handling
mapfile -t IMAGES < <(printf '%s\n' "${IMAGES[@]}" | sort -u)

echo "Images to scan: ${#IMAGES[@]}"
echo ""

# Track results
TOTAL=0
PASSED=0
FAILED=0

# Scan each image
for image in "${IMAGES[@]}"; do
    if [ -n "$image" ]; then
        ((TOTAL++))
        echo "----------------------------------------"
        if scan_image "$image"; then
            ((PASSED++))
        else
            ((FAILED++))
        fi
        echo ""
    fi
done

# Summary
echo "========================================"
echo "Scan Summary"
echo "========================================"
echo "Total images scanned: ${TOTAL}"
echo -e "Passed: ${GREEN}${PASSED}${NC}"
echo -e "Failed: ${RED}${FAILED}${NC}"

if [ "${JSON_OUTPUT}" = true ]; then
    echo ""
    echo "Reports saved to: ${REPORT_DIR}"
fi

# Exit with error if vulnerabilities found and exit-on-vuln is set
if [ "${EXIT_ON_VULN}" = true ] && [ "${FAILED}" -gt 0 ]; then
    exit 1
fi

exit 0
