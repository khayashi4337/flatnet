# ps

List containers with their Flatnet IP addresses.

## Synopsis

```bash
flatnet ps [OPTIONS]
```

## Description

The `ps` command lists all containers running in Podman and displays their Flatnet IP addresses. It combines information from Podman with the Flatnet Gateway registry to show which containers have been assigned Flatnet IPs.

## Options

| Option | Description |
|--------|-------------|
| `-a, --all` | Show all containers including stopped ones |
| `-f, --filter <FILTER>` | Filter containers by name, id, or image |
| `--json` | Output in JSON format |
| `-q, --quiet` | Only display container IDs |
| `-h, --help` | Print help information |

## Examples

### List Running Containers

```bash
flatnet ps
```

Output:
```
CONTAINER ID  NAME       IMAGE              FLATNET IP    STATUS
a1b2c3d4e5f6  web        nginx:latest       10.100.1.10   Up 2 hours
b2c3d4e5f6g7  api        myapp:v1.2         10.100.1.11   Up 2 hours
c3d4e5f6g7h8  db         postgres:15        10.100.1.12   Up 2 hours
d4e5f6g7h8i9  redis      redis:7-alpine     -             Up 1 hour

Total: 4 containers, 3 Flatnet IPs allocated
```

### Include Stopped Containers

```bash
flatnet ps --all
```

### Filter by Name

```bash
flatnet ps --filter name=web
```

### Filter by Image

```bash
flatnet ps --filter image=nginx
```

### Filter by State

```bash
flatnet ps --filter state=running
```

### Free-text Filter

Search in name, id, or image:

```bash
flatnet ps --filter nginx
```

### Get Container IDs Only

```bash
flatnet ps --quiet
```

Output:
```
a1b2c3d4e5f6
b2c3d4e5f6g7
c3d4e5f6g7h8
d4e5f6g7h8i9
```

### JSON Output

```bash
flatnet ps --json
```

Output:
```json
{
  "total_containers": 4,
  "flatnet_ips_allocated": 3,
  "containers": [
    {
      "id": "a1b2c3d4",
      "name": "web",
      "image": "nginx:latest",
      "flatnet_ip": "10.100.1.10",
      "status": "Up 2 hours"
    },
    {
      "id": "b2c3d4e5",
      "name": "api",
      "image": "myapp:v1.2",
      "flatnet_ip": "10.100.1.11",
      "status": "Up 2 hours"
    }
  ]
}
```

## Output Columns

| Column | Description |
|--------|-------------|
| CONTAINER ID | Short container ID (first 12 characters) |
| NAME | Container name |
| IMAGE | Container image (truncated if too long) |
| FLATNET IP | Assigned Flatnet IP address, or `-` if none |
| STATUS | Container status (Up, Exited, etc.) |

## Filter Syntax

Filters can be specified as `key=value` pairs:

| Key | Description |
|-----|-------------|
| `name` | Match container name (contains) |
| `id` | Match container ID (contains) |
| `image` | Match image name (contains) |
| `state` or `status` | Match container state (running, exited, etc.) |

If no key is specified, the filter searches across name, id, and image.

## Understanding Flatnet IPs

- Containers with a Flatnet IP are reachable from the corporate LAN via the Gateway
- Containers showing `-` for Flatnet IP are not registered with Flatnet
- Flatnet IPs are assigned by the CNI plugin when containers are created on the flatnet network

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error (e.g., Podman not available) |

## See Also

- [status](status.md) - Check system status
- [logs](logs.md) - View container logs
