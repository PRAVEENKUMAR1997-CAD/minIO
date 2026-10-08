# MinIO S3 Platform - Upgrade Guide

## Upgrade Philosophy

> **Never use `latest` for production.**
> 
> Always pin to specific versions for:
> - Reproducibility
> - Rollback capability
> - Change tracking

## Pre-Upgrade Checklist

- [ ] Current version documented
- [ ] New version release notes reviewed
- [ ] Breaking changes identified
- [ ] Full backup completed
- [ ] Rollback procedure documented
- [ ] Test environment upgrade successful
- [ ] Maintenance window scheduled

## Version Information

### Current Version

Check Dockerfile for pinned version:

```dockerfile
ARG MINIO_VERSION=RELEASE.2024-10-02T17-50-41Z
```

### Finding New Versions

MinIO releases: https://github.com/minio/minio/releases

Choose releases marked as stable. Review:
- Release notes
- Breaking changes
- Deprecations
- New features

## Upgrade Procedure

### Step 1: Backup

**Mandatory before any upgrade.**

```bash
# Full backup
./scripts/stop.sh

docker run --rm \
  -v minio_data:/data:ro \
  -v "$(pwd)/backup:/backup" \
  alpine \
  tar czf /backup/pre-upgrade-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .

./scripts/start.sh
```

### Step 2: Test in Non-Production

Always test upgrades in a non-production environment first.

```bash
# Create test environment
mkdir minio-upgrade-test
cp -r minio-s3-platform/* minio-upgrade-test/
cd minio-upgrade-test

# Update version in Dockerfile
# Test upgrade
# Verify functionality
```

### Step 3: Update Dockerfile

Edit `Dockerfile`:

```dockerfile
# Before
ARG MINIO_VERSION=RELEASE.2024-10-02T17-50-41Z

# After
ARG MINIO_VERSION=RELEASE.2024-11-01T00-00-00Z  # New version
```

Update OCI labels:

```dockerfile
LABEL org.opencontainers.image.version="RELEASE.2024-11-01T00-00-00Z"
```

### Step 4: Build New Image

```bash
# Build without cache
docker compose build --no-cache
```

### Step 5: Perform Upgrade

```bash
# Stop current version
./scripts/stop.sh

# Start with new version
docker compose up -d

# Monitor startup
docker compose logs -f minio
```

### Step 6: Verify Upgrade

```bash
# Check health
./scripts/health-check.sh

# Verify version
docker exec minio-server minio --version

# Test S3 operations
aws --endpoint-url http://localhost:9000 s3 ls
aws --endpoint-url http://localhost:9000 s3 ls s3://developer-data/

# Test console access
# Open http://localhost:9001
```

### Step 7: Post-Upgrade Tasks

```bash
# Clean up old images
docker image prune -f

# Document upgrade
echo "Upgraded to RELEASE.2024-11-01T00-00-00Z on $(date)" >> CHANGELOG.md
```

## Rollback Procedure

If issues occur after upgrade:

### Quick Rollback

```bash
# Stop new version
./scripts/stop.sh

# Revert Dockerfile to previous version
git checkout HEAD~1 -- Dockerfile

# Rebuild previous version
docker compose build --no-cache

# Start previous version
docker compose up -d

# Verify
./scripts/health-check.sh
```

### Rollback with Data Restore

If data is corrupted:

```bash
# Stop MinIO
./scripts/stop.sh

# Remove current volume
docker volume rm minio_data

# Create new volume
docker volume create minio_data

# Restore from pre-upgrade backup
docker run --rm \
  -v minio_data:/data \
  -v "$(pwd)/backup:/backup" \
  alpine \
  tar xzf /backup/pre-upgrade-YYYYMMDD-HHMMSS.tar.gz -C /data

# Revert Dockerfile
git checkout HEAD~1 -- Dockerfile

# Rebuild and start
docker compose build --no-cache
docker compose up -d

# Verify
./scripts/health-check.sh
```

## Upgrade Scenarios

### Minor Version Upgrade

Example: RELEASE.2024-10-02 → RELEASE.2024-10-15

Generally safe:
- Bug fixes
- Minor improvements
- No breaking changes

Follow standard procedure.

### Major Version Upgrade

Example: RELEASE.2024-xx → RELEASE.2025-xx

Requires careful review:
- Check migration guides
- Review breaking changes
- Test extensively

### Breaking Change Upgrade

When release notes indicate breaking changes:

1. Read migration documentation thoroughly
2. Test in isolated environment
3. Plan for potential downtime
4. Prepare rollback procedure
5. Execute during maintenance window

## Version Compatibility

### S3 API Compatibility

MinIO maintains S3 API compatibility. Applications should continue working after upgrade.

### Client Compatibility

| Client | Compatibility |
|--------|--------------|
| AWS CLI | Full |
| AWS SDK | Full |
| MinIO Client (mc) | Use matching version |

### Policy Compatibility

IAM policies generally remain compatible. Review release notes for policy changes.

## Automated Upgrade Monitoring

### Version Check Script

Create `scripts/check-version.sh`:

```bash
#!/bin/bash
set -euo pipefail

CURRENT_VERSION=$(grep 'ARG MINIO_VERSION=' Dockerfile | cut -d= -f2)

echo "Current version: $CURRENT_VERSION"

# Check latest release
LATEST=$(curl -s https://api.github.com/repos/minio/minio/releases/latest | grep tag_name | cut -d'"' -f4)

echo "Latest version: $LATEST"

if [[ "$CURRENT_VERSION" != "$LATEST" ]]; then
    echo ""
    echo "⚠️  New version available!"
    echo "Review: https://github.com/minio/minio/releases/tag/$LATEST"
fi
```

## Upgrade Frequency

### Recommendations

| Environment | Frequency | Strategy |
|-------------|-----------|----------|
| Development | Monthly | Stay current |
| Staging | Monthly | Test before production |
| Production | Quarterly | Stability focus |

### Security Updates

Apply security updates promptly:
1. Monitor MinIO security advisories
2. Test security releases quickly
3. Deploy within maintenance windows

## Common Upgrade Issues

### Container Won't Start

```bash
# Check logs
docker compose logs minio

# Common causes:
# - Incompatible data format (check migration notes)
# - Missing environment variables
# - Permission issues
```

### Health Check Fails

```bash
# Wait longer (new version may need time)
sleep 60
./scripts/health-check.sh

# Check if process is running
docker exec minio-server ps aux
```

### Data Access Issues

```bash
# Check data directory
docker exec minio-server ls -la /data

# Check bucket access
docker run --rm --network host \
  -e MC_HOST_local="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:9000" \
  minio/mc ls local/
```

### Policy/User Issues

```bash
# Re-run bootstrap
./scripts/bootstrap.sh

# Check user exists
docker run --rm --network host \
  -e MC_HOST_local="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:9000" \
  minio/mc admin user list local
```

## Related Documentation

- [Architecture](architecture.md)
- [Backup and Restore](backup-restore.md)
- [Security](security.md)
