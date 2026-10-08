# MinIO S3 Platform - Security Guide

## Security Overview

This guide covers security considerations for the MinIO S3 Platform deployment.

## Security Checklist

### Pre-Deployment

- [ ] Strong root password (12+ characters, mixed case, numbers, symbols)
- [ ] Strong developer password
- [ ] `.env` file permissions restricted (`chmod 600`)
- [ ] `.env` not committed to version control
- [ ] Network binding reviewed

### Post-Deployment

- [ ] Bootstrap completed with separate developer user
- [ ] Applications using access keys, not root credentials
- [ ] Health checks passing
- [ ] Firewall configured (if remote access needed)
- [ ] Backup strategy defined

### Production Readiness

- [ ] TLS configured (via reverse proxy)
- [ ] Reverse proxy in place
- [ ] Access logging enabled
- [ ] Credential rotation schedule defined
- [ ] Monitoring configured
- [ ] Disaster recovery plan documented

## Credential Security

### Root Credentials

**Requirements:**
- Minimum 12 characters
- Mixed case letters
- Numbers
- Special characters
- Unique (not used elsewhere)

**Never:**
- Use in applications
- Share with developers
- Commit to version control
- Log or print

### Application Credentials

**Best Practice:** Use access keys (service accounts) for applications.

```bash
# Create access key for application
./scripts/bootstrap.sh --create-access-key
```

**Benefits:**
- Can be rotated independently
- Can be revoked without affecting user
- Granular audit trail

### Secret Management

For production environments, use a secrets manager:

| Solution | Use Case |
|----------|----------|
| HashiCorp Vault | Enterprise secret management |
| AWS Secrets Manager | AWS-integrated deployments |
| Azure Key Vault | Azure-integrated deployments |
| Kubernetes Secrets | Kubernetes deployments |
| Docker Secrets | Docker Swarm deployments |

## Network Security

### Default Configuration (Localhost Only)

```bash
MINIO_BIND_ADDRESS=127.0.0.1
```

- Only accessible from the host machine
- Most secure for development
- No network exposure

### Remote Access Configuration

```bash
MINIO_BIND_ADDRESS=0.0.0.0
```

**Warning:** This exposes MinIO to the network.

**Required safeguards:**
1. Firewall rules
2. Reverse proxy with TLS
3. Strong credentials
4. Network segmentation

### Firewall Configuration

**Allow only necessary traffic:**

```bash
# Example: UFW (Ubuntu)
# Allow only from specific IP
sudo ufw allow from 192.168.1.100 to any port 9000
sudo ufw allow from 192.168.1.100 to any port 9001

# Or allow from subnet
sudo ufw allow from 192.168.1.0/24 to any port 9000
sudo ufw allow from 192.168.1.0/24 to any port 9001
```

**Never:**
- Open ports to `0.0.0.0/0` (entire internet)
- Expose MinIO directly to the internet without TLS

## TLS / HTTPS

### Why TLS is Required

Without TLS:
- Credentials transmitted in plain text
- Data transmitted in plain text
- Vulnerable to MITM attacks
- Not suitable for production

### Recommended Architecture

```
     Internet
         │
         ▼
  ┌──────────────┐
  │   Firewall   │
  └──────┬───────┘
         │
         ▼
  ┌──────────────┐
  │ Load Balancer│  ◄── TLS Termination
  │  (HTTPS)     │      (Certificate)
  └──────┬───────┘
         │ HTTP (internal)
         ▼
  ┌──────────────┐
  │    MinIO     │
  │ (localhost)  │
  └──────────────┘
```

### Reverse Proxy Example (Nginx)

