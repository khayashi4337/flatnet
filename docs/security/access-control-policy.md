# Flatnet Access Control Policy

## 1. Overview

This document defines the access control policy for the Flatnet system. It establishes who can access what resources, how access is authenticated, and the procedures for granting and revoking access.

## 2. Principles

### 2.1 Minimum Privilege

Users and services should only have the minimum access required to perform their duties. Access should be:
- Specific to the required resources
- Limited to the required operations (read, write, admin)
- Time-limited where appropriate

### 2.2 Defense in Depth

Multiple layers of access control should be applied:
1. Network-level restrictions (IP allowlists)
2. Authentication (credentials, keys)
3. Authorization (role-based access)
4. Audit logging (all access logged)

### 2.3 Separation of Duties

No single individual should have unchecked administrative access:
- Configuration changes require review
- Access grants require approval
- Critical operations require multiple approvers

---

## 3. Resource Classification

### 3.1 Public Resources

Resources accessible without authentication from within the corporate network.

| Resource | Access Level | Notes |
|----------|--------------|-------|
| Gateway HTTP endpoints | Read | Proxied application access |
| Application UIs (via Gateway) | Varies | Per-application authentication |

### 3.2 Internal Resources

Resources accessible only from specific networks or with authentication.

| Resource | Access Level | Required Access |
|----------|--------------|-----------------|
| Gateway API (8080) | Admin | Nebula network only |
| Prometheus metrics (9145) | Read | Internal network |
| Container registry | Admin | Authenticated push/pull |

### 3.3 Restricted Resources

Resources with strict access controls.

| Resource | Access Level | Required Access |
|----------|--------------|-----------------|
| TLS private keys | Admin | File permissions only |
| Configuration files | Admin | Admin + file permissions |
| Audit logs | Read | Admin approval |
| Backup data | Admin | Encrypted, admin only |

---

## 4. User Roles

### 4.1 Role Definitions

| Role | Description | Typical Users |
|------|-------------|---------------|
| User | Application access only | End users |
| Operator | Monitoring and basic troubleshooting | On-call staff |
| Developer | Application deployment and debugging | Development team |
| Administrator | Full system access | System administrators |
| Security | Security audit and policy management | Security team |

### 4.2 Role Permissions Matrix

| Resource | User | Operator | Developer | Administrator | Security |
|----------|------|----------|-----------|---------------|----------|
| Application access | R | R | R | R | R |
| View logs | - | R | R | R | R |
| View metrics | - | R | R | R | R |
| Configure alerts | - | - | R | RW | R |
| Deploy containers | - | - | RW | RW | - |
| Gateway config | - | - | R | RW | R |
| User management | - | - | - | RW | R |
| Security config | - | - | - | RW | RW |

R = Read, W = Write, RW = Read/Write, - = No access

---

## 5. Network Access Control

### 5.1 IP-based Restrictions

#### Gateway API (8080)

The internal API is restricted to the Nebula network:

```nginx
# Nebula network only
allow 10.100.0.0/16;
deny all;
```

#### Management Interfaces

Management interfaces should be restricted to administrator IPs:

```nginx
# Admin access example
location /admin {
    allow 192.168.1.10;  # Admin workstation
    allow 192.168.1.11;  # Backup admin
    deny all;
}
```

#### Metrics Endpoint

Metrics should be accessible from the monitoring system:

```nginx
server {
    listen 9145;

    location /metrics {
        allow 192.168.1.100;  # Prometheus server
        allow 10.100.0.0/16;  # Nebula network
        deny all;
    }
}
```

### 5.2 Recommended IP Allowlists

| Service | Allowed Networks | Purpose |
|---------|-----------------|---------|
| Gateway HTTP (80/443) | Corporate LAN | User access |
| Gateway API (8080) | Nebula network (10.100.0.0/16) | Internal API |
| Prometheus (9145) | Monitoring network | Metrics scraping |
| SSH (22) | Admin workstations | System administration |

