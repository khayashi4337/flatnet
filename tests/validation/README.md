# Flatnet Validation Tests

Phase 4, Stage 5: Validation Test Scripts

This directory contains scripts for validating the Flatnet system before production deployment.

## Overview

| Script | Purpose | Usage |
|--------|---------|-------|
| `load-test.sh` | Performance and load testing | Pre-production capacity planning |
| `health-check.sh` | System health verification | Daily checks, monitoring integration |

## Prerequisites

### For Load Testing

One of the following load testing tools:

**wrk (recommended)**
```bash
# Ubuntu/Debian - build from source
sudo apt install build-essential libssl-dev git
git clone https://github.com/wg/wrk.git
cd wrk && make && sudo cp wrk /usr/local/bin/
```

**hey (alternative)**
```bash
# If Go is installed
go install github.com/rakyll/hey@latest

# Or download binary
wget https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64
chmod +x hey_linux_amd64 && sudo mv hey_linux_amd64 /usr/local/bin/hey
```

### Common Dependencies

```bash
# Required
sudo apt install curl jq bc
```

## Load Test Script

### Basic Usage

```bash
# Run with default settings (auto-detect Gateway)
./load-test.sh

# Specify target URL
./load-test.sh -u http://192.168.1.100/

# Custom duration and concurrency levels
./load-test.sh -d 60 -l 10,25,50,100

# JSON output only (for automation)
./load-test.sh -j > results.json
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-u, --url URL` | Target URL | Auto-detect Gateway |
| `-d, --duration SEC` | Duration per test | 30 |
| `-o, --output DIR` | Output directory | ./results |
| `-l, --levels LIST` | Concurrency levels | 10,50,100,200 |
| `-t, --threads NUM` | Thread count (wrk) | Auto |
| `-j, --json` | JSON output only | false |
| `-h, --help` | Show help | - |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GATEWAY_IP` | Gateway IP address | Auto-detect |
| `GATEWAY_PORT` | Gateway port | 80 |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All tests completed successfully |
| 1 | Error (missing tools, unreachable target, etc.) |

### Output

Results are saved to the output directory:
- Individual test results: `load_test_c{N}_{timestamp}.json`
- Combined results: `load_test_combined_{timestamp}.json`

Example output:
```
==============================================
           LOAD TEST RESULTS SUMMARY
==============================================

Target: http://172.25.160.1/
Tool:   wrk
Date:   2024-01-15 10:30:00

Concurrency  | RPS        | Avg Latency  | p99 Latency  | Error Rate
-------------+------------+--------------+--------------+-----------
10           | 1523.45    | 6.54 ms      | 15.23 ms     | 0.00 %
50           | 4521.32    | 11.05 ms     | 45.67 ms     | 0.00 %
100          | 5234.78    | 19.10 ms     | 89.45 ms     | 0.12 %
200          | 4892.34    | 40.87 ms     | 198.32 ms    | 1.45 %

----------------------------------------------

Best throughput: 5234.78 RPS at 100 concurrent connections
Recommended concurrency: 100 (error rate < 1%)
```

## Health Check Script

### Basic Usage

```bash
# Full health check with colors
./health-check.sh

# Quiet mode (only output on failure)
./health-check.sh -q

# JSON output (for monitoring integration)
./health-check.sh -j

# Verbose mode
./health-check.sh -v
```

### Options

| Option | Description |
|--------|-------------|
| `-q, --quiet` | Only output on failure |
| `-j, --json` | Output results as JSON |
| `-v, --verbose` | Show detailed information |
| `--no-color` | Disable colored output |
| `-h, --help` | Show help |

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All checks passed |
| 1 | One or more checks failed |
| 2 | One or more checks warning |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `GATEWAY_IP` | Gateway IP address | Auto-detect |
| `GATEWAY_PORT` | Gateway port | 80 |
| `PROMETHEUS_PORT` | Prometheus port | 9090 |
| `GRAFANA_PORT` | Grafana port | 3000 |
| `ALERTMANAGER_PORT` | Alertmanager port | 9093 |
| `LOKI_PORT` | Loki port | 3100 |
| `DISK_WARN_PERCENT` | Disk warning threshold | 80 |
| `DISK_CRIT_PERCENT` | Disk critical threshold | 90 |
| `MEM_WARN_PERCENT` | Memory warning threshold | 85 |

### Checks Performed

1. **Gateway (HTTP)** - Verifies Gateway is responding
2. **Prometheus** - Checks Prometheus readiness
3. **Grafana** - Checks Grafana health endpoint
4. **Alertmanager** - Checks Alertmanager readiness
5. **Loki** - Checks Loki readiness
6. **Disk Space** - Checks disk usage (warning at 80%, critical at 90%)
7. **Memory Usage** - Checks memory usage (warning at 85%)
8. **Containers** - Lists running Podman containers

### JSON Output Format

```json
{
    "timestamp": "2024-01-15T10:30:00+09:00",
    "summary": {
        "total": 8,
        "passed": 7,
        "failed": 0,
        "warning": 1
    },
    "overall_status": "degraded",
    "checks": [
        {"name": "Gateway", "status": "ok", "message": "HTTP 200"},
        {"name": "Prometheus", "status": "ok", "message": "HTTP 200"},
        ...
    ]
}
```

## Integration with Monitoring

### Cron Job for Health Checks

Add to crontab for regular health checks:

```bash
# Run health check every 5 minutes
*/5 * * * * /path/to/tests/validation/health-check.sh -q >> /var/log/flatnet/health-check.log 2>&1
```

### Prometheus Integration

Use the JSON output with a custom exporter or textfile collector:

```bash
# Write metrics to textfile for node_exporter
./health-check.sh -j | jq -r '
  "flatnet_health_check_total " + (.summary.total|tostring),
  "flatnet_health_check_passed " + (.summary.passed|tostring),
  "flatnet_health_check_failed " + (.summary.failed|tostring),
  "flatnet_health_check_warning " + (.summary.warning|tostring)
' > /var/lib/node_exporter/textfile_collector/flatnet_health.prom
```

## Troubleshooting

### Load Test Issues

**"Cannot reach target" error:**
- Verify Gateway is running: `curl http://<GATEWAY_IP>/`
- Check Windows firewall allows connections

**Low throughput:**
- Increase thread count with `-t` option
- Check if target is the bottleneck

**High error rate at low concurrency:**
- Check backend service health
- Review Gateway logs for errors

**Test interrupted (Ctrl+C):**
- Partial results are automatically saved to the output directory
- Check `./results` for individual test files
- Re-run the script to continue testing from scratch

### Health Check Issues

**Gateway check fails:**
- Verify OpenResty is running on Windows
- Check WSL2 to Windows connectivity
- Test manually: `curl http://$(grep nameserver /etc/resolv.conf | awk '{print $2}')/`

**Monitoring services fail:**
- Ensure monitoring stack is running: `cd /path/to/monitoring && podman-compose ps`
- Check port bindings: `ss -tlnp | grep -E '(9090|3000|9093|3100)'`

## Related Documentation

- [Test Plan](../../docs/operations/test-plan.md)
- [Load Test Report Template](../../docs/operations/load-test-report-template.md)
- [Validation Report Template](../../docs/operations/validation-report-template.md)
- [Monitoring Stack](../../monitoring/README.md)
