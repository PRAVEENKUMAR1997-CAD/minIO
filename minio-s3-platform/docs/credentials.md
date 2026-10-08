# MinIO S3 Platform - Credentials Guide

## Credential Types

MinIO uses several types of credentials. Understanding the differences is critical for security.

### Overview

| Type | Purpose | Used By | Console Login | S3 API |
|------|---------|---------|---------------|--------|
| Root Credentials | Full admin access | Administrators | Yes | Yes (NOT recommended) |
| User Credentials | User identity | Console users | Yes | Yes |
| Access Keys | Service authentication | Applications | No | Yes |

## Root Credentials

### Configuration

Set in `.env`:

```bash
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=YourVeryStrongPassword123!
```

### Capabilities

- **Full administrative access**
- Create/delete users
- Create/delete buckets
- Manage policies
- Server configuration
- Access all data

### Security Requirements

| Requirement | Recommendation |
|-------------|----------------|
| Password Length | Minimum 12 characters |
| Complexity | Upper, lower, numbers, symbols |
| Storage | Secure vault (HashiCorp, AWS Secrets Manager) |
| Rotation | Regular rotation schedule |
| Usage | Administrative tasks ONLY |

### Warning

> **NEVER use root credentials in applications.**
> 
> Root credentials should only be used for:
> - Initial setup
> - Administrative tasks
> - Emergency access

## User Credentials

### Creating Users

**Via Bootstrap:**
```bash
./scripts/bootstrap.sh
```

**Via Script:**
```bash
./scripts/create-user.sh myuser MyPassword123!
```

**Via MinIO Client:**
```bash
docker run --rm --network host \
  -e MC_HOST_local="http://admin:password@localhost:9000" \
  minio/mc admin user add local myuser MyPassword123!
```

### Developer User

The default developer user created by bootstrap:

```bash
MINIO_DEVELOPER_USER=developer
MINIO_DEVELOPER_PASSWORD=YourDeveloperPassword!
```

Capabilities:
- Access to `developer-data` bucket
- Read/write objects
- List bucket contents
- **Cannot** manage other users
- **Cannot** access other buckets
- **Cannot** perform admin operations

## Access Keys (Service Accounts)

### What Are Access Keys?

Access keys are separate credentials for applications:

- **Access Key ID**: Public identifier (like a username)
- **Secret Access Key**: Private secret (like a password)

### Why Use Access Keys?

1. **Granular Control**: Create multiple keys per user
2. **Easy Rotation**: Rotate without changing user password
3. **Auditability**: Track which key performed actions
4. **Revocation**: Disable a key without affecting user

### Creating Access Keys

**Via Bootstrap:**
```bash
./scripts/bootstrap.sh --create-access-key
```

**Via MinIO Console:**
1. Login to console
2. Navigate to Identity → Service Accounts
3. Click "Create Service Account"
4. Save credentials securely

**Via MinIO Client:**
```bash
docker run --rm --network host \
  -e MC_HOST_local="http://admin:password@localhost:9000" \
  minio/mc admin user svcacct add local developer
```

Output:
```
Access Key: Q3AM3UQ867SPQQA43P2F
Secret Key: zuf+tfteSlswRu7BJ86wekitnifILbZam1KYY3TG
```

> **Warning:** The secret key is shown ONLY ONCE. Save it immediately.

### Using Access Keys

**AWS CLI:**
```bash
export AWS_ACCESS_KEY_ID=Q3AM3UQ867SPQQA43P2F
export AWS_SECRET_ACCESS_KEY=zuf+tfteSlswRu7BJ86wekitnifILbZam1KYY3TG
aws --endpoint-url http://localhost:9000 s3 ls
```

**AWS Credentials File:**
```ini
# ~/.aws/credentials
[minio]
aws_access_key_id = Q3AM3UQ867SPQQA43P2F
aws_secret_access_key = zuf+tfteSlswRu7BJ86wekitnifILbZam1KYY3TG
```

**Java/Spring Boot:**
```java
AwsBasicCredentials credentials = AwsBasicCredentials.create(
    "Q3AM3UQ867SPQQA43P2F",
    "zuf+tfteSlswRu7BJ86wekitnifILbZam1KYY3TG"
);
```

## Credential Rotation

### Root Password Rotation

1. Backup current configuration
2. Update `.env` with new password
3. Restart MinIO: `./scripts/stop.sh && ./scripts/start.sh`
4. Update any admin tooling using root credentials

### User Password Rotation

```bash
docker run --rm --network host \
  -e MC_HOST_local="http://admin:password@localhost:9000" \
  minio/mc admin user password local developer NewPassword123!
```

### Access Key Rotation

1. Create new access key
2. Update applications with new key
3. Verify applications work
4. Delete old access key

```bash
# Create new key
docker run --rm --network host \
  -e MC_HOST_local="http://admin:password@localhost:9000" \
  minio/mc admin user svcacct add local developer

# After updating applications, remove old key
docker run --rm --network host \
  -e MC_HOST_local="http://admin:password@localhost:9000" \
  minio/mc admin user svcacct rm local OLD_ACCESS_KEY
```

## Security Best Practices

### Do

- ✅ Use separate credentials for each application
- ✅ Use access keys for applications, not user passwords
- ✅ Rotate credentials regularly
- ✅ Use a secrets manager for production
- ✅ Apply least-privilege policies
- ✅ Audit credential usage

### Don't

- ❌ Use root credentials in applications
- ❌ Share credentials between applications
- ❌ Commit credentials to version control
- ❌ Log credentials
- ❌ Send credentials via insecure channels
- ❌ Use weak passwords

## Credential Flow Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                    Credential Hierarchy                       │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────┐                                         │
│  │  Root User      │ ◄── Administrative access only          │
│  │  (admin)        │                                         │
│  └────────┬────────┘                                         │
│           │ creates                                           │
│           ▼                                                   │
│  ┌─────────────────┐                                         │
│  │  Regular User   │ ◄── Console login + S3 API              │
│  │  (developer)    │                                         │
│  └────────┬────────┘                                         │
│           │ creates                                           │
│           ▼                                                   │
│  ┌─────────────────┐                                         │
│  │  Access Key     │ ◄── Application authentication          │
│  │  (service acct) │     S3 API only                         │
│  └─────────────────┘                                         │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

## Troubleshooting

### Invalid Access Key

```
An error occurred (InvalidAccessKeyId): The AWS Access Key Id you provided does not exist
```

**Solution:** Verify the access key ID is correct and the key exists.

### Signature Mismatch

```
An error occurred (SignatureDoesNotMatch): The request signature we calculated does not match
```

**Solution:** Verify the secret access key is correct.

### Access Denied

```
An error occurred (AccessDenied): Access Denied
```

**Solution:** Check that the user/access key has the required policy attached.

## Related Documentation

- [Security](security.md)
- [Integration](integration.md)
- [Setup](setup.md)
