# MinIO S3 Platform - Backup and Restore Guide

## Important Distinction

> **Docker volume persistence is NOT backup.**
> 
> Data surviving `docker compose down` is persistence, not protection against:
> - Hardware failure
> - Accidental deletion
> - Corruption
> - Disasters

## Backup Strategies

### Strategy 1: Docker Volume Backup

Backs up the entire MinIO data directory.

**Pros:**
- Complete backup including metadata
- Simple to restore
- Fast for moderate data sizes

**Cons:**
- Requires stopping MinIO or consistent snapshot
- Large backup size
- All-or-nothing restore

#### Create Backup

```bash
# Stop MinIO for consistent backup
./scripts/stop.sh

# Create backup directory
mkdir -p backup

# Backup volume
docker run --rm \
  -v minio_data:/data:ro \
  -v "$(pwd)/backup:/backup" \
  alpine \
  tar czf /backup/minio-data-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .

# Restart MinIO
./scripts/start.sh
```

#### Online Backup (Less Consistent)

```bash
# Backup while running (use with caution)
docker run --rm \
  -v minio_data:/data:ro \
  -v "$(pwd)/backup:/backup" \
  alpine \
  tar czf /backup/minio-data-$(date +%Y%m%d-%H%M%S).tar.gz -C /data .
```

### Strategy 2: Object-Level Backup (mc mirror)

Uses MinIO Client to mirror objects to another location.

**Pros:**
- Can run while MinIO is online
- Selective backup possible
- Can mirror to remote storage

**Cons:**
- Doesn't include user/policy configuration
- Requires additional storage

#### Mirror to Local Directory

```bash
# Create backup directory
mkdir -p backup/objects

# Mirror all buckets
docker run --rm --network host \
  -v "$(pwd)/backup/objects:/backup" \
  -e MC_HOST_local="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:9000" \
  minio/mc mirror local/ /backup/
```

#### Mirror Specific Bucket

```bash
docker run --rm --network host \
  -v "$(pwd)/backup/objects:/backup" \
  -e MC_HOST_local="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:9000" \
  minio/mc mirror local/developer-data /backup/developer-data/
```

#### Mirror to Remote MinIO/S3

```bash
docker run --rm --network host \
  -e MC_HOST_local="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:9000" \
  -e MC_HOST_remote="https://${REMOTE_ACCESS_KEY}:${REMOTE_SECRET_KEY}@remote-minio:9000" \
  minio/mc mirror local/ remote/backup/
```

### Strategy 3: Combined Backup

Best practice for production: combine both strategies.

```bash
#!/bin/bash
# backup-full.sh

set -euo pipefail

DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="backup/${DATE}"

mkdir -p "${BACKUP_DIR}"

echo "Starting full backup..."

# 1. Object-level backup (online)
echo "Backing up objects..."
docker run --rm --network host \
  -v "$(pwd)/${BACKUP_DIR}/objects:/backup" \
  -e MC_HOST_local="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:9000" \
  minio/mc mirror local/ /backup/

# 2. Export users and policies
echo "Exporting configuration..."
docker run --rm --network host \
  -e MC_HOST_local="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:9000" \
  minio/mc admin user list local > "${BACKUP_DIR}/users.txt"

docker run --rm --network host \
  -e MC_HOST_local="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:9000" \
  minio/mc admin policy list local > "${BACKUP_DIR}/policies.txt"

# 3. Copy policy files
cp -r config/policies "${BACKUP_DIR}/"

echo "Backup complete: ${BACKUP_DIR}"
```

## Restore Procedures

### Restore from Volume Backup

```bash
# Stop MinIO
./scripts/stop.sh

# Remove existing volume (if corrupted)
docker volume rm minio_data

# Create new volume
docker volume create minio_data

# Restore from backup
docker run --rm \
  -v minio_data:/data \
  -v "$(pwd)/backup:/backup" \
  alpine \
  tar xzf /backup/minio-data-YYYYMMDD-HHMMSS.tar.gz -C /data

# Start MinIO
./scripts/start.sh

# Verify
./scripts/health-check.sh
```

### Restore from Object Backup

```bash
# Ensure MinIO is running
./scripts/start.sh

# Restore objects
docker run --rm --network host \
  -v "$(pwd)/backup/objects:/backup" \
  -e MC_HOST_local="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:9000" \
  minio/mc mirror /backup/ local/

# Re-run bootstrap to restore users/policies
./scripts/bootstrap.sh
```

### Partial Restore (Specific Bucket)

