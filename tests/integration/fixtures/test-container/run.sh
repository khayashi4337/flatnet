#!/bin/bash
# Flatnet Test Container Runner
#
# This script builds and runs the test container.
#
# Usage:
#   ./run.sh [OPTIONS]
#
# Options:
#   build     - Build the container image only
#   run       - Run the container (builds if needed)
#   stop      - Stop and remove the container
#   logs      - Show container logs
#   status    - Show container status
#   test      - Run a quick connectivity test
#   clean     - Remove container and image

set -e

# Script directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
IMAGE_NAME="flatnet-test"
IMAGE_TAG="latest"
CONTAINER_NAME="flatnet-test-server"
NETWORK_NAME="flatnet"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Build the container image
do_build() {
    log_info "Building ${IMAGE_NAME}:${IMAGE_TAG}..."
    cd "$SCRIPT_DIR"

    if sudo podman build -t "${IMAGE_NAME}:${IMAGE_TAG}" -f Containerfile .; then
        log_info "Build successful"
        return 0
    else
        log_error "Build failed"
        return 1
    fi
}

# Check if image exists
image_exists() {
    sudo podman image exists "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null
}

# Check if container exists
container_exists() {
    sudo podman container exists "$CONTAINER_NAME" 2>/dev/null
}

# Check if container is running
container_running() {
    if container_exists; then
        state=$(sudo podman inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)
        [ "$state" = "true" ]
    else
        return 1
    fi
}

# Run the container
do_run() {
    # Build if image doesn't exist
    if ! image_exists; then
        log_info "Image not found, building..."
        do_build
    fi

    # Stop existing container if running
    if container_exists; then
        log_warn "Container $CONTAINER_NAME already exists, stopping..."
        do_stop
    fi

    # Check if network exists
    if ! sudo podman network exists "$NETWORK_NAME" 2>/dev/null; then
        log_warn "Network $NETWORK_NAME does not exist"
        log_info "Creating network (this should use the Flatnet CNI plugin)..."
        # Note: This may need to be adjusted based on your Flatnet network configuration
        sudo podman network create "$NETWORK_NAME" 2>/dev/null || true
    fi

    log_info "Starting container $CONTAINER_NAME..."
    if sudo podman run -d \
        --name "$CONTAINER_NAME" \
        --network "$NETWORK_NAME" \
        --restart unless-stopped \
        "${IMAGE_NAME}:${IMAGE_TAG}"; then

        # Wait a moment for container to start
        sleep 2

        # Get container IP
        container_ip=$(sudo podman inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME" 2>/dev/null)

        log_info "Container started successfully"
        log_info "Container IP: ${container_ip:-unknown}"
        log_info ""
        log_info "Test endpoints:"
        log_info "  curl http://${container_ip:-<IP>}/"
        log_info "  curl http://${container_ip:-<IP>}/health"
        log_info ""
        log_info "For iperf3 throughput test:"
        log_info "  iperf3 -c ${container_ip:-<IP>}"
        return 0
    else
        log_error "Failed to start container"
        return 1
    fi
}

# Stop the container
do_stop() {
    if container_exists; then
        log_info "Stopping container $CONTAINER_NAME..."
        sudo podman stop "$CONTAINER_NAME" 2>/dev/null || true
        sudo podman rm "$CONTAINER_NAME" 2>/dev/null || true
        log_info "Container stopped and removed"
    else
        log_warn "Container $CONTAINER_NAME does not exist"
    fi
}

# Show container logs
do_logs() {
    if container_exists; then
        sudo podman logs "$CONTAINER_NAME"
    else
        log_error "Container $CONTAINER_NAME does not exist"
        return 1
    fi
}

# Show container status
do_status() {
    echo ""
    echo "=== Container Status ==="
    echo ""

    if container_exists; then
        echo "Container: $CONTAINER_NAME"

        state=$(sudo podman inspect --format '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)
        echo "State: $state"

        if container_running; then
            container_ip=$(sudo podman inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME" 2>/dev/null)
            echo "IP Address: ${container_ip:-unknown}"

            # Check port bindings
            ports=$(sudo podman inspect --format '{{range $k, $v := .NetworkSettings.Ports}}{{$k}}={{$v}} {{end}}' "$CONTAINER_NAME" 2>/dev/null)
            echo "Ports: ${ports:-none}"

            # Check health
            health=$(sudo podman inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null)
            echo "Health: ${health:-not configured}"

            # Quick connectivity test
            if [ -n "$container_ip" ]; then
                if curl -s --connect-timeout 2 "http://${container_ip}/health" | grep -q "OK"; then
                    echo -e "HTTP Status: ${GREEN}OK${NC}"
                else
                    echo -e "HTTP Status: ${RED}FAILED${NC}"
                fi
            fi
        fi
    else
        echo -e "Container: ${RED}Not found${NC}"
    fi

    echo ""
    echo "=== Image Status ==="
    echo ""

    if image_exists; then
        sudo podman images "${IMAGE_NAME}:${IMAGE_TAG}"
    else
        echo -e "Image: ${RED}Not found${NC}"
    fi

    echo ""
}

# Run connectivity test
do_test() {
    if ! container_running; then
        log_error "Container is not running"
        log_info "Run './run.sh run' to start the container"
        return 1
    fi

    container_ip=$(sudo podman inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER_NAME" 2>/dev/null)

    if [ -z "$container_ip" ]; then
        log_error "Could not get container IP"
        return 1
    fi

    echo ""
    echo "=== Connectivity Test ==="
    echo ""
    echo "Container IP: $container_ip"
    echo ""

    # Test health endpoint
    echo "1. Health endpoint:"
    if curl -s --connect-timeout 5 "http://${container_ip}/health"; then
        echo ""
        echo -e "   ${GREEN}PASS${NC}"
    else
        echo -e "   ${RED}FAIL${NC}"
    fi

    echo ""

    # Test main page
    echo "2. Main page:"
    if curl -s --connect-timeout 5 "http://${container_ip}/" | head -1; then
        echo "   ..."
        echo -e "   ${GREEN}PASS${NC}"
    else
        echo -e "   ${RED}FAIL${NC}"
    fi

    echo ""

    # Ping test
    echo "3. Ping test:"
    if ping -c 2 "$container_ip" 2>/dev/null; then
        echo -e "   ${GREEN}PASS${NC}"
    else
        echo -e "   ${YELLOW}SKIP (ICMP may be blocked)${NC}"
    fi

    echo ""
}

# Clean up everything
do_clean() {
    log_info "Cleaning up..."

    # Stop and remove container
    if container_exists; then
        log_info "Removing container..."
        sudo podman rm -f "$CONTAINER_NAME" 2>/dev/null || true
    fi

    # Remove image
    if image_exists; then
        log_info "Removing image..."
        sudo podman rmi "${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || true
    fi

    log_info "Cleanup complete"
}

# Show usage
show_usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  build   - Build the container image"
    echo "  run     - Run the container (builds if needed)"
    echo "  stop    - Stop and remove the container"
    echo "  logs    - Show container logs"
    echo "  status  - Show container status"
    echo "  test    - Run connectivity test"
    echo "  clean   - Remove container and image"
    echo ""
    echo "Without a command, shows status."
}

# Main
case "${1:-status}" in
    build)
        do_build
        ;;
    run)
        do_run
        ;;
    stop)
        do_stop
        ;;
    logs)
        do_logs
        ;;
    status)
        do_status
        ;;
    test)
        do_test
        ;;
    clean)
        do_clean
        ;;
    -h|--help|help)
        show_usage
        ;;
    *)
        log_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac
