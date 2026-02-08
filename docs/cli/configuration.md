# Configuration

The Flatnet CLI can be configured through a configuration file and environment variables.

## Configuration File

The configuration file is located at:

```
~/.config/flatnet/config.toml
```

### Example Configuration

```toml
[gateway]
# Gateway API URL (auto-detected in WSL2 if not set)
url = "http://10.100.1.1:8080"

# Request timeout in seconds
timeout_secs = 5

[monitoring]
# Prometheus URL
prometheus_url = "http://localhost:9090"

# Grafana URL
grafana_url = "http://localhost:3000"

# Loki URL
loki_url = "http://localhost:3100"

[display]
# Enable colored output
color = true
```

### Creating the Configuration File

```bash
mkdir -p ~/.config/flatnet

cat > ~/.config/flatnet/config.toml << 'EOF'
[gateway]
url = "http://10.100.1.1:8080"
timeout_secs = 5

[monitoring]
prometheus_url = "http://localhost:9090"
grafana_url = "http://localhost:3000"
loki_url = "http://localhost:3100"

[display]
color = true
EOF
```

## Environment Variables

Environment variables override configuration file settings.

| Variable | Description | Default |
|----------|-------------|---------|
| `FLATNET_GATEWAY_URL` | Gateway API URL | Auto-detected |
| `FLATNET_GATEWAY_TIMEOUT` | Request timeout (seconds) | 5 |
| `FLATNET_PROMETHEUS_URL` | Prometheus URL | http://localhost:9090 |
| `FLATNET_GRAFANA_URL` | Grafana URL | http://localhost:3000 |
| `FLATNET_LOKI_URL` | Loki URL | http://localhost:3100 |
| `FLATNET_COLOR` | Enable colors (0/false to disable) | true |
| `NO_COLOR` | Disable colors (standard) | - |

### Example

```bash
# Temporarily override Gateway URL
FLATNET_GATEWAY_URL=http://192.168.1.100:8080 flatnet status

# Disable colors
NO_COLOR=1 flatnet doctor

# Export for the session
export FLATNET_GATEWAY_URL=http://10.100.1.1:8080
flatnet status
```

## Configuration Priority

Settings are applied in the following order (highest priority first):

1. **Environment variables** - Override everything
2. **Configuration file** - User settings
3. **Auto-detection** - Gateway URL from WSL2 resolv.conf
4. **Defaults** - Built-in fallback values

## Gateway URL Auto-Detection

In WSL2, the Gateway URL is automatically detected from `/etc/resolv.conf`:

```bash
# The Windows host IP is extracted from:
nameserver 172.x.x.x
```

This IP is used as the default Gateway host with port 8080.

## Sections

### [gateway]

Configuration for connecting to the Flatnet Gateway.

| Key | Type | Description |
|-----|------|-------------|
| `url` | string | Full URL to Gateway API (e.g., `http://10.100.1.1:8080`) |
| `timeout_secs` | integer | HTTP request timeout in seconds |

### [monitoring]

Configuration for monitoring service endpoints.

| Key | Type | Description |
|-----|------|-------------|
| `prometheus_url` | string | Prometheus server URL |
| `grafana_url` | string | Grafana dashboard URL |
| `loki_url` | string | Loki log aggregator URL |

### [display]

Display and output settings.

| Key | Type | Description |
|-----|------|-------------|
| `color` | boolean | Enable/disable colored output |

## Disabling Colors

Colors can be disabled in multiple ways:

1. **Configuration file**:
   ```toml
   [display]
   color = false
   ```

2. **Environment variable**:
   ```bash
   FLATNET_COLOR=false flatnet status
   ```

3. **NO_COLOR standard** (takes precedence):
   ```bash
   NO_COLOR=1 flatnet status
   ```

## Validating Configuration

Use the `doctor` command to verify your configuration:

```bash
flatnet doctor --verbose
```

This checks:
- Gateway connectivity
- Monitoring service availability
- Network configuration

## Resetting to Defaults

To reset to default configuration:

```bash
rm ~/.config/flatnet/config.toml
```

The CLI will use auto-detection and built-in defaults.
