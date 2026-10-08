# MinIO S3 Platform - Setup Guide

## Prerequisites

### Required Software

| Software | Minimum Version | Purpose |
|----------|-----------------|---------|
| Docker | 20.10+ | Container runtime |
| Docker Compose | 2.0+ | Container orchestration |
| curl | Any | Health checks |
| bash | 4.0+ | Scripts |

### Optional Software

| Software | Purpose |
|----------|---------|
| AWS CLI v2 | S3 API interaction |
| Git | Version control |

### System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 1 core | 2+ cores |
| RAM | 1 GB | 4+ GB |
| Disk | 10 GB | Based on storage needs |

## Quick Start

### 1. Clone or Extract Project

```bash
cd /path/to/minio-s3-platform
```

### 2. Configure Environment

```bash
# Copy example configuration
cp .env.example .env

# Edit configuration
nano .env  # or your preferred editor
```

**Required Configuration:**

```bash
# Strong, unique passwords (minimum 8 characters)
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=YourStrongRootPassword123!

MINIO_DEVELOPER_USER=developer
MINIO_DEVELOPER_PASSWORD=YourDeveloperPassword123!
```

### 3. Start Services

```bash
./scripts/start.sh
```

This will:
1. Validate configuration
2. Build MinIO image from source
3. Start MinIO container
4. Wait for health
5. Display access information

### 4. Run Bootstrap

```bash
./scripts/bootstrap.sh
```

This will:
1. Create default bucket
2. Create developer user
3. Configure access policies

### 5. Access MinIO

- **Console**: http://127.0.0.1:9001
- **S3 API**: http://127.0.0.1:9000

## Deployment Options

### Option A: Build from Source (Default)

Uses the main `docker-compose.yml` to build MinIO from official source.

```bash
./scripts/start.sh
```

**Advantages:**
- Full control over source version
- No external image dependencies
- Reproducible builds

### Option B: Docker Hardened Image

Uses `dhi.io/minio` (requires Docker ELS subscription).

```bash
# Login to dhi.io registry first
docker login dhi.io

# Start with DHI override
docker compose -f docker-compose.yml -f docker-compose.dhi.yml up -d
```

**Prerequisites:**
- Docker ELS entitlement
- Access to dhi.io registry

### Option C: Legacy Docker Hub (Testing Only)

Uses the legacy `minio/minio` image. **Not recommended for production.**

```bash
docker compose -f docker-compose.yml -f docker-compose.legacy.yml up -d
```

**Warning:** The `minio/minio` Docker Hub repository may be archived.

## Configuration Reference

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MINIO_ROOT_USER` | Yes | - | Admin username |
| `MINIO_ROOT_PASSWORD` | Yes | - | Admin password (min 8 chars) |
| `MINIO_DEVELOPER_USER` | No | developer | Developer username |
| `MINIO_DEVELOPER_PASSWORD` | No | - | Developer password |
| `MINIO_DEFAULT_BUCKET` | No | developer-data | Default bucket name |
| `MINIO_API_PORT` | No | 9000 | S3 API port |
| `MINIO_CONSOLE_PORT` | No | 9001 | Console port |
| `MINIO_BIND_ADDRESS` | No | 127.0.0.1 | Network binding |
| `MINIO_REGION` | No | us-east-1 | S3 region |
| `MINIO_SERVER_URL` | No | - | External S3 URL |
| `MINIO_BROWSER_REDIRECT_URL` | No | - | External console URL |

### Network Binding

**Localhost Only (Default - Most Secure):**
```bash
MINIO_BIND_ADDRESS=127.0.0.1
```

**All Interfaces (Remote Access):**
```bash
MINIO_BIND_ADDRESS=0.0.0.0
```

**Warning:** Binding to `0.0.0.0` exposes MinIO to the network. Use only with:
- Proper firewall configuration
- Reverse proxy with TLS
- Network security controls

### Ports

Default port configuration:

| Service | Internal | External |
|---------|----------|----------|
| S3 API | 9000 | MINIO_API_PORT |
| Console | 9001 | MINIO_CONSOLE_PORT |

## Post-Setup Verification

### Check Health

```bash
./scripts/health-check.sh
```

### Test S3 API

```bash
# Configure AWS CLI
aws configure
# Access Key ID: <developer user or access key>
# Secret Access Key: <developer password or secret key>
# Region: us-east-1
# Output format: json

# List buckets
aws --endpoint-url http://127.0.0.1:9000 s3 ls

# Upload file
echo "test" > test.txt
aws --endpoint-url http://127.0.0.1:9000 s3 cp test.txt s3://developer-data/

# Download file
aws --endpoint-url http://127.0.0.1:9000 s3 cp s3://developer-data/test.txt downloaded.txt

# Verify
cat downloaded.txt
```

### Access Console

1. Open http://127.0.0.1:9001
2. Login with root or developer credentials
3. Browse buckets and objects

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker compose logs minio

# Common issues:
# - Invalid credentials format
# - Port already in use
# - Volume permissions
```

### Health Check Fails

```bash
# Manual health check
curl -v http://127.0.0.1:9000/minio/health/live

# Check container status
docker compose ps
docker inspect minio-server
```

### Permission Denied

```bash
# Check volume permissions
docker exec minio-server ls -la /data

# If issues, reset with:
./scripts/reset.sh
./scripts/start.sh
```

### Connection Refused

```bash
# Verify binding address
grep MINIO_BIND_ADDRESS .env

# Check if ports are open
netstat -tlnp | grep -E '9000|9001'
```

## Next Steps

1. [Configure additional users](credentials.md)
2. [Set up application integration](integration.md)
3. [Configure backups](backup-restore.md)
4. [Review security settings](security.md)