```nginx
upstream minio_s3 {
    server 127.0.0.1:9000;
}

upstream minio_console {
    server 127.0.0.1:9001;
}

server {
    listen 443 ssl http2;
    server_name s3.example.com;
    
    ssl_certificate /etc/ssl/certs/s3.example.com.crt;
    ssl_certificate_key /etc/ssl/private/s3.example.com.key;
    
    # Modern TLS configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;
    
    # S3 API
    location / {
        proxy_pass http://minio_s3;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Required for large uploads
        client_max_body_size 0;
        proxy_buffering off;
    }
}

server {
    listen 443 ssl http2;
    server_name console.example.com;
    
    ssl_certificate /etc/ssl/certs/console.example.com.crt;
    ssl_certificate_key /etc/ssl/private/console.example.com.key;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;
    
    # Console
    location / {
        proxy_pass http://minio_console;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support for console
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

### MinIO URL Configuration

When behind a reverse proxy, configure:

```bash
# .env
MINIO_SERVER_URL=https://s3.example.com
MINIO_BROWSER_REDIRECT_URL=https://console.example.com
```

## Access Control

### Policy Design

Follow the principle of least privilege:

| User Type | Access Level |
|-----------|--------------|
| Root | Full access (admin tasks only) |
| Developer | Specific buckets only |
| Application | Specific operations only |

### Developer Policy Example

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::developer-data",
        "arn:aws:s3:::developer-data/*"
      ]
    }
  ]
}
```

### What Developers Cannot Do

- Create/delete buckets
- Manage users
- Manage policies
- Access other buckets
- View server configuration

## Audit and Logging

### Container Logs

```bash
# View logs
docker compose logs minio

# Follow logs
docker compose logs -f minio

# Save logs
docker compose logs minio > minio.log
```

### MinIO Audit Logging

For production, configure audit logging:

```bash
# .env (add these)
MINIO_AUDIT_WEBHOOK_ENABLE=on
MINIO_AUDIT_WEBHOOK_ENDPOINT=http://audit-service:8080/audit
```

### What to Monitor

- Failed authentication attempts
- Unauthorized access attempts
- Large data transfers
- Unusual access patterns
- Credential usage

## Data Protection

### Encryption at Rest

MinIO supports server-side encryption. For production:

```bash
# Environment variable for encryption
MINIO_KMS_SECRET_KEY=my-minio-key:$(cat /dev/urandom | head -c 32 | base64)
```

### Encryption in Transit

- Use TLS (via reverse proxy)
- Never expose HTTP to untrusted networks

### Backup Security

- Encrypt backups
- Store backups securely
- Test restore procedures
- Limit backup access

## Container Security

### Non-Root User

The Dockerfile runs MinIO as a non-root user:

```dockerfile
USER minio
```

### Security Options

Docker Compose includes:

```yaml
security_opt:
  - no-new-privileges:true
```

### Read-Only Root Filesystem

For enhanced security (optional):

```yaml
services:
  minio:
    read_only: true
    tmpfs:
      - /tmp
```

## Common Vulnerabilities

### Credential Exposure

| Risk | Mitigation |
|------|------------|
| Credentials in code | Use environment variables |
| Credentials in logs | Configure log filtering |
| Credentials in version control | Use .gitignore, secrets scanner |
| Weak passwords | Enforce password policy |

### Network Exposure

| Risk | Mitigation |
|------|------------|
| Public exposure | Bind to localhost |
| Unencrypted traffic | Use TLS |
| Open ports | Firewall rules |
| MITM attacks | TLS with valid certificates |

### Access Control

| Risk | Mitigation |
|------|------------|
| Excessive permissions | Least privilege policies |
| Shared credentials | Per-application access keys |
| Stale credentials | Regular rotation |
| Root usage in apps | Use service accounts |

## Security Incident Response

### If Credentials Are Compromised

1. **Immediately:**
   - Rotate affected credentials
   - Revoke compromised access keys
   - Check audit logs

2. **Assess:**
   - Identify what was accessed
   - Determine scope of exposure
   - Check for unauthorized changes

3. **Remediate:**
   - Update all affected systems
   - Implement additional controls
   - Document incident

### If Data Is Exposed

1. **Contain:**
   - Disable affected access
   - Isolate affected systems

2. **Assess:**
   - Identify affected data
   - Determine how exposure occurred

3. **Report:**
   - Follow organizational procedures
   - Notify affected parties if required

## Related Documentation

- [Credentials](credentials.md)
- [Architecture](architecture.md)
- [Backup and Restore](backup-restore.md)
