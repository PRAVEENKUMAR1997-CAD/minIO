# MinIO S3 Platform

A production-quality, security-conscious, developer-friendly MinIO S3 platform for Linux using Docker Compose.

[![Validate](https://github.com/your-org/minio-s3-platform/actions/workflows/validate.yml/badge.svg)](https://github.com/your-org/minio-s3-platform/actions/workflows/validate.yml)

## Overview

This project provides a complete MinIO deployment with:

- ✅ S3-compatible API
- ✅ MinIO Web Console
- ✅ Persistent object storage
- ✅ Admin/root credentials
- ✅ Separate developer user
- ✅ Bucket-level permissions
- ✅ Health checks
- ✅ Bootstrap/initialization
- ✅ Complete documentation

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  MinIO S3 Platform                       │
├─────────────────────────────────────────────────────────┤
│                                                          │
│   ┌──────────────┐         ┌──────────────────────┐     │
│   │  S3 API      │         │  Web Console         │     │
│   │  :9000       │         │  :9001               │     │
│   └──────┬───────┘         └──────────┬───────────┘     │
│          │                            │                  │
│          └────────────┬───────────────┘                  │
│                       │                                  │
│              ┌────────▼────────┐                        │
│              │  MinIO Server   │                        │
│              │  (Container)    │                        │
│              └────────┬────────┘                        │
│                       │                                  │
│              ┌────────▼────────┐                        │
│              │  Docker Volume  │                        │
│              │  (minio_data)   │                        │
│              └─────────────────┘                        │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

## Requirements

| Software | Minimum Version |
|----------|-----------------|
| Docker | 20.10+ |
| Docker Compose | 2.0+ |
| curl | Any |
| bash | 4.0+ |

## MinIO Distribution Model

This project supports multiple deployment strategies:

### Option A: Community Source Build (Default)

Builds MinIO from the official source repository using a multi-stage Dockerfile.

```bash
./scripts/start.sh
```

**Current pinned version:** `RELEASE.2024-10-02T17-50-41Z`

### Option B: Docker Hardened Image

Uses `dhi.io/minio` (requires Docker ELS subscription).

```bash
docker compose -f docker-compose.yml -f docker-compose.dhi.yml up -d
```

### Option C: Legacy Image (Testing Only)

⚠️ **NOT recommended for production.** The `minio/minio` Docker Hub repository may be archived.

```bash
docker compose -f docker-compose.yml -f docker-compose.legacy.yml up -d
```

## Quick Start

### 1. Configure Environment

```bash
cp .env.example .env
# Edit .env with your configuration
```

**Required settings:**
```bash
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=YourStrongPassword123!
MINIO_DEVELOPER_USER=developer
MINIO_DEVELOPER_PASSWORD=DevPassword123!
```

### 2. Start Services

```bash
./scripts/start.sh
```

### 3. Initialize (Bootstrap)

```bash
./scripts/bootstrap.sh
```

### 4. Access MinIO

| Service | URL |
|---------|-----|
| Web Console | http://127.0.0.1:9001 |
| S3 API | http://127.0.0.1:9000 |

## Configuration

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

### Network Binding

**Localhost only (default, most secure):**
```bash
MINIO_BIND_ADDRESS=127.0.0.1
```

**All interfaces (remote access):**
```bash
MINIO_BIND_ADDRESS=0.0.0.0
```

⚠️ **Warning:** Binding to `0.0.0.0` exposes MinIO to the network. Use only with proper firewall and TLS configuration.

## Credentials

### User Types

| Type | Purpose | Console | S3 API |
|------|---------|---------|--------|
| Root | Administration | ✅ | ⚠️ (not recommended) |
| Developer | Application access | ✅ | ✅ |
| Access Key | Service authentication | ❌ | ✅ |

### Creating Access Keys

```bash
./scripts/bootstrap.sh --create-access-key
```

**Important:** Never use root credentials in applications.

## Console Access

1. Navigate to http://127.0.0.1:9001
2. Login with configured credentials
3. Browse buckets, upload/download objects

### Root vs Developer Login

| User | Capabilities |
|------|-------------|
| Root | Full admin, all buckets, user management |
| Developer | Configured bucket only, no admin |

## S3 API

### Endpoint

```
http://127.0.0.1:9000
```

### Default Bucket

```
developer-data
```

## AWS CLI Integration

### Configure

```bash
aws configure
# Access Key ID: <developer or access key>
# Secret Access Key: <password or secret>
# Region: us-east-1
```

### Usage

```bash
# List buckets
aws --endpoint-url http://localhost:9000 s3 ls

# List bucket contents
aws --endpoint-url http://localhost:9000 s3 ls s3://developer-data/

# Upload file
aws --endpoint-url http://localhost:9000 s3 cp test.txt s3://developer-data/

# Download file
aws --endpoint-url http://localhost:9000 s3 cp s3://developer-data/test.txt ./

# Delete file
aws --endpoint-url http://localhost:9000 s3 rm s3://developer-data/test.txt
```

## Spring Boot Integration

### Dependencies (Maven)

```xml
<dependency>
    <groupId>software.amazon.awssdk</groupId>
    <artifactId>s3</artifactId>
</dependency>
```

### Configuration

```yaml
minio:
  endpoint: http://localhost:9000
  region: us-east-1
  bucket: developer-data
```

### S3 Client

```java
S3Client s3Client = S3Client.builder()
    .endpointOverride(URI.create("http://localhost:9000"))
    .region(Region.of("us-east-1"))
    .credentialsProvider(StaticCredentialsProvider.create(
        AwsBasicCredentials.create(accessKey, secretKey)
    ))
    .serviceConfiguration(S3Configuration.builder()
        .pathStyleAccessEnabled(true)
        .build())
    .build();
```

See [docs/integration.md](docs/integration.md) for complete examples.

## Persistence

Data is stored in Docker named volume `minio_data`.

| Command | Volume Behavior |
|---------|-----------------|
| `docker compose down` | **Preserved** |
| `docker compose down -v` | **Deleted** |
| `./scripts/stop.sh` | **Preserved** |
| `./scripts/reset.sh` | **Deleted** (with confirmation) |

## Backup

### Volume Backup

```bash
./scripts/stop.sh

docker run --rm \
  -v minio_data:/data:ro \
  -v "$(pwd)/backup:/backup" \
  alpine \
  tar czf /backup/minio-data-$(date +%Y%m%d).tar.gz -C /data .

./scripts/start.sh
```

### Object-Level Backup

```bash
docker run --rm --network host \
  -v "$(pwd)/backup:/backup" \
  -e MC_HOST_local="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:9000" \
  minio/mc mirror local/ /backup/
```

See [docs/backup-restore.md](docs/backup-restore.md) for complete procedures.

## Restore

```bash
./scripts/stop.sh
docker volume rm minio_data
docker volume create minio_data

docker run --rm \
  -v minio_data:/data \
  -v "$(pwd)/backup:/backup" \
  alpine \
  tar xzf /backup/minio-data-YYYYMMDD.tar.gz -C /data

./scripts/start.sh
```

## Security

### Checklist

- [ ] Strong passwords (12+ characters)
- [ ] `.env` file permissions (`chmod 600`)
- [ ] Network binding reviewed
- [ ] Applications using access keys, not root
- [ ] TLS configured (production)
- [ ] Firewall configured (remote access)

### TLS / Reverse Proxy

For production, place MinIO behind a reverse proxy with TLS:

```
Internet → HTTPS → Nginx → HTTP → MinIO
```

Configure in `.env`:
```bash
MINIO_SERVER_URL=https://s3.example.com
MINIO_BROWSER_REDIRECT_URL=https://console.example.com
```

See [docs/security.md](docs/security.md) for complete security guidance.

## Upgrade

1. Backup data
2. Update version in `Dockerfile`
3. Build new image
4. Restart services
5. Verify health

```bash
# Backup
./scripts/stop.sh
# ... backup commands ...

# Update Dockerfile version
# ARG MINIO_VERSION=RELEASE.2024-xx-xx...

# Upgrade
docker compose build --no-cache
./scripts/start.sh
./scripts/health-check.sh
```

See [docs/upgrade.md](docs/upgrade.md) for complete procedures.

## Rollback

```bash
# Revert Dockerfile
git checkout HEAD~1 -- Dockerfile

# Rebuild and restart
docker compose build --no-cache
./scripts/start.sh
```

If data restore is needed, follow backup/restore procedures.

## Troubleshooting

### Container Won't Start

```bash
docker compose logs minio
```

### Health Check Fails

```bash
./scripts/health-check.sh
curl -v http://localhost:9000/minio/health/live
```

### Permission Denied

```bash
docker exec minio-server ls -la /data
```

### View Logs

```bash
docker compose logs -f minio
```

## Limitations

⚠️ **Single-Node Deployment**

This deployment does **NOT** provide:

- High availability
- Erasure coding
- Automatic failover
- Data redundancy

**For production requiring HA:**
- Deploy distributed MinIO (4+ nodes)
- Configure erasure coding
- Implement proper backup strategy
- Use external monitoring

## Project Structure

```
minio-s3-platform/
├── docker-compose.yml          # Main deployment
├── docker-compose.dhi.yml      # DHI override
├── docker-compose.legacy.yml   # Legacy override
├── Dockerfile                  # Multi-stage build
├── .dockerignore
├── .env.example
├── .gitignore
├── README.md
│
├── config/
│   ├── policies/
│   │   └── developer-policy.json
│   └── lifecycle/
│       └── bucket-lifecycle.json
│
├── scripts/
│   ├── bootstrap.sh
│   ├── create-user.sh
│   ├── create-bucket.sh
│   ├── health-check.sh
│   ├── start.sh
│   ├── stop.sh
│   └── reset.sh
│
├── docs/
│   ├── architecture.md
│   ├── setup.md
│   ├── credentials.md
│   ├── security.md
│   ├── backup-restore.md
│   ├── upgrade.md
│   └── integration.md
│
└── .github/
    └── workflows/
        └── validate.yml
```

## Commands Reference

| Command | Description |
|---------|-------------|
| `./scripts/start.sh` | Build, start, and verify |
| `./scripts/stop.sh` | Stop services (preserve data) |
| `./scripts/reset.sh` | Delete everything (requires confirmation) |
| `./scripts/health-check.sh` | Verify health status |
| `./scripts/bootstrap.sh` | Initialize bucket and users |
| `./scripts/create-user.sh` | Create additional users |
| `./scripts/create-bucket.sh` | Create additional buckets |

## Documentation

- [Architecture](docs/architecture.md)
- [Setup Guide](docs/setup.md)
- [Credentials](docs/credentials.md)
- [Security](docs/security.md)
- [Backup & Restore](docs/backup-restore.md)
- [Upgrade](docs/upgrade.md)
- [Integration](docs/integration.md)

## License

This project configuration is provided as-is. MinIO is licensed under AGPL-3.0.
