#!/bin/bash
# Flatnet Monitoring Stack - Start Script
# Phase 4, Stage 1: Monitoring
#
# Starts the monitoring stack (Prometheus, Grafana, Alertmanager, Node Exporter)
# using Podman Compose.
#
# Usage:
#   ./scripts/monitoring/start.sh [--detach]
#
# Options:
#   --detach, -d    Run in background (default)
#   --foreground    Run in foreground with logs
#   -h, --help      Show this help message

set -e

VERSION="1.0.0"

show_help() {
    cat << 'EOF'
Flatnet Monitoring Stack - Start Script
Phase 4, Stage 1: Monitoring

Usage:
  ./scripts/monitoring/start.sh [OPTIONS]

Options:
  -d, --detach      Run in background (default)
  --foreground      Run in foreground with logs
  -h, --help        Show this help message
  --version         Show version information

Examples:
  ./scripts/monitoring/start.sh              # Start in background
  ./scripts/monitoring/start.sh --foreground # Start with logs visible

Services started:
  - Prometheus:    http://localhost:9090
  - Grafana:       http://localhost:3000
  - Alertmanager:  http://localhost:9093
  - Node Exporter: http://localhost:9100/metrics
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

# Default to detached mode
DETACH=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--detach)
            DETACH=true
            shift
            ;;
        --foreground)
            DETACH=false
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --version)
            echo "flatnet-monitoring-start v${VERSION}"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Usage: $0 [--detach|-d|--foreground|--help]"
            exit 1
            ;;
    esac
done

# Check if podman-compose is available
if ! command -v podman-compose &> /dev/null; then
    echo -e "${RED}Error: podman-compose is not installed${NC}"
    echo "Install it with: pip install podman-compose"
    exit 1
fi

# Check if monitoring directory exists
if [ ! -d "$MONITORING_DIR" ]; then
    echo -e "${RED}Error: Monitoring directory not found: $MONITORING_DIR${NC}"
    exit 1
fi

# Check if compose file exists
if [ ! -f "$MONITORING_DIR/podman-compose.yml" ]; then
    echo -e "${RED}Error: podman-compose.yml not found in $MONITORING_DIR${NC}"
    exit 1
fi

echo -e "${GREEN}Starting Flatnet Monitoring Stack...${NC}"
echo "Monitoring directory: $MONITORING_DIR"

# Check for custom Grafana password
if [ -n "$GRAFANA_ADMIN_PASSWORD" ]; then
    echo -e "${YELLOW}Using custom Grafana admin password from environment${NC}"
else
    echo -e "${YELLOW}Using default Grafana admin password (flatnet)${NC}"
    echo -e "${YELLOW}Set GRAFANA_ADMIN_PASSWORD env var for production use${NC}"
fi
echo ""

cd "$MONITORING_DIR"

if [ "$DETACH" = true ]; then
    echo -e "${YELLOW}Starting in detached mode...${NC}"
    podman-compose up -d

    echo ""
    echo -e "${GREEN}Monitoring stack started successfully!${NC}"
    echo ""
    echo "Services:"
    echo "  - Prometheus:    http://localhost:9090"
    if [ -n "$GRAFANA_ADMIN_PASSWORD" ]; then
        echo "  - Grafana:       http://localhost:3000 (admin/<custom>)"
    else
        echo "  - Grafana:       http://localhost:3000 (admin/flatnet)"
    fi
    echo "  - Alertmanager:  http://localhost:9093"
    echo "  - Node Exporter: http://localhost:9100/metrics"
    echo ""
    echo "To view logs:    podman-compose -f $MONITORING_DIR/podman-compose.yml logs -f"
    echo "To stop:         $SCRIPT_DIR/stop.sh"
    echo "To check status: $SCRIPT_DIR/status.sh"
else
    echo -e "${YELLOW}Starting in foreground mode (Ctrl+C to stop)...${NC}"
    podman-compose up
fi
