#!/bin/bash
# Flatnet Monitoring Stack - Stop Script
# Phase 4, Stage 1: Monitoring
#
# Stops the monitoring stack.
#
# Usage:
#   ./scripts/monitoring/stop.sh [--volumes]
#
# Options:
#   --volumes, -v   Also remove volumes (data will be lost)
#   -h, --help      Show this help message

set -e

VERSION="1.0.0"

show_help() {
    cat << 'EOF'
Flatnet Monitoring Stack - Stop Script
Phase 4, Stage 1: Monitoring

Usage:
  ./scripts/monitoring/stop.sh [OPTIONS]

Options:
  -v, --volumes     Also remove volumes (data will be lost)
  -h, --help        Show this help message
  --version         Show version information

Examples:
  ./scripts/monitoring/stop.sh            # Stop, keep data
  ./scripts/monitoring/stop.sh --volumes  # Stop and remove all data
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MONITORING_DIR="$PROJECT_ROOT/monitoring"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default to keeping volumes
REMOVE_VOLUMES=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--volumes)
            REMOVE_VOLUMES=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --version)
            echo "flatnet-monitoring-stop v${VERSION}"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Usage: $0 [--volumes|-v|--help]"
            exit 1
            ;;
    esac
done

# Check if podman-compose is available
if ! command -v podman-compose &> /dev/null; then
    echo -e "${RED}Error: podman-compose is not installed${NC}"
    exit 1
fi

# Check if monitoring directory exists
if [ ! -d "$MONITORING_DIR" ]; then
    echo -e "${RED}Error: Monitoring directory not found: $MONITORING_DIR${NC}"
    exit 1
fi

echo -e "${YELLOW}Stopping Flatnet Monitoring Stack...${NC}"

cd "$MONITORING_DIR"

if [ "$REMOVE_VOLUMES" = true ]; then
    echo -e "${RED}WARNING: Removing volumes - all monitoring data will be lost!${NC}"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        podman-compose down -v
        echo -e "${GREEN}Monitoring stack stopped and volumes removed.${NC}"
    else
        echo "Aborted."
        exit 0
    fi
else
    podman-compose down
    echo -e "${GREEN}Monitoring stack stopped. Data volumes preserved.${NC}"
fi

echo ""
echo "To start again: $SCRIPT_DIR/start.sh"
