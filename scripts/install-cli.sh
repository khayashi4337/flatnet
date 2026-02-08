#!/bin/bash
# Flatnet CLI Installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/khayashi4337/flatnet/master/scripts/install-cli.sh | bash
#
# Environment variables:
#   FLATNET_INSTALL_DIR - Installation directory (default: ~/.local/bin)
#   FLATNET_VERSION     - Specific version to install (default: latest)

set -euo pipefail

# Configuration
REPO="khayashi4337/flatnet"
BINARY_NAME="flatnet"
INSTALL_DIR="${FLATNET_INSTALL_DIR:-$HOME/.local/bin}"

# Colors (only if terminal supports it)
if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "$TERM" != "dumb" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

# Print functions
info() {
    printf "${BLUE}==>${NC} ${BOLD}%s${NC}\n" "$1"
}

success() {
    printf "${GREEN}==>${NC} ${BOLD}%s${NC}\n" "$1"
}

warn() {
    printf "${YELLOW}Warning:${NC} %s\n" "$1"
}

error() {
    printf "${RED}Error:${NC} %s\n" "$1" >&2
}

# Detect platform
detect_platform() {
    local os arch

    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)

    case "$os" in
        linux)
            os="linux"
            ;;
        darwin)
            # macOS support is planned but binaries may not be available yet
            os="darwin"
            ;;
        *)
            error "Unsupported operating system: $os"
            exit 1
            ;;
    esac

    case "$arch" in
        x86_64|amd64)
            arch="x86_64"
            ;;
        aarch64|arm64)
            arch="aarch64"
            ;;
        *)
            error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac

    echo "${os}-${arch}"
}

# Check for required commands
check_requirements() {
    local missing=()

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        missing+=("curl or wget")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        error "Missing required commands: ${missing[*]}"
        exit 1
    fi
}

# Fetch URL content (supports both curl and wget)
fetch() {
    local url="$1"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url"
    else
        wget -qO- "$url"
    fi
}

# Download file (supports both curl and wget)
download() {
    local url="$1"
    local dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest"
    else
        wget -q "$url" -O "$dest"
    fi
}

# Get latest version from GitHub releases
get_latest_version() {
    local response
    response=$(fetch "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null) || {
        error "Failed to fetch latest version from GitHub"
        error "Please check your internet connection or try again later"
        exit 1
    }

    # Extract tag_name from JSON response
    # Supports both cli-v* and v* tag formats
    local version
    version=$(echo "$response" | grep '"tag_name":' | sed -E 's/.*"tag_name":\s*"([^"]+)".*/\1/')

    if [ -z "$version" ]; then
        error "Could not parse version from GitHub API response"
        exit 1
    fi

    # Remove cli- prefix and v prefix if present
    version="${version#cli-}"
    version="${version#v}"
    echo "$version"
}

# Main installation function
install() {
    local platform version url tmp_file

    info "Detecting platform..."
    platform=$(detect_platform)
    echo "  Platform: $platform"

    # Get version (from env or latest)
    if [ -n "${FLATNET_VERSION:-}" ]; then
        version="${FLATNET_VERSION#v}"
        info "Installing specified version: v${version}"
    else
        info "Fetching latest version..."
        version=$(get_latest_version)
        echo "  Latest version: v${version}"
    fi

    # Construct download URL
    url="https://github.com/${REPO}/releases/download/cli-v${version}/flatnet-${platform}"

    info "Downloading flatnet v${version}..."
    echo "  URL: $url"

    # Create install directory if it doesn't exist
    mkdir -p "$INSTALL_DIR"

    # Download to temporary file
    tmp_file=$(mktemp)
    trap 'rm -f "$tmp_file"' EXIT

    if ! download "$url" "$tmp_file"; then
        error "Failed to download binary"
        error "URL: $url"
        echo ""
        echo "Please check:"
        echo "  1. The version exists: https://github.com/${REPO}/releases"
        echo "  2. Your platform ($platform) is supported"
        exit 1
    fi

    # Make executable
    chmod +x "$tmp_file"

    # Move to final location
    mv "$tmp_file" "${INSTALL_DIR}/${BINARY_NAME}"
    trap - EXIT

    success "Installed flatnet v${version} to ${INSTALL_DIR}/${BINARY_NAME}"
    echo ""

    # Check if install directory is in PATH
    if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
        warn "${INSTALL_DIR} is not in your PATH"
        echo ""
        echo "Add the following to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
        echo ""
        echo "    export PATH=\"\$PATH:${INSTALL_DIR}\""
        echo ""
        echo "Then reload your shell or run:"
        echo ""
        echo "    source ~/.bashrc  # or source ~/.zshrc"
        echo ""
    fi

    # Verify installation
    if command -v flatnet >/dev/null 2>&1; then
        echo "Verify installation:"
        echo ""
        flatnet --version
    else
        echo "Verify installation by running:"
        echo ""
        echo "    ${INSTALL_DIR}/flatnet --version"
    fi
}

# Entry point
main() {
    echo ""
    echo "Flatnet CLI Installer"
    echo "====================="
    echo ""

    check_requirements
    install

    echo ""
    success "Installation complete!"
    echo ""
    echo "Get started with:"
    echo ""
    echo "    flatnet status    # Check system status"
    echo "    flatnet doctor    # Run diagnostics"
    echo "    flatnet ps        # List containers"
    echo "    flatnet --help    # Show all commands"
    echo ""
}

main
