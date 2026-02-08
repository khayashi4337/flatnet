# Flatnet CLI

Flatnet CLI is a command-line tool for managing and monitoring the Flatnet system.

## Overview

The Flatnet CLI provides a unified interface to:

- Check system status across all components
- Diagnose issues and get actionable suggestions
- List containers with their Flatnet IPs
- View logs from components and containers
- Keep the CLI up to date

## Quick Start

### Installation

```bash
curl -fsSL https://raw.githubusercontent.com/khayashi4337/flatnet/master/scripts/install-cli.sh | bash
```

See [Installation Guide](installation.md) for more options.

### Basic Commands

```bash
# Check system status
flatnet status

# Run diagnostics
flatnet doctor

# List containers with Flatnet IPs
flatnet ps

# View logs
flatnet logs gateway

# Upgrade to latest version
flatnet upgrade
```

## Command Reference

| Command | Description |
|---------|-------------|
| [status](commands/status.md) | Display system status for all components |
| [doctor](commands/doctor.md) | Run diagnostics and check for issues |
| [ps](commands/ps.md) | List containers with Flatnet IP addresses |
| [logs](commands/logs.md) | View logs from components or containers |
| upgrade | Upgrade CLI to the latest version |

## Configuration

The CLI can be configured via:

1. Configuration file: `~/.config/flatnet/config.toml`
2. Environment variables: `FLATNET_*`

See [Configuration Guide](configuration.md) for details.

## Troubleshooting

Having issues? Check the [Troubleshooting Guide](troubleshooting.md) for common problems and solutions.

## Getting Help

```bash
# Show all commands
flatnet --help

# Show help for a specific command
flatnet status --help
flatnet doctor --help
```
