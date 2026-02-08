# Flatnet Security Audit Checklist

## Overview

This checklist is used to perform security audits of the Flatnet system. Audits should be performed:
- Before initial production deployment
- After major changes or updates
- Quarterly for regular security reviews

## Audit Information

| Item | Value |
|------|-------|
| Audit Date | YYYY-MM-DD |
| Auditor | |
| Version | |
| Environment | Production / Staging / Development |

---

## 1. Network Security

### 1.1 Port Exposure

- [ ] **Inventory open ports**: Document all listening ports
  - Command: `netstat -tuln` or `ss -tuln`
- [ ] **No unnecessary ports exposed**: Only required ports are listening
- [ ] **Internal ports restricted**: Management ports (9145, 8080) are not exposed externally
- [ ] **WSL2 to Windows firewall**: Verify Windows Firewall rules are appropriate

### 1.2 Network Segmentation

- [ ] **Nebula network isolation**: Internal API accessible only from Nebula network
- [ ] **Container network isolation**: Containers cannot access host network directly
- [ ] **Gateway access control**: Gateway only proxies to authorized backends

### 1.3 Firewall Rules

- [ ] **Windows Firewall configured**: Rules allow only required traffic
- [ ] **UFW/iptables in WSL2**: Appropriate rules if using firewall in WSL2
- [ ] **Podman network rules**: Container traffic appropriately restricted

### 1.4 External Access

- [ ] **Public exposure minimized**: Only Gateway ports exposed to LAN
- [ ] **No direct container access**: Containers not accessible without Gateway
- [ ] **Admin interfaces protected**: Prometheus/Grafana not publicly accessible

---

## 2. Authentication and Authorization

### 2.1 Management Interface Authentication

- [ ] **Grafana authentication enabled**: Default admin password changed
- [ ] **Prometheus UI protected**: IP restriction or authentication configured
- [ ] **Alertmanager UI protected**: Not publicly accessible
- [ ] **Forgejo authentication**: Strong password policy enforced

### 2.2 Default Credentials

- [ ] **No default passwords**: All default credentials changed
- [ ] **Service accounts secured**: Service accounts have strong passwords/keys
- [ ] **API keys rotated**: API keys are unique and rotated regularly

### 2.3 Access Control

- [ ] **Minimum privilege principle**: Users have only required permissions
- [ ] **Admin access limited**: Admin accounts limited to necessary personnel
- [ ] **Guest access disabled**: Anonymous access disabled where not required

### 2.4 Authentication Methods

- [ ] **Strong password policy**: Minimum length, complexity requirements
- [ ] **Session management**: Appropriate session timeouts configured
- [ ] **Failed login handling**: Account lockout or rate limiting enabled

---

## 3. Secret Management

### 3.1 Secret Storage

- [ ] **No plaintext secrets**: Secrets not stored in plaintext in configs
- [ ] **Config file permissions**: Secret files readable only by service users
- [ ] **Environment variables**: Secrets passed via environment where appropriate
- [ ] **Git exclusions**: .env and secret files in .gitignore

### 3.2 Secret Handling

- [ ] **Secrets not in logs**: Sensitive data masked in log output
- [ ] **Debug mode disabled**: Debug logging disabled in production
- [ ] **Memory protection**: Secrets cleared from memory when not needed

### 3.3 Key Management

- [ ] **TLS private keys protected**: Key files have 600 permissions
- [ ] **Key rotation schedule**: Keys rotated according to policy
- [ ] **Backup encryption**: Backup data encrypted at rest

---

## 4. Container Security

### 4.1 Image Security

- [ ] **Base images updated**: Using latest patched base images
- [ ] **Minimal images**: Using minimal base images (alpine, distroless)
- [ ] **No unnecessary packages**: Only required packages installed
- [ ] **Image signing**: Images signed or from trusted sources

### 4.2 Container Runtime

- [ ] **Rootless mode**: Containers running as non-root where possible
- [ ] **No privileged containers**: --privileged flag not used
- [ ] **Capability restrictions**: Unnecessary capabilities dropped
- [ ] **Read-only root filesystem**: Root filesystem read-only where possible

### 4.3 Container Configuration

- [ ] **Resource limits set**: CPU/memory limits configured
- [ ] **No host network**: Containers not using host network mode
- [ ] **Volume mounts minimal**: Only required paths mounted
- [ ] **No sensitive host paths**: /etc, /var not mounted without need