---

## 6. Authentication Methods

### 6.1 Application Authentication

Each application behind the Gateway manages its own authentication:

| Application | Method | Notes |
|-------------|--------|-------|
| Forgejo | Username/Password | Built-in authentication |
| Grafana | Username/Password | LDAP optional |
| Prometheus | None/Basic | IP restriction preferred |

### 6.2 Gateway Authentication

For administrative endpoints, use Basic Authentication or IP restriction:

```nginx
# Basic Authentication
location /admin {
    auth_basic "Admin Area";
    auth_basic_user_file /etc/nginx/.htpasswd;
}
```

Generate htpasswd file:
```bash
# Install apache2-utils
apt install apache2-utils

# Create password file
htpasswd -c /etc/nginx/.htpasswd admin
```

### 6.3 SSH Access

SSH access to WSL2 should use key-based authentication:

```bash
# Disable password authentication
# /etc/ssh/sshd_config
PasswordAuthentication no
PubkeyAuthentication yes
```

---

## 7. Access Request Procedures

### 7.1 New Access Request

1. **Requester** submits access request including:
   - Requested resource(s)
   - Required access level (read/write/admin)
   - Business justification
   - Duration (permanent or temporary)

2. **Approver** (resource owner or manager) reviews and approves/denies

3. **Administrator** implements access if approved

4. **Requester** confirms access is working

### 7.2 Access Review

Access should be reviewed:
- Quarterly for all users
- Immediately upon role change
- Immediately upon termination

### 7.3 Access Revocation

1. **Trigger**: Termination, role change, or access review
2. **Administrator** removes access
3. **Audit** log entry created
4. **Verification** that access is revoked

---

## 8. Service Account Management

### 8.1 Service Account Principles

- Each service has its own dedicated account
- Service accounts should not be shared between services
- Service accounts should have minimum required permissions

### 8.2 Service Account Inventory

| Service | Account | Purpose | Owner |
|---------|---------|---------|-------|
| Prometheus | prometheus | Metrics scraping | Ops team |
| Grafana | grafana | Dashboard access | Ops team |
| CNI Plugin | flatnet-cni | Container network | Platform team |

### 8.3 Credential Rotation

| Credential Type | Rotation Period | Procedure |
|-----------------|-----------------|-----------|
| User passwords | 90 days | Self-service reset |
| Service passwords | 180 days | Coordinated rotation |
| API keys | 365 days | Key regeneration |
| TLS certificates | Before expiry | Certificate renewal |

---

## 9. Audit and Monitoring

### 9.1 Access Logging

All access should be logged including:
- Timestamp
- Source IP
- User identity (if authenticated)
- Resource accessed
- Action performed
- Success/failure

### 9.2 Log Retention

| Log Type | Retention Period | Storage |
|----------|-----------------|---------|
| Access logs | 90 days | Local + Loki |
| Authentication logs | 1 year | Secure storage |
| Administrative actions | 2 years | Secure storage |

### 9.3 Alerting

Alerts should be configured for:
- Multiple failed authentication attempts
- Access from unusual locations
- Administrative actions outside business hours
- Access to sensitive resources

---

## 10. Compliance Checklist

- [ ] All users have documented role assignments
- [ ] Access requests follow documented procedure
- [ ] Service accounts are inventoried
- [ ] IP restrictions are configured for admin interfaces
- [ ] Authentication is enabled for management interfaces
- [ ] Access logs are retained per policy
- [ ] Regular access reviews are performed
- [ ] Access is revoked promptly when no longer needed

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | | | Initial version |

**Approved by:** ___________________ Date: ___________

---

## Related Documents

- [Security Audit Checklist](./audit-checklist.md) - Checklist for performing audits
- [Incident Response Procedures](./incident-response.md) - Procedures for handling security incidents
- [TLS Setup Guide](./tls-setup.md) - TLS certificate configuration for secure communications
