# MinIO S3 Platform - Architecture

## Overview

This platform provides a production-quality, single-node MinIO deployment using Docker Compose. It delivers S3-compatible object storage with a web console for administration.

## Architecture Diagram

```
                                    ┌─────────────────────────────────────┐
                                    │         External Clients            │
                                    │  (AWS CLI, SDKs, Applications)      │
                                    └─────────────────┬───────────────────┘
                                                      │
                              ┌───────────────────────┴───────────────────────┐
                              │                                               │
                    ┌─────────▼─────────┐                       ┌─────────────▼───────────┐
                    │   S3 API :9000    │                       │   Web Console :9001     │
                    │  (Object Storage) │                       │   (Administration)      │
                    └─────────┬─────────┘                       └─────────────┬───────────┘
                              │                                               │
                              └───────────────────────┬───────────────────────┘
                                                      │
                                    ┌─────────────────▼───────────────────┐
                                    │          MinIO Server               │
                                    │      (minio-server container)       │
                                    │                                     │
                                    │  ┌───────────────────────────────┐  │
                                    │  │      Object Storage Engine    │  │
                                    │  │   - Bucket Management         │  │
                                    │  │   - Object Operations         │  │
                                    │  │   - Access Control            │  │
                                    │  │   - Versioning                │  │
                                    │  │   - Lifecycle Policies        │  │
                                    │  └───────────────────────────────┘  │
                                    └─────────────────┬───────────────────┘
                                                      │
                                    ┌─────────────────▼───────────────────┐
                                    │       Docker Named Volume           │
                                    │         (minio_data:/data)          │
                                    │                                     │
                                    │   Persistent Object Storage         │
                                    │   - Survives container restarts     │
                                    │   - Survives docker compose down    │
                                    │   - Deleted by docker compose down -v│
                                    └─────────────────────────────────────┘
```

## Components

### MinIO Server

The core component providing:

- **S3 API** (Port 9000): S3-compatible object storage API
- **Web Console** (Port 9001): Browser-based administration interface

### Docker Volume

Named volume `minio_data` provides:

- Persistent storage across container lifecycle
- Data survival during normal operations
- Explicit deletion required for data removal

### MinIO Client (mc)

Administrative tool used for:

- User management
- Policy configuration
- Bucket operations
- Data migration

## Data Flow

```
Client Request
      │
      ▼
┌─────────────────┐
│   Port Binding  │──── 127.0.0.1:9000 (API)
│                 │──── 127.0.0.1:9001 (Console)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  MinIO Server   │
│  (Container)    │
│                 │
│  ┌───────────┐  │
│  │ Auth/IAM  │  │  ◄── Users, Policies, Access Keys
│  └─────┬─────┘  │
│        │        │
│  ┌─────▼─────┐  │
│  │  Bucket   │  │  ◄── Bucket Operations
│  │  Handler  │  │
│  └─────┬─────┘  │
│        │        │
│  ┌─────▼─────┐  │
│  │  Object   │  │  ◄── Object CRUD
│  │  Handler  │  │
│  └─────┬─────┘  │
└────────┼────────┘
         │
         ▼
┌─────────────────┐
│  /data Volume   │
│  (minio_data)   │
└─────────────────┘
```

## Security Layers

### Network Security

```
                    Internet
                        │
                        ▼
              ┌─────────────────┐
              │    Firewall     │  ◄── Block direct access
              └────────┬────────┘
                       │
              ┌────────▼────────┐
              │  Reverse Proxy  │  ◄── TLS termination
              │  (Nginx, etc.)  │
              └────────┬────────┘
                       │
              ┌────────▼────────┐
              │  MinIO Server   │  ◄── HTTP only (internal)
              │  127.0.0.1:9000 │
              └─────────────────┘
```

### Authentication & Authorization

```
┌──────────────────────────────────────────────────────┐
│                  MinIO IAM System                     │
├──────────────────────────────────────────────────────┤
│                                                       │
│  ┌─────────────┐      ┌─────────────┐                │
│  │ Root User   │      │  Policies   │                │
│  │ (Admin)     │      │             │                │
│  │             │      │ ┌─────────┐ │                │
│  │ - Full      │      │ │Developer│ │                │
│  │   access    │      │ │ Policy  │ │                │
│  │ - User      │      │ └─────────┘ │                │
│  │   mgmt      │      │             │                │
│  └──────┬──────┘      └──────┬──────┘                │
│         │                    │                        │
│         │    ┌───────────────┘                        │
│         ▼    ▼                                        │
│  ┌─────────────────┐                                  │
│  │ Developer User  │                                  │
│  │                 │                                  │
│  │ - Bucket access │                                  │
│  │ - No admin ops  │                                  │
│  │ - No user mgmt  │                                  │
│  └─────────────────┘                                  │
│                                                       │
└──────────────────────────────────────────────────────┘
```

## Single-Node vs Distributed

### This Deployment (Single-Node)

| Aspect | Characteristic |
|--------|----------------|
| Nodes | 1 |
| Drives | 1 (Docker volume) |
| Redundancy | None |
| Data Protection | External backups only |
| Use Case | Development, testing, small workloads |

### Distributed MinIO (Not Included)

| Aspect | Characteristic |
|--------|----------------|
| Nodes | 4+ |
| Drives | 4+ per node |
| Redundancy | Erasure coding |
| Data Protection | Built-in redundancy |
| Use Case | Production, enterprise |

## Limitations

1. **No High Availability**: Single point of failure
2. **No Erasure Coding**: Data not protected against drive failure
3. **Manual Backups Required**: No automatic replication
4. **Limited Scalability**: Single container performance limits

## Recommended Production Architecture

For production workloads requiring high availability:

```
                         Load Balancer
                              │
              ┌───────────────┼───────────────┐
              │               │               │
         ┌────▼────┐    ┌────▼────┐    ┌────▼────┐
         │ MinIO 1 │    │ MinIO 2 │    │ MinIO 3 │ ...
         │ 4 drives│    │ 4 drives│    │ 4 drives│
         └─────────┘    └─────────┘    └─────────┘
              │               │               │
              └───────────────┼───────────────┘
                              │
                    Erasure Coded Storage
```

## Related Documentation

- [Security](security.md)
- [Setup](setup.md)
- [Backup and Restore](backup-restore.md)
- [Upgrade](upgrade.md)