### 4.4 Registry Security

- [ ] **Private registry secure**: Registry requires authentication
- [ ] **Image scanning enabled**: Images scanned before deployment
- [ ] **Vulnerability policy**: High/Critical vulnerabilities blocked

---

## 5. Gateway Security

### 5.1 OpenResty Configuration

- [ ] **Server tokens disabled**: server_tokens off in nginx.conf
- [ ] **Directory listing disabled**: autoindex off
- [ ] **Request size limits**: client_max_body_size configured
- [ ] **Timeout values set**: Appropriate timeouts to prevent slowloris

### 5.2 HTTP Security Headers

- [ ] **X-Content-Type-Options**: nosniff header present
- [ ] **X-Frame-Options**: SAMEORIGIN or DENY header present
- [ ] **X-XSS-Protection**: 1; mode=block header present
- [ ] **Content-Security-Policy**: Appropriate CSP configured
- [ ] **Referrer-Policy**: Appropriate policy set

### 5.3 TLS Configuration

- [ ] **TLS enabled**: HTTPS configured for production
- [ ] **TLS 1.2+ only**: Older protocols disabled
- [ ] **Strong ciphers**: Weak ciphers disabled
- [ ] **HSTS enabled**: Strict-Transport-Security header present
- [ ] **Certificate valid**: Certificate not expired or self-signed in production

### 5.4 Access Logging

- [ ] **Access logs enabled**: All requests logged
- [ ] **Error logs enabled**: Errors captured for debugging
- [ ] **Log rotation configured**: Logs rotated to prevent disk fill
- [ ] **Sensitive data excluded**: Passwords/tokens not in logs

---

## 6. Logging and Monitoring

### 6.1 Log Coverage

- [ ] **All components logging**: Gateway, containers, system logs collected
- [ ] **Security events logged**: Authentication, authorization events captured
- [ ] **Access patterns visible**: Who accessed what, when

### 6.2 Log Security

- [ ] **Log integrity**: Logs protected from tampering
- [ ] **Log retention**: Appropriate retention period configured
- [ ] **Log access restricted**: Only authorized personnel can view logs

### 6.3 Monitoring

- [ ] **Health monitoring**: All components monitored for availability
- [ ] **Alerting configured**: Alerts for security-relevant events
- [ ] **Dashboard access secured**: Grafana/monitoring dashboards protected

---

## 7. Backup and Recovery

### 7.1 Backup Security

- [ ] **Backups encrypted**: Backup data encrypted at rest
- [ ] **Backup access restricted**: Only authorized access to backups
- [ ] **Offsite copies**: Backups stored in separate location

### 7.2 Recovery Testing

- [ ] **Recovery tested**: Restore procedure verified periodically
- [ ] **Recovery time acceptable**: RTO meets requirements
- [ ] **Data integrity verified**: Restored data matches original

---

## 8. Compliance and Documentation

### 8.1 Documentation

- [ ] **Security policies documented**: Access control, incident response documented
- [ ] **Architecture documented**: Network topology and data flows documented
- [ ] **Change management**: Changes tracked and documented

### 8.2 Reviews

- [ ] **Regular security reviews**: Quarterly reviews scheduled
- [ ] **Penetration testing**: Annual pen test if applicable
- [ ] **Vulnerability scanning**: Regular automated scans configured

---

## Findings Summary

### Critical Issues

| Finding | Severity | Status | Remediation |
|---------|----------|--------|-------------|
| | Critical | | |

### High Issues

| Finding | Severity | Status | Remediation |
|---------|----------|--------|-------------|
| | High | | |

### Medium Issues

| Finding | Severity | Status | Remediation |
|---------|----------|--------|-------------|
| | Medium | | |

### Low Issues

| Finding | Severity | Status | Remediation |
|---------|----------|--------|-------------|
| | Low | | |

---

## Sign-off

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Auditor | | | |
| Reviewer | | | |
| System Owner | | | |

---

## Related Documents

- [Audit Report Template](./audit-report-template.md) - Template for documenting audit findings
- [Vulnerability Report Template](./vulnerability-report-template.md) - Template for vulnerability scan reports
- [Incident Response Procedures](./incident-response.md) - Procedures for handling security incidents
- [Access Control Policy](./access-control-policy.md) - Access control guidelines
- [TLS Setup Guide](./tls-setup.md) - TLS certificate configuration
