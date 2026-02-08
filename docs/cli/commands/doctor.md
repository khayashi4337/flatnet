# doctor

Run system diagnostics and check for issues.

## Synopsis

```bash
flatnet doctor [OPTIONS]
```

## Description

The `doctor` command runs a comprehensive set of diagnostic checks on the Flatnet system. It identifies issues and provides actionable suggestions for resolving them.

Checks are organized into categories:
- **Gateway**: Connectivity and API health
- **CNI Plugin**: Plugin installation and configuration
- **Network**: Network connectivity and routing
- **Monitoring**: Prometheus, Grafana, Loki availability
- **Disk**: Disk space and filesystem checks

## Options

| Option | Description |
|--------|-------------|
| `--json` | Output results in JSON format |
| `-q, --quiet` | Only show warnings and errors (for CI) |
| `-v, --verbose` | Show detailed diagnostic information |
| `-h, --help` | Print help information |

## Examples

### Run All Diagnostics

```bash
flatnet doctor
```

Output:
```
Running system diagnostics...

Gateway
  [✓] Gateway Connectivity
  [✓] Gateway API

CNI Plugin
  [✓] CNI Plugin installed
  [✓] CNI configuration valid

Network
  [✓] Windows host reachable
  [✓] Container network connectivity

Monitoring
  [✓] Prometheus
  [!] Grafana (port 3000 not responding)
      → Start Grafana: podman start grafana
  [✓] Loki

Disk
  [✓] Sufficient disk space

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Summary: 7 passed, 1 warnings, 0 failed
```

### Verbose Mode

Show detailed information for all checks:

```bash
flatnet doctor --verbose
```

### Quiet Mode (CI)

Only output issues (useful for CI/CD pipelines):

```bash
flatnet doctor --quiet
```

Output (only if there are issues):
```
[WARN] Monitoring/Grafana: port 3000 not responding
  -> Start Grafana: podman start grafana
```

### JSON Output

For scripting and automation:

```bash
flatnet doctor --json
```

Output:
```json
{
  "checks": [
    {
      "category": "Gateway",
      "name": "Gateway Connectivity",
      "status": "Pass",
      "message": "Connected to Gateway at 10.100.1.1:8080",
      "suggestion": null
    },
    {
      "category": "Monitoring",
      "name": "Grafana",
      "status": "Warning",
      "message": "port 3000 not responding",
      "suggestion": "Start Grafana: podman start grafana"
    }
  ],
  "summary": {
    "passed": 7,
    "warnings": 1,
    "failed": 0,
    "exit_code": 1
  }
}
```

## Check Results

| Symbol | Status | Meaning |
|--------|--------|---------|
| ✓ | Pass | Check passed |
| ! | Warning | Issue detected, but not critical |
| ✗ | Fail | Critical issue detected |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All checks passed |
| 1 | One or more warnings |
| 2 | One or more failures |

## Using in CI/CD

The doctor command is designed to work well in CI/CD pipelines:

```bash
# In CI script
flatnet doctor --quiet
if [ $? -ne 0 ]; then
    echo "Flatnet health check failed!"
    exit 1
fi
```

Or check for JSON output:

```bash
# Check for failures
FAILURES=$(flatnet doctor --json | jq '.summary.failed')
if [ "$FAILURES" -gt 0 ]; then
    echo "Flatnet has $FAILURES failures"
    exit 1
fi
```

## Checks Performed

### Gateway Checks
- Gateway connectivity (can reach the Gateway API)
- Gateway API health (API returns valid responses)

### CNI Plugin Checks
- Plugin binary exists
- Plugin configuration is valid

### Network Checks
- Windows host is reachable from WSL2
- Container network connectivity

### Monitoring Checks
- Prometheus is running and healthy
- Grafana is running and healthy
- Loki is running and ready

### Disk Checks
- Sufficient disk space available
- Writable filesystem for container data

## See Also

- [status](status.md) - Quick overview of system status
- [Configuration](../configuration.md) - Configure check thresholds
