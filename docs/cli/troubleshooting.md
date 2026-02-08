# Troubleshooting

This guide covers common issues and their solutions when using the Flatnet CLI.

## Quick Diagnostics

Always start by running diagnostics:

```bash
flatnet doctor
```

This identifies most common issues and provides actionable suggestions.

## Common Issues

### Gateway Connection Issues

#### Symptom: "Gateway: Stopped" or "connection refused"

```
╭─────────────────────────────────────────────────────╮
│ Flatnet System Status                               │
├─────────────────────────────────────────────────────┤
│ Gateway      ○ Stopped    10.100.1.1:8080 (conn...)│
╰─────────────────────────────────────────────────────╯
```

**Causes and Solutions:**

1. **Gateway not running on Windows**
   ```powershell
   # On Windows, check if OpenResty is running
   Get-Process -Name nginx -ErrorAction SilentlyContinue

   # Start the Gateway
   cd F:\flatnet\gateway
   .\nginx.exe
   ```

2. **Firewall blocking connection**
   ```powershell
   # On Windows, allow inbound connections on port 8080
   New-NetFirewallRule -DisplayName "Flatnet Gateway" -Direction Inbound -Port 8080 -Protocol TCP -Action Allow
   ```

3. **Wrong Gateway URL**
   ```bash
   # Check the detected Gateway URL
   flatnet status --json | grep gateway_url

   # Override if necessary
   export FLATNET_GATEWAY_URL=http://YOUR_WINDOWS_IP:8080
   ```

4. **WSL2 network issues**
   ```bash
   # Check if Windows host is reachable
   ping $(grep nameserver /etc/resolv.conf | awk '{print $2}')
   ```

### Podman Not Found

#### Symptom: "Error: Podman not found" or "podman: command not found"

**Solutions:**

1. **Install Podman**
   ```bash
   # Ubuntu/Debian
   sudo apt update && sudo apt install podman

   # Fedora
   sudo dnf install podman
   ```

2. **Add Podman to PATH**
   ```bash
   # Check if podman is installed but not in PATH
   which podman || find /usr -name podman 2>/dev/null
   ```

### No Containers Found

#### Symptom: `flatnet ps` shows no containers

**Check:**

1. **Containers are running**
   ```bash
   podman ps -a
   ```

2. **Using the correct Podman socket**
   ```bash
   # Check if running as rootless
   podman info | grep -i rootless
   ```

### Missing Flatnet IPs

#### Symptom: Containers show "-" for Flatnet IP

```
CONTAINER ID  NAME   IMAGE          FLATNET IP  STATUS
a1b2c3d4e5f6  web    nginx:latest   -           Up 2 hours
```

**Causes and Solutions:**

1. **Container not on Flatnet network**
   ```bash
   # Create container on flatnet network
   podman run --network=flatnet -d nginx
   ```

2. **Gateway registry not synced**
   ```bash
   # Check Gateway status
   flatnet status

   # If Gateway is running, restart container
   podman restart <container>
   ```

3. **CNI plugin not installed**
   ```bash
   flatnet doctor --verbose
   # Look for CNI Plugin checks
   ```

### Logs Not Available

#### Symptom: "No logs found" or "Loki unavailable"

**Solutions:**

1. **Use Podman fallback**
   ```bash
   # If Loki is down, logs fall back to Podman
   # Just wait for the automatic fallback message
   ```

2. **Check if Loki is running**
   ```bash
   flatnet doctor | grep -i loki

   # Start Loki if needed
   podman start loki
   ```

3. **Check Loki URL configuration**
   ```bash
   # View current config
   cat ~/.config/flatnet/config.toml

   # Or override via environment
   FLATNET_LOKI_URL=http://localhost:3100 flatnet logs gateway
   ```

### Monitoring Services Stopped

#### Symptom: Prometheus, Grafana, or Loki show as Stopped

**Solutions:**

1. **Start the monitoring stack**
   ```bash
   podman start prometheus grafana loki
   ```

2. **Check if containers exist**
   ```bash
   podman ps -a | grep -E 'prometheus|grafana|loki'
   ```

3. **Check container logs for errors**
   ```bash
   podman logs prometheus
   podman logs grafana
   podman logs loki
   ```

### CLI Binary Not Found

#### Symptom: "flatnet: command not found"

**Solutions:**

1. **Add install directory to PATH**
   ```bash
   export PATH="$PATH:$HOME/.local/bin"

   # Make permanent
   echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
   source ~/.bashrc
   ```

2. **Reinstall the CLI**
   ```bash
   curl -fsSL https://raw.githubusercontent.com/khayashi4337/flatnet/master/scripts/install-cli.sh | bash
   ```

### Upgrade Fails

#### Symptom: "flatnet upgrade" fails

**Common causes:**

1. **No internet connection**
   ```bash
   # Check GitHub access
   curl -I https://github.com
   ```

2. **GitHub API rate limit**
   ```bash
   # Check rate limit
   curl -s https://api.github.com/rate_limit | jq .rate
   ```

3. **Binary permission issues**
   ```bash
   # Check file permissions
   ls -la $(which flatnet)

   # Fix if needed
   chmod +x $(which flatnet)
   ```

4. **No releases available**
   - Check [GitHub Releases](https://github.com/khayashi4337/flatnet/releases)

### Display Issues

#### Symptom: Garbled output or missing characters

**Solutions:**

1. **Terminal doesn't support Unicode**
   ```bash
   # Disable fancy output
   NO_COLOR=1 flatnet status
   ```

2. **Wrong locale settings**
   ```bash
   # Set UTF-8 locale
   export LANG=en_US.UTF-8
   export LC_ALL=en_US.UTF-8
   ```

## Getting More Information

### Verbose Output

```bash
flatnet doctor --verbose
```

### JSON Output for Debugging

```bash
flatnet status --json
flatnet doctor --json
flatnet ps --json
```

### Check Version

```bash
flatnet --version
```

## Reporting Issues

If you encounter an issue not covered here:

1. Run diagnostics and capture output:
   ```bash
   flatnet doctor --verbose > doctor.log 2>&1
   flatnet status --json > status.json 2>&1
   ```

2. Check the [GitHub Issues](https://github.com/khayashi4337/flatnet/issues)

3. Open a new issue with:
   - CLI version (`flatnet --version`)
   - OS and architecture
   - Full error message
   - Diagnostic output

## Quick Reference

| Problem | Quick Fix |
|---------|-----------|
| Gateway not connecting | Check Windows firewall, verify Gateway is running |
| No Flatnet IPs | Use `--network=flatnet` when creating containers |
| Logs not available | Loki down, automatic Podman fallback will be used |
| Command not found | Add `~/.local/bin` to PATH |
| Upgrade fails | Check internet connection and GitHub access |