```bash
docker run --rm --network host \
  -v "$(pwd)/backup/objects:/backup" \
  -e MC_HOST_local="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:9000" \
  minio/mc mirror /backup/developer-data/ local/developer-data/
```

## Backup Schedule

### Recommended Schedule

| Environment | Full Backup | Incremental |
|-------------|-------------|-------------|
| Development | Weekly | Daily |
| Staging | Daily | Every 6 hours |
| Production | Daily | Hourly |

### Retention Policy

| Backup Type | Retention |
|-------------|-----------|
| Daily | 7 days |
| Weekly | 4 weeks |
| Monthly | 12 months |

## Automated Backup Script

Create `scripts/backup.sh`:

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

source .env

DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="backup/${DATE}"
RETENTION_DAYS=7

mkdir -p "${BACKUP_DIR}"

echo "=== MinIO Backup: ${DATE} ==="

# Object backup
echo "Backing up objects..."
docker run --rm --network host \
  -v "${PROJECT_DIR}/${BACKUP_DIR}:/backup" \
  -e MC_HOST_local="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:${MINIO_API_PORT:-9000}" \
  minio/mc mirror --quiet local/ /backup/

# Compress
echo "Compressing..."
tar czf "backup/minio-backup-${DATE}.tar.gz" -C backup "${DATE}"
rm -rf "${BACKUP_DIR}"

# Cleanup old backups
echo "Cleaning up old backups..."
find backup -name "minio-backup-*.tar.gz" -mtime +${RETENTION_DAYS} -delete

echo "=== Backup complete ==="
ls -lh backup/minio-backup-${DATE}.tar.gz
```

### Cron Job

```bash
# Add to crontab
# Daily backup at 2 AM
0 2 * * * /path/to/minio-s3-platform/scripts/backup.sh >> /var/log/minio-backup.log 2>&1
```

## Disaster Recovery

### Single-Node Limitations

> **This deployment does NOT provide high availability.**
> 
> A single-node MinIO deployment cannot survive:
> - Drive failure
> - Container host failure
> - Data corruption

### DR Requirements

| RPO | Recovery Point Objective | How much data loss is acceptable? |
|-----|-------------------------|-----------------------------------|
| RTO | Recovery Time Objective | How quickly must service be restored? |

### DR Strategies by RPO/RTO

| Strategy | RPO | RTO | Cost |
|----------|-----|-----|------|
| Daily backup to remote | 24h | Hours | Low |
| Continuous replication | Minutes | Minutes | Medium |
| Distributed MinIO | Seconds | Seconds | High |

### Remote Backup Location

Store backups in a different:
- Physical location
- Cloud region
- Infrastructure provider

```bash
# Example: Backup to AWS S3
aws s3 cp backup/minio-backup-*.tar.gz s3://my-backup-bucket/minio/
```

## Verification

### Test Restore Regularly

1. Create test environment
2. Restore from backup
3. Verify data integrity
4. Document any issues

### Backup Verification Script

```bash
#!/bin/bash
# verify-backup.sh

BACKUP_FILE="$1"

if [[ ! -f "$BACKUP_FILE" ]]; then
    echo "Usage: $0 <backup-file.tar.gz>"
    exit 1
fi

echo "Verifying backup: $BACKUP_FILE"

# Test archive integrity
if tar tzf "$BACKUP_FILE" > /dev/null 2>&1; then
    echo "✓ Archive integrity OK"
else
    echo "✗ Archive is corrupted"
    exit 1
fi

# Check file count
FILE_COUNT=$(tar tzf "$BACKUP_FILE" | wc -l)
echo "✓ Contains $FILE_COUNT files"

# Check size
SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
echo "✓ Backup size: $SIZE"

echo "Verification complete"
```

## Troubleshooting

### Backup Fails

```bash
# Check disk space
df -h

# Check volume exists
docker volume ls | grep minio_data

# Check MinIO health
./scripts/health-check.sh
```

### Restore Fails

```bash
# Verify backup integrity
tar tzf backup/minio-backup-*.tar.gz | head

# Check volume permissions
docker run --rm -v minio_data:/data alpine ls -la /data
```

### Data Mismatch After Restore

```bash
# Sync differences
docker run --rm --network host \
  -v "$(pwd)/backup/objects:/backup" \
  -e MC_HOST_local="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@localhost:9000" \
  minio/mc mirror --overwrite /backup/ local/
```

## Related Documentation

- [Architecture](architecture.md)
- [Security](security.md)
- [Upgrade](upgrade.md)
