#!/bin/bash
# Flatnet Monitoring Stack - Status Script
# Phase 4, Stage 1: Monitoring
#
# Shows the status of the monitoring stack.
#
# Usage:
#   ./scripts/monitoring/status.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MONITORING_DIR="$PROJECT_ROOT/monitoring"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

echo -e "${CYAN}=== Flatnet Monitoring Stack Status ===${NC}"
echo ""

cd "$MONITORING_DIR"

# Show container status
echo -e "${YELLOW}Container Status:${NC}"
podman-compose ps
echo ""

# Check each service
check_service() {
    local name=$1
    local url=$2
    local timeout=2

    if curl -s --connect-timeout $timeout "$url" > /dev/null 2>&1; then
        echo -e "  $name: ${GREEN}UP${NC} ($url)"
        return 0
    else
        echo -e "  $name: ${RED}DOWN${NC} ($url)"
        return 1
    fi
}

echo -e "${YELLOW}Service Health:${NC}"
check_service "Prometheus" "http://localhost:9090/-/ready" || true
check_service "Grafana" "http://localhost:3000/api/health" || true
check_service "Alertmanager" "http://localhost:9093/-/ready" || true
check_service "Node Exporter" "http://localhost:9100/metrics" || true
check_service "Gateway Metrics" "http://localhost:9145/metrics" || true
echo ""

# Check Prometheus targets
echo -e "${YELLOW}Prometheus Targets:${NC}"
if curl -s "http://localhost:9090/api/v1/targets" > /dev/null 2>&1; then
    targets=$(curl -s "http://localhost:9090/api/v1/targets" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for target in data.get('data', {}).get('activeTargets', []):
        job = target.get('labels', {}).get('job', 'unknown')
        health = target.get('health', 'unknown')
        instance = target.get('labels', {}).get('instance', 'unknown')
        if health == 'up':
            print(f'  {job} ({instance}): UP')
        else:
            print(f'  {job} ({instance}): DOWN - {target.get(\"lastError\", \"unknown error\")}')
except Exception as e:
    print(f'  Error parsing targets: {e}')
" 2>/dev/null || echo "  (Unable to parse targets)")
    echo "$targets"
else
    echo -e "  ${RED}Unable to fetch targets (Prometheus may be down)${NC}"
fi
echo ""

# Check active alerts
echo -e "${YELLOW}Active Alerts:${NC}"
if curl -s "http://localhost:9090/api/v1/alerts" > /dev/null 2>&1; then
    alerts=$(curl -s "http://localhost:9090/api/v1/alerts" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    alerts = data.get('data', {}).get('alerts', [])
    if not alerts:
        print('  No active alerts')
    else:
        for alert in alerts:
            name = alert.get('labels', {}).get('alertname', 'unknown')
            state = alert.get('state', 'unknown')
            severity = alert.get('labels', {}).get('severity', 'unknown')
            print(f'  {name} [{severity}]: {state}')
except Exception as e:
    print(f'  Error parsing alerts: {e}')
" 2>/dev/null || echo "  (Unable to parse alerts)")
    echo "$alerts"
else
    echo -e "  ${RED}Unable to fetch alerts (Prometheus may be down)${NC}"
fi
echo ""

# Show resource usage
echo -e "${YELLOW}Resource Usage:${NC}"
if podman ps --filter "name=flatnet" --format "{{.Names}}" 2>/dev/null | grep -q flatnet; then
    podman stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | grep -E "(flatnet|NAME)" || echo "  Unable to get resource stats"
else
    echo "  No flatnet containers running"
fi
echo ""

echo -e "${CYAN}=== End of Status ===${NC}"
