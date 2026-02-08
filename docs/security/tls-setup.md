# Flatnet TLS Configuration Guide

## Overview

This guide covers TLS/HTTPS configuration for the Flatnet Gateway (OpenResty on Windows). TLS encryption is essential for protecting data in transit and should be enabled for any production deployment.

## Table of Contents

1. [Certificate Options](#1-certificate-options)
2. [Self-Signed Certificate Generation](#2-self-signed-certificate-generation)
3. [OpenResty TLS Configuration](#3-openresty-tls-configuration)
4. [TLS Best Practices](#4-tls-best-practices)
5. [Testing and Verification](#5-testing-and-verification)
6. [Troubleshooting](#6-troubleshooting)

---

## 1. Certificate Options

### 1.1 Self-Signed Certificates (Development/Internal)

- **Use Case:** Development, testing, internal-only services
- **Pros:** Free, quick to generate, no external dependencies
- **Cons:** Browser warnings, requires manual trust configuration
- **Validity:** Configurable (typically 365 days)

### 1.2 Internal CA (Enterprise)

- **Use Case:** Enterprise environments with existing PKI
- **Pros:** Trusted by corporate devices, central management
- **Cons:** Requires PKI infrastructure
- **Validity:** Per CA policy

### 1.3 Let's Encrypt (Public-Facing)

- **Use Case:** Publicly accessible services
- **Pros:** Free, trusted by all browsers, automated renewal
- **Cons:** Requires public DNS, 90-day validity
- **Note:** Not typically applicable for internal/WSL2 services

---

## 2. Self-Signed Certificate Generation

### 2.1 Using the Provided Script

The simplest method is to use the provided script:

```bash
# From WSL2
/home/kh/prj/flatnet/scripts/security/generate-cert.sh

# Or from PowerShell
wsl /home/kh/prj/flatnet/scripts/security/generate-cert.sh
```

### 2.2 Manual Generation (WSL2)

```bash
# Create certificate directory with restricted permissions
mkdir -p /mnt/f/flatnet/config/ssl
chmod 700 /mnt/f/flatnet/config/ssl

# Generate private key and certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /mnt/f/flatnet/config/ssl/server.key \
  -out /mnt/f/flatnet/config/ssl/server.crt \
  -subj "/CN=flatnet.local/O=Flatnet/C=JP"

# Set appropriate permissions
# Private key: owner read/write only (CRITICAL for security)
chmod 600 /mnt/f/flatnet/config/ssl/server.key
# Certificate: world-readable (public information)
chmod 644 /mnt/f/flatnet/config/ssl/server.crt
```

**Important:** Private key permissions are critical. The key file should only be readable by the user running OpenResty. A world-readable private key compromises all TLS security.

### 2.3 Certificate with Subject Alternative Names

For certificates with multiple hostnames:

```bash
# Create OpenSSL config file
cat > /tmp/openssl.cnf << 'EOF'
[req]
default_bits = 2048
distinguished_name = req_distinguished_name
req_extensions = v3_req
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = JP
O = Flatnet
CN = flatnet.local

[v3_req]
subjectAltName = @alt_names
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment

[alt_names]
DNS.1 = flatnet.local
DNS.2 = localhost
DNS.3 = *.flatnet.local
IP.1 = 127.0.0.1
IP.2 = 192.168.1.100
EOF

# Generate certificate with SANs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /mnt/f/flatnet/config/ssl/server.key \
  -out /mnt/f/flatnet/config/ssl/server.crt \
  -config /tmp/openssl.cnf
```

### 2.4 Trusting Self-Signed Certificates

#### Windows

```powershell
# Import certificate to Trusted Root (requires admin)
Import-Certificate -FilePath "F:\flatnet\config\ssl\server.crt" `
  -CertStoreLocation Cert:\LocalMachine\Root
```

#### Firefox

1. Navigate to https://flatnet.local
2. Click "Advanced" > "Accept the Risk and Continue"
3. Or import via Settings > Privacy & Security > Certificates > View Certificates > Import

---

## 3. OpenResty TLS Configuration

### 3.1 Example TLS Configuration

Create `config/openresty/conf.d/ssl.conf`:

```nginx
#==============================================================================
# Flatnet Gateway - TLS Configuration
# Phase 4, Stage 3: Security
#==============================================================================

# HTTPS Server
server {
    listen 443 ssl http2;
    server_name flatnet.local;

    #--------------------------------------------------------------------------
    # TLS Certificate Configuration
    #--------------------------------------------------------------------------

    # Certificate and key paths (Windows paths with forward slashes)
    ssl_certificate F:/flatnet/config/ssl/server.crt;
    ssl_certificate_key F:/flatnet/config/ssl/server.key;

    #--------------------------------------------------------------------------
    # TLS Protocol and Cipher Configuration
    #--------------------------------------------------------------------------

    # Modern configuration (TLS 1.2+)
    ssl_protocols TLSv1.2 TLSv1.3;

    # Strong cipher suites
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;

    # Prefer server ciphers (optional, for TLS 1.2)
    ssl_prefer_server_ciphers off;

    #--------------------------------------------------------------------------
    # TLS Session Configuration
    #--------------------------------------------------------------------------

    # Session caching for performance
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    #--------------------------------------------------------------------------
    # Security Headers
    #--------------------------------------------------------------------------

    # HTTP Strict Transport Security (HSTS)
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Other security headers (see security-headers.conf)
    include conf.d/security-headers.conf;

    #--------------------------------------------------------------------------
    # Proxy Configuration
    #--------------------------------------------------------------------------

    location / {
        proxy_pass http://127.0.0.1:3000;
        include conf.d/proxy-params.conf;
    }
}

#==============================================================================
# HTTP to HTTPS Redirect
#==============================================================================

server {
    listen 80;
    server_name flatnet.local;

    # Redirect all HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}
```

### 3.2 Include TLS in Main Configuration

Update `nginx.conf` to include TLS configuration:

```nginx
http {
    # ... other configuration ...

    # Include TLS configuration
    include conf.d/ssl.conf;
}
```

---

## 4. TLS Best Practices

### 4.1 Protocol Configuration

| Protocol | Recommendation | Notes |
|----------|----------------|-------|
| SSL 2.0 | Disable | Insecure, deprecated |
| SSL 3.0 | Disable | Insecure (POODLE) |
| TLS 1.0 | Disable | Deprecated, weak |
| TLS 1.1 | Disable | Deprecated, weak |
| TLS 1.2 | Enable | Widely supported |
| TLS 1.3 | Enable | Recommended |

### 4.2 Cipher Suite Recommendations

**Modern Configuration (Recommended):**
- Supports TLS 1.2 and 1.3
- Strong forward secrecy
- Drops support for older browsers (IE11 on Windows 7, older Android)

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
```

**Intermediate Configuration:**
- For broader compatibility
- Still reasonably secure

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
```

### 4.3 HSTS Configuration

HTTP Strict Transport Security prevents protocol downgrade attacks:

```nginx
# Recommended for production
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
```

**Caution:** Start with a short max-age during testing:
```nginx
# Testing phase
add_header Strict-Transport-Security "max-age=300" always;
```

### 4.4 OCSP Stapling

For public CA certificates (not self-signed):

```nginx
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /path/to/chain.pem;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
```

**Note:** OCSP stapling does not work with self-signed certificates.

### 4.5 DH Parameters (Optional)

For DHE cipher suites, generate strong DH parameters:

```bash
openssl dhparam -out /mnt/f/flatnet/config/ssl/dhparam.pem 2048
```

```nginx
ssl_dhparam F:/flatnet/config/ssl/dhparam.pem;
```

---

## 5. Testing and Verification

### 5.1 Basic Connectivity Test

```bash
# From WSL2
curl -vk https://localhost:443

# Check certificate
openssl s_client -connect localhost:443 -servername flatnet.local </dev/null
```

### 5.2 Protocol and Cipher Testing

```bash
# Check supported protocols
nmap --script ssl-enum-ciphers -p 443 localhost

# Test specific TLS version
openssl s_client -connect localhost:443 -tls1_2
openssl s_client -connect localhost:443 -tls1_3
```

### 5.3 SSL Labs Testing

For publicly accessible endpoints, use SSL Labs:
- https://www.ssllabs.com/ssltest/

### 5.4 testssl.sh

For comprehensive local testing:

```bash
# Install testssl.sh
git clone --depth 1 https://github.com/drwetter/testssl.sh.git

# Run test
./testssl.sh/testssl.sh https://flatnet.local
```

---

## 6. Troubleshooting

### 6.1 Common Issues

#### "Certificate has expired"

- Check certificate expiration: `openssl x509 -noout -dates -in server.crt`
- Regenerate certificate with longer validity

#### "Certificate is not trusted"

- Import certificate to system trust store
- Use proper CA-signed certificate for production

#### "SSL_ERROR_RX_RECORD_TOO_LONG"

- Usually means HTTP traffic sent to HTTPS port
- Check client is using https:// URL

#### "No shared cipher"

- Client and server have no common cipher suites
- Update cipher configuration or client

### 6.2 Debugging Commands

```bash
# View certificate details
openssl x509 -noout -text -in /mnt/f/flatnet/config/ssl/server.crt

# Verify key matches certificate
openssl x509 -noout -modulus -in server.crt | openssl md5
openssl rsa -noout -modulus -in server.key | openssl md5
# (Should output same MD5 hash)

# Check nginx configuration
nginx -t

# Check nginx TLS errors
tail -f /var/log/nginx/error.log | grep -i ssl
```

### 6.3 Windows Path Issues

OpenResty on Windows requires forward slashes or escaped backslashes:

```nginx
# Correct
ssl_certificate F:/flatnet/config/ssl/server.crt;

# Also correct
ssl_certificate "F:\\flatnet\\config\\ssl\\server.crt";

# Incorrect (will fail)
ssl_certificate F:\flatnet\config\ssl\server.crt;
```

---

## References

- [Mozilla SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [OpenSSL Documentation](https://www.openssl.org/docs/)
- [Nginx SSL Module](https://nginx.org/en/docs/http/ngx_http_ssl_module.html)
- [SSL Labs Best Practices](https://github.com/ssllabs/research/wiki/SSL-and-TLS-Deployment-Best-Practices)

---

## Related Documents

- [Security Audit Checklist](./audit-checklist.md) - TLS configuration is part of the security audit
- [Access Control Policy](./access-control-policy.md) - Access control guidelines
- OpenResty TLS Configuration: `config/openresty/conf.d/ssl.conf.example`

## Certificate Generation

Use the provided script to generate certificates:

```bash
scripts/security/generate-cert.sh --help
```
