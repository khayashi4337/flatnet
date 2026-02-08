# logs

View logs from Flatnet components or containers.

## Synopsis

```bash
flatnet logs <TARGET> [OPTIONS]
```

## Description

The `logs` command displays logs from Flatnet components or individual containers. It first attempts to fetch logs from Loki (centralized log aggregation), and falls back to Podman logs if Loki is unavailable.

## Arguments

| Argument | Description |
|----------|-------------|
| `TARGET` | Component name or container name/ID |

### Known Components

| Component | Description |
|-----------|-------------|
| `gateway` | OpenResty Gateway logs |
| `cni` | CNI Plugin logs |
| `prometheus` | Prometheus server logs |
| `grafana` | Grafana dashboard logs |
| `loki` | Loki log aggregator logs |

## Options

| Option | Description |
|--------|-------------|
| `-n, --tail <LINES>` | Number of lines to show from the end |
| `-f, --follow` | Follow log output in real-time |
| `--since <DURATION>` | Show logs since duration (e.g., 1h, 30m, 2d) |
| `--grep <PATTERN>` | Filter logs by pattern |
| `--json` | Output in JSON format |
| `-h, --help` | Print help information |

## Examples

### View Gateway Logs

```bash
flatnet logs gateway
```

### View Last 50 Lines

```bash
flatnet logs gateway --tail 50
```

### Follow Logs in Real-time

```bash
flatnet logs gateway --follow
```

### View Logs from Last Hour

```bash
flatnet logs cni --since 1h
```

### Filter Logs by Pattern

```bash
flatnet logs gateway --grep "error"
```

### Combine Options

View errors from the last 30 minutes:

```bash
flatnet logs gateway --since 30m --grep "error" --tail 100
```

### View Container Logs

View logs from a specific container:

```bash
flatnet logs my-web-container
```

Or by container ID:

```bash
flatnet logs a1b2c3d4
```

### JSON Output

```bash
flatnet logs gateway --json --tail 10
```

Output:
```json
{
  "target": "gateway",
  "source": "loki",
  "entries": [
    {
      "timestamp": "2024-01-15T10:30:15Z",
      "line": "2024/01/15 10:30:15 [info] request completed: 200"
    },
    {
      "timestamp": "2024-01-15T10:30:14Z",
      "line": "2024/01/15 10:30:14 [info] incoming request: GET /api/status"
    }
  ]
}
```

## Duration Format

The `--since` option accepts durations in the following formats:

| Format | Example | Description |
|--------|---------|-------------|
| `Ns` | `30s` | N seconds ago |
| `Nm` | `30m` | N minutes ago |
| `Nh` | `2h` | N hours ago |
| `Nd` | `1d` | N days ago |

## Log Sources

The `logs` command uses two sources:

1. **Loki** (preferred): Centralized log aggregation with full-text search
2. **Podman** (fallback): Direct container logs via Podman

If Loki is unavailable, the command automatically falls back to Podman:

```
Note: Loki unavailable (connection refused), falling back to Podman logs...
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (e.g., target not found) |

## Troubleshooting

### "Container or component not found"

Make sure the target exists:

```bash
# List known components
flatnet logs --help

# List running containers
flatnet ps
```

### "Loki unavailable"

If you see this message, logs will be fetched from Podman instead. To enable Loki:

1. Ensure Loki is running: `flatnet doctor`
2. Check Loki configuration in `~/.config/flatnet/config.toml`

### No Logs Displayed

If no logs are shown:

1. Check if the component/container is running: `flatnet status`
2. Try a longer time range: `--since 1d`
3. Check if logs exist in Podman: `podman logs <container>`

## See Also

- [status](status.md) - Check system status
- [ps](ps.md) - List containers
- [Configuration](../configuration.md) - Configure Loki URL
