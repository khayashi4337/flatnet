# Flatnet Incident Response Procedures

## 1. Overview

This document defines the incident response procedures for security incidents affecting the Flatnet system. All team members should be familiar with these procedures before an incident occurs.

## 2. Contact Information

### 2.1 Incident Response Team

| Role | Name | Email | Phone |
|------|------|-------|-------|
| Incident Commander | TBD | | |
| Technical Lead | TBD | | |
| Communications Lead | TBD | | |

### 2.2 Escalation Contacts

| Level | Contact | When to Escalate |
|-------|---------|------------------|
| L1 | On-call engineer | Initial response |
| L2 | Technical Lead | L1 cannot resolve in 30 min |
| L3 | Incident Commander | Critical severity or extended outage |
| Management | Department Head | Critical severity or data breach |

---

## 3. Incident Classification

### 3.1 Severity Levels

| Severity | Definition | Response Time | Examples |
|----------|------------|---------------|----------|
| **Critical** | Complete service outage or confirmed security breach | 15 minutes | Data breach, ransomware, complete Gateway failure |
| **High** | Significant service degradation or potential security issue | 1 hour | Partial outage, suspicious activity, vulnerability exploitation |
| **Medium** | Limited impact or security anomaly | 4 hours | Single component failure, failed intrusion attempt |
| **Low** | Minimal impact, informational | Next business day | Minor misconfiguration, policy violation |

### 3.2 Incident Categories

| Category | Description | Examples |
|----------|-------------|----------|
| Availability | Service not functioning | Gateway down, container crash |
| Integrity | Data or system modified | Unauthorized config change |
| Confidentiality | Data exposure | Log leak, credential exposure |
| Compliance | Policy violation | Unauthorized access, audit failure |

---

## 4. Incident Response Phases

### Phase 1: Detection and Reporting

**Objective:** Identify and report potential incidents

**Activities:**
1. Monitor alerts from Prometheus/Grafana
2. Review security logs for anomalies
3. Receive reports from users or external parties

**Reporting:**
- Any team member can report an incident
- Report via: [incident reporting channel/system]
- Include: What happened, when, what systems affected

**Initial Assessment Questions:**
- Is this a security incident or operational issue?
- What systems are affected?
- Is there ongoing unauthorized access?
- Is data at risk?

---

### Phase 2: Containment

**Objective:** Limit the scope and impact of the incident

**Immediate Containment (Critical/High):**

1. **Network Isolation** (if needed):
```bash
# Block suspicious IP at Windows Firewall
netsh advfirewall firewall add rule name="Block Suspicious IP" dir=in action=block remoteip=X.X.X.X

# Or restart Gateway with restricted config
Stop-Service OpenResty
# Update config to restrict access
Start-Service OpenResty
```

2. **Stop Affected Containers**:
```bash
# Identify affected container
podman ps

# Stop container
podman stop <container_id>
```

3. **Disable Compromised Accounts**:
```bash
# Disable Forgejo user (example)
podman exec forgejo gitea admin user disable --username <username>
```

4. **Preserve Evidence** (before making changes):
```bash
# Copy logs
cp /var/log/nginx/access.log /secure/evidence/access.log.$(date +%Y%m%d_%H%M%S)

# Capture container state
podman inspect <container_id> > /secure/evidence/container_state.json
```

**Short-term Containment:**
- Apply emergency patches
- Implement additional monitoring
- Restrict access to affected systems

---

### Phase 3: Investigation

**Objective:** Determine root cause and full scope

**Data Collection:**

1. **Log Analysis**:
```bash
# Gateway access logs
grep -E "suspicious_pattern" /var/log/nginx/access.log

# Authentication failures
grep -i "auth" /var/log/nginx/error.log

# Container logs
podman logs <container_id> > container_logs.txt
```

2. **Timeline Construction**:
- First indication of incident
- All affected systems/data
- Actions taken by responders
- Actions taken by attacker (if applicable)

3. **Scope Determination**:
- Which systems were accessed?
- What data was affected?
- Was data exfiltrated?
- Are other systems at risk?

**Investigation Checklist:**
- [ ] Logs collected and preserved
- [ ] Timeline documented
- [ ] Attack vector identified
- [ ] Scope determined
- [ ] Root cause identified

---

### Phase 4: Eradication

**Objective:** Remove the threat and fix vulnerabilities

**Activities:**

1. **Remove Malicious Artifacts**:
```bash
# Remove unauthorized files
rm /path/to/malicious/file

# Verify file integrity
sha256sum /path/to/expected/file
```

2. **Patch Vulnerabilities**:
```bash
# Update container images
podman pull new-image:patched

# Restart with patched image
podman stop old-container
podman run ... new-image:patched
```

