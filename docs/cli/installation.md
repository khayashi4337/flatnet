# Installation

This guide covers different methods to install the Flatnet CLI.

## Quick Install (Recommended)

The fastest way to install Flatnet CLI is using the install script:

```bash
curl -fsSL https://raw.githubusercontent.com/khayashi4337/flatnet/master/scripts/install-cli.sh | bash
```

Or using wget:

```bash
wget -qO- https://raw.githubusercontent.com/khayashi4337/flatnet/master/scripts/install-cli.sh | bash
```

This will:
1. Detect your platform (Linux x86_64 or aarch64)
2. Download the latest release
3. Install to `~/.local/bin/flatnet`
4. Display PATH instructions if needed

## Manual Installation

### Download Binary

1. Go to the [Releases page](https://github.com/khayashi4337/flatnet/releases)
2. Download the binary for your platform:
   - `flatnet-linux-x86_64` for Linux x86_64
   - `flatnet-linux-aarch64` for Linux ARM64

3. Make it executable and move to your PATH:

```bash
chmod +x flatnet-linux-x86_64
mv flatnet-linux-x86_64 ~/.local/bin/flatnet
```

### Verify Installation

```bash
flatnet --version
```

## Build from Source

If you want to build from source:

```bash
# Clone the repository
git clone https://github.com/khayashi4337/flatnet.git
cd flatnet

# Build with cargo
cd src/flatnet-cli
cargo build --release

# Install
cp target/release/flatnet ~/.local/bin/
```

### Requirements

- Rust 1.70 or later
- Cargo

## Installation Options

### Custom Install Directory

By default, the install script places the binary in `~/.local/bin`. You can customize this:

```bash
FLATNET_INSTALL_DIR=/usr/local/bin bash -c "$(curl -fsSL https://raw.githubusercontent.com/khayashi4337/flatnet/master/scripts/install-cli.sh)"
```

### Specific Version

To install a specific version:

```bash
FLATNET_VERSION=0.1.0 bash -c "$(curl -fsSL https://raw.githubusercontent.com/khayashi4337/flatnet/master/scripts/install-cli.sh)"
```

## Adding to PATH

If the install directory is not in your PATH, add it to your shell profile:

### Bash

```bash
echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
source ~/.bashrc
```

### Zsh

```bash
echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.zshrc
source ~/.zshrc
```

## Upgrading

Once installed, you can upgrade to the latest version:

```bash
# Check for updates
flatnet upgrade --check

# Upgrade to latest
flatnet upgrade

# Upgrade to specific version
flatnet upgrade --version 0.2.0
```

## Uninstalling

To uninstall, simply remove the binary:

```bash
rm ~/.local/bin/flatnet
```

And optionally remove the configuration:

```bash
rm -rf ~/.config/flatnet
```

## Supported Platforms

| Platform | Architecture | Status |
|----------|--------------|--------|
| Linux | x86_64 | Supported |
| Linux | aarch64 | Supported |
| macOS | x86_64 | Planned |
| macOS | aarch64 (M1/M2) | Planned |
| Windows | x86_64 | Not supported |

Note: Flatnet CLI is designed to run on WSL2 (Linux), not native Windows.
