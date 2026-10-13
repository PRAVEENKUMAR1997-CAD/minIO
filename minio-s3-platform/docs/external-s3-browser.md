# External S3 Browser

Read-only access to AWS S3 buckets through a web interface.

## Overview

The External S3 Browser allows users to browse and download files from AWS S3 buckets without copying data into MinIO. Users authenticate using their MinIO credentials, but the actual S3 operations use server-side AWS credentials that are never exposed to users.

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          User's Browser                              │
│                                                                      │
│  ┌──────────────────┐              ┌──────────────────────────┐     │
│  │ MinIO Console    │              │ External S3 Browser      │     │
│  │ :9001            │              │ :8080                    │     │
│  └────────┬─────────┘              └─────────────┬────────────┘     │
└───────────┼──────────────────────────────────────┼──────────────────┘
            │                                      │
            │                                      │ Login: MinIO creds
            │                                      │ Browse: AWS S3
            │                                      │
┌───────────┼──────────────────────────────────────┼──────────────────┐
│           │              Docker Network          │                   │
│           ▼                                      ▼                   │
│  ┌──────────────────┐              ┌──────────────────────────┐     │
│  │ MinIO Server     │◄─────────────│ S3 Browser Service       │     │
│  │ (Local Storage)  │  Auth check  │ (Flask + boto3)          │     │
│  └──────────────────┘              └─────────────┬────────────┘     │
│                                                  │                   │
└──────────────────────────────────────────────────┼──────────────────┘
                                                   │
                                                   │ AWS API calls
                                                   │ (server-side only)
                                                   ▼
                                    ┌──────────────────────────┐
                                    │ AWS S3                   │
                                    │ (Original data location) │
                                    └──────────────────────────┘
```

### Key Features

| Feature | Description |
|---------|-------------|
| **Read-only access** | List buckets, browse objects, download files |
| **No data duplication** | Data remains in AWS S3, never copied to MinIO |
| **MinIO authentication** | Users log in with existing MinIO credentials |
| **AWS credentials hidden** | Server-side only, never exposed to browser |
| **Bucket allow-list** | Only authorized buckets are accessible |
| **CSRF protection** | Flask-WTF with CSRF tokens |
| **Secure cookies** | HTTPOnly, SameSite=Lax |

## Prerequisites

1. **Running MinIO deployment** with user accounts
2. **AWS S3 buckets** you want users to access
3. **AWS IAM credentials** with read-only permissions

## Setup

### 1. Create AWS IAM User

Create a dedicated IAM user with minimal read-only permissions:

```bash
# Create IAM user
aws iam create-user --user-name minio-s3-browser-readonly

# Attach the policy (edit config/aws-iam/s3-browser-readonly-policy.json first)
aws iam put-user-policy \
  --user-name minio-s3-browser-readonly \
  --policy-name S3BrowserReadOnly \
  --policy-document file://config/aws-iam/s3-browser-readonly-policy.json

# Create access key
aws iam create-access-key --user-name minio-s3-browser-readonly
```

**Important:** Edit `config/aws-iam/s3-browser-readonly-policy.json` to replace `YOUR-BUCKET-1`, `YOUR-BUCKET-2` with your actual bucket names before applying.

### 2. Configure Environment

Edit `.env` and configure:

```bash
# Required: List of AWS S3 buckets users can browse
APPROVED_S3_BUCKETS=bucket1,bucket2,bucket3

# Required: Generate a secret key
S3_BROWSER_SECRET_KEY=<run: python3 -c "import secrets; print(secrets.token_hex(32))">

# AWS credentials (from Step 1)
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=ap-south-1