3. **Reset Credentials**:
```bash
# Rotate affected credentials
# Update configuration files
# Restart services
```

4. **Verify Clean State**:
- Run vulnerability scans
- Verify configurations
- Check for persistence mechanisms

---

### Phase 5: Recovery

**Objective:** Restore normal operations safely

**Recovery Steps:**

1. **Restore from Backup** (if needed):
```bash
# Restore data
# Verify integrity
# Test functionality
```

2. **Gradual Restoration**:
- Start services in controlled manner
- Monitor closely for recurrence
- Verify all components functional

3. **Validation**:
- [ ] All services operational
- [ ] Security controls in place
- [ ] Monitoring active
- [ ] No signs of recurring incident

**Recovery Checklist:**
- [ ] Systems restored to known good state
- [ ] All patches applied
- [ ] Credentials rotated where needed
- [ ] Additional monitoring in place
- [ ] Stakeholders notified of restoration

---

### Phase 6: Lessons Learned

**Objective:** Improve security posture and incident response

**Post-Incident Review:**
- Conduct within 5 business days of resolution
- All responders should participate
- Document findings

**Review Questions:**
1. What happened and when?
2. How was the incident detected?
3. What was the root cause?
4. What worked well in the response?
5. What could be improved?
6. What follow-up actions are needed?

**Documentation:**
- Create incident report
- Update runbooks if needed
- File lessons learned
- Track remediation items

---

## 5. Communication Templates

### 5.1 Initial Internal Notification

```
Subject: [SEVERITY] Security Incident - [Brief Description]

Incident ID: INC-YYYY-NNNN
Severity: Critical/High/Medium/Low
Status: Investigating/Contained/Resolved

Summary:
[Brief description of what happened]

Impact:
[Systems/users affected]

Current Status:
[What is being done]

Next Update:
[When to expect next update]

Incident Commander: [Name]
```

### 5.2 Status Update

```
Subject: Update - [Incident ID] - [Status]

Status: [Investigating/Contained/Resolved]

Since last update:
- [Action taken]
- [Finding]

Current status:
[Current situation]

Next steps:
- [Planned action]

ETA for resolution: [Time estimate]

Next update: [Time]
```

### 5.3 Resolution Notice

```
Subject: RESOLVED - [Incident ID]

The incident has been resolved.

Summary:
[What happened]

Root Cause:
[Brief root cause]

Resolution:
[How it was fixed]

Duration:
Start: [Time]
End: [Time]
Total: [Duration]

Post-incident review scheduled: [Date/Time]
```

---

## 6. Specific Incident Runbooks

### 6.1 Gateway Compromise

1. Stop OpenResty immediately
2. Preserve all logs
3. Check for configuration changes
4. Scan system for malware
5. Restore from known good configuration
6. Restart with additional monitoring

### 6.2 Container Breakout

1. Stop all containers on affected host
2. Preserve container images and logs
3. Check host for unauthorized changes
4. Scan for lateral movement
5. Rebuild containers from trusted images
6. Review and harden container security

### 6.3 Credential Compromise

1. Disable affected account immediately
2. Rotate all related credentials
3. Review access logs for abuse
4. Check for persistence
5. Notify affected parties
6. Implement additional authentication

### 6.4 Denial of Service

1. Identify attack source/type
2. Implement rate limiting or blocking
3. Scale resources if possible
4. Contact ISP if external attack
5. Preserve attack data for analysis
6. Implement long-term mitigations

---

## 7. Evidence Handling

### 7.1 Evidence Collection

- Use write-once storage where possible
- Create cryptographic hashes of all evidence
- Document chain of custody
- Store in secure location

### 7.2 Evidence Preservation

```bash
# Create evidence directory
mkdir -p /secure/evidence/INC-YYYY-NNNN

# Copy logs with metadata
cp -a /var/log/nginx/* /secure/evidence/INC-YYYY-NNNN/

# Create hash manifest
cd /secure/evidence/INC-YYYY-NNNN
sha256sum * > MANIFEST.sha256

# Sign manifest (if GPG available)
gpg --sign MANIFEST.sha256
```

### 7.3 Chain of Custody Log

| Date/Time | Evidence | Action | Person | Notes |
|-----------|----------|--------|--------|-------|
| | | Collected | | |
| | | Transferred | | |
| | | Analyzed | | |

---

## 8. Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | | | Initial version |

**Review Schedule:** Annually or after major incident

**Approved by:** ___________________ Date: ___________

---

## Related Documents

- [Security Audit Checklist](./audit-checklist.md) - Checklist for performing security audits
- [Audit Report Template](./audit-report-template.md) - Template for documenting audit findings
- [Vulnerability Report Template](./vulnerability-report-template.md) - Template for vulnerability scan reports
- [Access Control Policy](./access-control-policy.md) - Access control guidelines
