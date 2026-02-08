#!/bin/bash
#==============================================================================
# Flatnet Rust Dependency Scanner
# Phase 4, Stage 3: Security
#
# Scans Rust dependencies for known vulnerabilities using cargo-audit.
# Generates reports and optionally fails the build on vulnerabilities.
#==============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORT_DIR="${PROJECT_ROOT}/reports/security"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Default settings
JSON_OUTPUT=false
DENY_WARNINGS=false
FIX_MODE=false
CARGO_DIRS=()

# Colors for output
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

#------------------------------------------------------------------------------
# Functions
#------------------------------------------------------------------------------

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [CARGO_DIR...]

Scan Rust dependencies for vulnerabilities using cargo-audit.

Options:
    -j, --json          Output JSON report
    -d, --deny          Deny warnings (exit with error on any finding)
    -f, --fix           Attempt to automatically fix vulnerabilities
    -o, --output DIR    Output directory for reports (default: ${REPORT_DIR})
    -h, --help          Show this help message

Examples:
    # Scan project in current directory
    $(basename "$0")

    # Scan specific directory with JSON output
    $(basename "$0") -j ./cni-plugin

    # Scan and attempt to fix
    $(basename "$0") --fix

    # Scan with strict mode (fail on any warning)
    $(basename "$0") --deny
EOF
    exit 0
}

check_cargo_audit() {
    if ! command -v cargo-audit &> /dev/null; then
        echo -e "${RED}Error: cargo-audit is not installed.${NC}"
        echo ""
        echo "Install cargo-audit:"
        echo "  cargo install cargo-audit"
        exit 1
    fi
}

find_cargo_projects() {
    # Find all directories containing Cargo.toml
    find "${PROJECT_ROOT}" -name "Cargo.toml" -type f 2>/dev/null | xargs -I{} dirname {} | sort -u
}

scan_cargo_dir() {
    local cargo_dir="$1"
    local dir_name
    dir_name=$(basename "${cargo_dir}")

    if [ ! -f "${cargo_dir}/Cargo.toml" ]; then
        echo -e "${RED}Error: No Cargo.toml found in: ${cargo_dir}${NC}"
        echo "Please specify a directory containing a Rust project."
        return 1
    fi

    if [ ! -f "${cargo_dir}/Cargo.lock" ]; then
        echo -e "${YELLOW}Warning: No Cargo.lock found in: ${cargo_dir}${NC}"
        echo "Running 'cargo generate-lockfile' to create one..."
        (cd "${cargo_dir}" && cargo generate-lockfile 2>/dev/null) || true
    fi

    echo -e "${YELLOW}Scanning: ${cargo_dir}${NC}"
    echo ""

    # Build cargo-audit command
    local audit_args=()

    if [ "${DENY_WARNINGS}" = true ]; then
        audit_args+=("--deny" "warnings")
    fi

    # Create report directory if needed
    local json_file=""
    if [ "${JSON_OUTPUT}" = true ]; then
        mkdir -p "${REPORT_DIR}"
        json_file="${REPORT_DIR}/cargo-audit_${dir_name}_${TIMESTAMP}.json"
        audit_args+=("--json")
    fi

    # Run audit
    local result=0
    local output

    cd "${cargo_dir}" || return 1

    if [ "${FIX_MODE}" = true ]; then
        echo "Running cargo audit fix..."
        cargo audit fix "${audit_args[@]}" 2>&1 || result=$?
    else
        if [ "${JSON_OUTPUT}" = true ]; then
            output=$(cargo audit "${audit_args[@]}" 2>&1) || result=$?
            echo "${output}" > "${json_file}"
            echo "JSON report: ${json_file}"

            # Also print human-readable output
            cargo audit 2>&1 || true
        else
            cargo audit "${audit_args[@]}" 2>&1 || result=$?
        fi
    fi

    cd - > /dev/null || true

    if [ "${result}" -eq 0 ]; then
        echo -e "${GREEN}No vulnerabilities found: ${cargo_dir}${NC}"
    else
        echo -e "${RED}Vulnerabilities found in: ${cargo_dir}${NC}"
    fi

    return "${result}"
}

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case $1 in
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        -d|--deny)
            DENY_WARNINGS=true
            shift
            ;;
        -f|--fix)
            FIX_MODE=true
            shift
            ;;
        -o|--output)
            REPORT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            CARGO_DIRS+=("$1")
            shift
            ;;
    esac
done

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

echo "========================================"
echo "Flatnet Rust Dependency Scanner"
echo "========================================"
echo ""

# Check cargo-audit is installed
check_cargo_audit

# Display cargo-audit version
echo "cargo-audit version: $(cargo audit --version 2>/dev/null || echo 'unknown')"
echo ""

# Determine directories to scan
if [ "${#CARGO_DIRS[@]}" -eq 0 ]; then
    # Auto-discover Cargo projects
    mapfile -t discovered < <(find_cargo_projects)
    if [ "${#discovered[@]}" -eq 0 ]; then
        echo -e "${YELLOW}No Cargo projects found in: ${PROJECT_ROOT}${NC}"
        echo ""
        echo "This is normal if no Rust code has been written yet (Phase 2+)."
        echo ""
        echo "To scan a specific directory containing Cargo.toml:"
        echo "  $(basename "$0") /path/to/rust/project"
        exit 0
    fi
    CARGO_DIRS=("${discovered[@]}")
fi

echo "Directories to scan: ${#CARGO_DIRS[@]}"
echo ""

# Track results
TOTAL=0
PASSED=0
FAILED=0

# Scan each directory
for cargo_dir in "${CARGO_DIRS[@]}"; do
    if [ -n "$cargo_dir" ]; then
        ((TOTAL++))
        echo "----------------------------------------"
        if scan_cargo_dir "$cargo_dir"; then
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
echo "Total projects scanned: ${TOTAL}"
echo -e "Passed: ${GREEN}${PASSED}${NC}"
echo -e "Failed: ${RED}${FAILED}${NC}"

if [ "${JSON_OUTPUT}" = true ]; then
    echo ""
    echo "Reports saved to: ${REPORT_DIR}"
fi

# Update advisory database
echo ""
echo "----------------------------------------"
echo "Updating RustSec Advisory Database..."
if cargo audit fetch 2>/dev/null; then
    echo "Database updated successfully."
else
    echo -e "${YELLOW}Warning: Could not update advisory database. Using cached version.${NC}"
fi

# Exit with error if vulnerabilities found
if [ "${FAILED}" -gt 0 ]; then
    exit 1
fi

exit 0