# MinIO bucket for authentication validation
S3_BROWSER_AUTH_BUCKET=developer-data
```

### 3. Start Services

```bash
./scripts/start-with-s3-browser.sh
```

Or manually:

```bash
docker compose -f docker-compose.yml -f docker-compose.s3-browser.yml up -d
```

### 4. Access the Browser

Navigate to http://127.0.0.1:8080 and log in with MinIO credentials.

## Configuration Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `APPROVED_S3_BUCKETS` | Yes | - | Comma-separated list of allowed bucket names |
| `S3_BROWSER_SECRET_KEY` | Yes | - | Flask session secret (generate random) |
| `AWS_ACCESS_KEY_ID` | No* | - | AWS access key ID |
| `AWS_SECRET_ACCESS_KEY` | No* | - | AWS secret access key |
| `AWS_REGION` | No | ap-south-1 | AWS region |
| `S3_BROWSER_PORT` | No | 8080 | Browser service port |
| `S3_BROWSER_AUTH_BUCKET` | No | developer-data | MinIO bucket for auth validation |
| `MINIO_REGION` | No | us-east-1 | Must match MinIO server region for login validation |
| `S3_BROWSER_COOKIE_SECURE` | No | false | Set true when behind HTTPS proxy |

### Unit tests (no Docker/AWS)

```bash
./scripts/run-s3-browser-tests.sh
```

*AWS credentials are optional if running on EC2 with an instance role.

## Security

### AWS IAM Policy (Minimum Permissions)

The provided policy in `config/aws-iam/s3-browser-readonly-policy.json` grants only:

- `s3:ListBucket` - List objects in bucket
- `s3:GetBucketLocation` - Determine bucket region
- `s3:GetObject` - Download objects
- `s3:GetObjectVersion` - Access versioned objects
- `s3:GetObjectAttributes` - Read object metadata

**Not granted (read-only enforced):**
- `s3:PutObject` - Cannot upload
- `s3:DeleteObject` - Cannot delete
- `s3:PutBucketPolicy` - Cannot modify permissions
- Any administrative actions

### Credential Security

| Credential Type | Exposed to User? | Storage Location |
|-----------------|------------------|------------------|
| MinIO access key | User provides | User's input |
| MinIO secret key | User provides | Server memory only |
| AWS access key | **Never** | Server environment |
| AWS secret key | **Never** | Server environment |

### Network Security

- Default binding: `127.0.0.1` (localhost only)
- CSRF protection on all forms
- HTTPOnly cookies
- Optional TLS via reverse proxy

## Testing Read-Only Enforcement

### Verify AWS Policy Denies Writes

```bash
# Should fail with AccessDenied
aws s3 cp test.txt s3://your-bucket/test.txt \
  --profile s3-browser-readonly

# Should fail with AccessDenied
aws s3 rm s3://your-bucket/existing-file.txt \
  --profile s3-browser-readonly

# Should succeed (read allowed)
aws s3 ls s3://your-bucket/ --profile s3-browser-readonly
```

### Verify Application Has No Write Endpoints

The Flask application only implements:
- `GET /login` - Login form
- `POST /login` - Authentication
- `POST /logout` - Sign out
- `GET /` - List approved buckets
- `GET /bucket/<name>` - Browse bucket
- `GET /download/<bucket>?key=...` - Download file

No upload, delete, or modify endpoints exist.

## User Access Control

### Creating Read-Only MinIO Users

Create MinIO users with limited permissions:

```bash
# Create policy that only allows listing
cat > /tmp/readonly-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::developer-data",
        "arn:aws:s3:::developer-data/*"
      ]
    }
  ]
}
EOF

# Apply via mc
docker exec minio-server mc admin policy create local readonly-policy /tmp/readonly-policy.json
docker exec minio-server mc admin user add local s3viewer ViewerPassword123
docker exec minio-server mc admin policy attach local readonly-policy --user=s3viewer
```

Users with `s3viewer` credentials can log into the External S3 Browser but cannot perform any write operations on either MinIO or AWS S3.

## Troubleshooting

### "Login failed" Error

1. Verify MinIO credentials are correct
2. Check that `S3_BROWSER_AUTH_BUCKET` exists in MinIO
3. Verify user has `s3:ListBucket` permission on the auth bucket

### "Unable to access S3" Error (502)

1. Verify AWS credentials in `.env`
2. Check IAM policy includes the bucket
3. Verify bucket name matches exactly (case-sensitive)
4. Check AWS region setting

### Service Won't Start

Check logs:
```bash
docker compose -f docker-compose.yml -f docker-compose.s3-browser.yml logs s3-browser
```

Common issues:
- Missing `APPROVED_S3_BUCKETS` - must be set
- Missing `S3_BROWSER_SECRET_KEY` - must be set
- MinIO not healthy - s3-browser waits for MinIO

## Stopping the Service

```bash
# Stop both services (preserve data)
docker compose -f docker-compose.yml -f docker-compose.s3-browser.yml down

# Stop only S3 browser, keep MinIO running
docker compose -f docker-compose.yml -f docker-compose.s3-browser.yml stop s3-browser
```

## Rollback

To remove the External S3 Browser:

```bash
# Stop services
docker compose -f docker-compose.yml -f docker-compose.s3-browser.yml down

# Start MinIO only
./scripts/start.sh
```

The S3 browser is stateless - removing it has no impact on MinIO data.
