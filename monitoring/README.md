# Flatnet Monitoring Stack

Phase 4, Stage 1: Monitoring Infrastructure

This directory contains the monitoring stack for Flatnet, including Prometheus, Grafana, Alertmanager, and Node Exporter.

## Components

| Component | Port | Description |
|-----------|------|-------------|
| Prometheus | 9090 | Metrics collection and alerting |
| Grafana | 3000 | Visualization dashboards |
| Alertmanager | 9093 | Alert routing and notification |
| Node Exporter | 9100 | Host system metrics |
| Gateway Metrics | 9145 | OpenResty Gateway metrics |

## Security Notice

**IMPORTANT**: The default configuration uses simple passwords suitable for local development only.

For production deployments:
1. Change the Grafana admin password using the .env file:
   ```bash
   cp .env.example .env
   # Edit .env and set GRAFANA_ADMIN_PASSWORD
   ./scripts/monitoring/start.sh
   ```
   Or set it in your shell environment:
   ```bash
   export GRAFANA_ADMIN_PASSWORD="your-secure-password"
   ./scripts/monitoring/start.sh
   ```
2. Consider binding services to localhost only (edit `podman-compose.yml` ports)
3. Use a reverse proxy with TLS for external access
4. Configure proper authentication for Prometheus and Alertmanager

## Quick Start

```bash
# Start the monitoring stack
./scripts/monitoring/start.sh

# Check status
./scripts/monitoring/status.sh

# Stop the monitoring stack
./scripts/monitoring/stop.sh
```

## Access

- **Prometheus**: http://localhost:9090
- **Grafana**: http://localhost:3000
  - Username: `admin`
  - Password: `flatnet` (default, or `$GRAFANA_ADMIN_PASSWORD` if set)
- **Alertmanager**: http://localhost:9093

## Directory Structure

```
monitoring/
├── .env.example                # Environment variable template
├── podman-compose.yml          # Container definitions
├── prometheus/
│   ├── prometheus.yml          # Prometheus configuration
│   └── alerts/
│       ├── gateway.yml         # Gateway alert rules
│       ├── cni.yml             # CNI Plugin alert rules
│       └── system.yml          # System alert rules
├── alertmanager/
│   └── alertmanager.yml        # Alertmanager configuration
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/        # Prometheus data source
│   │   └── dashboards/         # Dashboard provisioning
│   └── dashboards/
│       ├── system-overview.json    # System overview
│       ├── gateway-detail.json     # Gateway details
│       └── cni-detail.json         # CNI Plugin details
└── README.md
```

## Dashboards

### System Overview
- Service status (Gateway, Prometheus, Node Exporter)
- Request rate and error rate
- CPU, Memory, and Disk usage

### Gateway Detail
- Requests by status code
- Response time percentiles (p50, p95, p99)
- Active connections
- Status code distribution

### CNI Plugin Detail
- Container count (active and total)
- IP allocation status
- Operation success/failure rate
- Gateway registration metrics

## Alert Rules

### Critical Alerts
- **GatewayDown**: Gateway unreachable for 1+ minute
- **CNIPluginDown**: CNI Plugin unreachable for 1+ minute
- **DiskSpaceCritical**: Disk usage above 90%

### Warning Alerts
- **HighErrorRate**: Error rate above 5% for 5+ minutes
- **HighLatency**: P95 latency above 1 second for 5+ minutes
- **DiskSpaceWarning**: Disk usage above 80%
- **HighMemoryUsage**: Memory usage above 85%
- **HighCPUUsage**: CPU usage above 80% for 10+ minutes

## Configuration

### Adding Notification Receivers

Edit `alertmanager/alertmanager.yml` to configure alert notifications:

```yaml
# Slack example
receivers:
  - name: 'slack-notifications'
    slack_configs:
      - channel: '#flatnet-alerts'
        api_url: 'https://hooks.slack.com/services/xxx/yyy/zzz'
        send_resolved: true
```

### Adjusting Scrape Intervals

Edit `prometheus/prometheus.yml`:

```yaml
global:
  scrape_interval: 15s      # Default scrape interval
  evaluation_interval: 15s  # Rule evaluation interval
```

### Adding New Scrape Targets

Add new jobs to `prometheus/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'my-service'
    static_configs:
      - targets: ['host:port']
```

## Gateway Metrics

The Gateway exposes metrics at `http://localhost:9145/metrics` in Prometheus text format:

- `flatnet_http_requests_total` - Total HTTP requests (counter)
- `flatnet_http_requests_total{status="..."}` - Requests by status code
- `flatnet_http_request_duration_seconds_bucket` - Response time histogram
- `flatnet_active_connections` - Current active connections (gauge)

### Enabling Gateway Metrics

Add to `nginx.conf`:

```nginx
# Shared memory for metrics
lua_shared_dict flatnet_metrics 1m;
```

Add metrics endpoint to your server block:

```nginx
location /metrics {
    content_by_lua_block {
        local metrics = require("flatnet.metrics")
        ngx.header.content_type = "text/plain; charset=utf-8"
        ngx.say(metrics.export())
    }
}
```

## Data Persistence

Monitoring data is stored in Podman volumes:
- `prometheus_data` - Prometheus TSDB (15 days retention)
- `grafana_data` - Grafana dashboards and settings
- `alertmanager_data` - Alertmanager state

To remove all data:
```bash
./scripts/monitoring/stop.sh --volumes
```

## Troubleshooting

### Prometheus can't scrape Gateway

1. Check that OpenResty is running on Windows
2. Verify the metrics endpoint: `curl http://localhost:9145/metrics`
3. Check WSL2 to Windows connectivity: `curl http://$(cat /etc/resolv.conf | grep nameserver | awk '{print $2}'):9145/metrics`

### Grafana shows "No data"

1. Check Prometheus is running: `curl http://localhost:9090/-/ready`
2. Verify the data source in Grafana (Settings > Data Sources)
3. Check for metrics in Prometheus: http://localhost:9090/graph

### Alerts not firing

1. Check alert rules in Prometheus: http://localhost:9090/alerts
2. Verify Alertmanager is running: `curl http://localhost:9093/-/ready`
3. Check Alertmanager configuration in Prometheus

## Requirements

- Podman 4.x
- podman-compose (`pip install podman-compose`)
- Approximately 2GB RAM for all services
- 10GB disk space for Prometheus data (2 weeks retention)
