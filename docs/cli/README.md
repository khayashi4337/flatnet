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

### Tutorial

初めての方は [Getting Started - チュートリアル](getting-started.md) をご覧ください。インストールから基本的な使い方まで、ステップバイステップで解説しています。

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

## Quick Reference

コマンドを素早く確認したい場合は [クイックリファレンス](quick-reference.md) をご覧ください。

## Use Cases

実践的な使い方やスクリプト例は [ユースケース集](use-cases.md) をご覧ください。CI/CD 連携や自動化の例も含まれています。

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
