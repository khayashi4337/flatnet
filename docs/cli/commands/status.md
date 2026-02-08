# status

Display the status of all Flatnet system components.

## Synopsis

```bash
flatnet status [OPTIONS]
```

## Description

The `status` command provides an overview of the Flatnet system, showing the health and status of all components:

- **Gateway**: The OpenResty gateway on Windows
- **CNI Plugin**: Container network interface plugin
- **Healthcheck**: Container health monitoring service
- **Prometheus**: Metrics collection
- **Grafana**: Metrics visualization
- **Loki**: Log aggregation

## Options

| Option | Description |
|--------|-------------|
| `--json` | Output status in JSON format |
| `-w, --watch` | Continuously update status display |
| `--interval <SECS>` | Interval between updates in watch mode (default: 2) |
| `-h, --help` | Print help information |

## Examples

### Basic Status

```bash
flatnet status
```

Output:
```
╭─────────────────────────────────────────────────────╮
│ Flatnet System Status                               │
├─────────────────────────────────────────────────────┤
│ Gateway      ● Running    10.100.1.1:8080           │
│ CNI Plugin   ● Ready      10.100.x.0/24 (5 IPs)     │
│ Healthcheck  ● Running    5 healthy, 0 unhealthy    │
│ Prometheus   ● Running    :9090                     │
│ Grafana      ● Running    :3000                     │
│ Loki         ● Running    :3100                     │
╰─────────────────────────────────────────────────────╯

Containers: 5 running
```

### Watch Mode

Monitor status in real-time:

```bash
flatnet status --watch
```

Update every 5 seconds:

```bash
flatnet status --watch --interval 5
```

### JSON Output

For scripting and automation:

```bash
flatnet status --json
```

Output:
```json
{
  "components": [
    {
      "name": "Gateway",
      "status": "Running",
      "details": "10.100.1.1:8080"
    },
    {
      "name": "CNI Plugin",
      "status": "Ready",
      "details": "10.100.x.0/24 (5 IPs)"
    }
  ],
  "containers": 5,
  "uptime": null,
  "gateway_url": "http://10.100.1.1:8080"
}
```

## Status Indicators

| Symbol | Color | Meaning |
|--------|-------|---------|
| ● | Green | Running/Ready - Component is healthy |
| ● | Yellow | Warning/Disabled - Component needs attention |
| ○ | Red | Stopped/Error - Component is not working |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (e.g., failed to connect to Gateway) |

## See Also

- [doctor](doctor.md) - Run diagnostics and check for issues
- [ps](ps.md) - List containers with Flatnet IPs
