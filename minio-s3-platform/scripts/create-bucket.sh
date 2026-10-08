#!/usr/bin/env bash
# ==================================================
# MinIO S3 Platform - Create Bucket Script
# ==================================================
# Creates a bucket if it doesn't already exist.
# Never deletes existing buckets or objects.
#
# Usage:
#   ./scripts/create-bucket.sh [bucket-name]
#
# Examples:
#   ./scripts/create-bucket.sh                    # Creates MINIO_DEFAULT_BUCKET
#   ./scripts/create-bucket.sh my-custom-bucket   # Creates custom bucket

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# ==================================================
# Load configuration
# ==================================================
if [[ ! -f ".env" ]]; then
    echo -e "${RED}ERROR: .env file not found${NC}"
    exit 1
fi

# shellcheck source=/dev/null
source .env

MINIO_ROOT_USER="${MINIO_ROOT_USER:?MINIO_ROOT_USER is required}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD is required}"
API_PORT="${MINIO_API_PORT:-9000}"
BIND_ADDR="${MINIO_BIND_ADDRESS:-127.0.0.1}"
DEFAULT_BUCKET="${MINIO_DEFAULT_BUCKET:-developer-data}"

if [[ "$BIND_ADDR" == "0.0.0.0" ]]; then
    MINIO_HOST="localhost"
else
    MINIO_HOST="$BIND_ADDR"
fi

# Get bucket name from argument or default
BUCKET_NAME="${1:-$DEFAULT_BUCKET}"

MC_ALIAS="local"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}MinIO S3 Platform - Create Bucket${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Bucket: ${BUCKET_NAME}"
echo ""

# ==================================================
# Validate bucket name
# ==================================================
# S3 bucket naming rules (basic validation)
if [[ ! "$BUCKET_NAME" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ]] || [[ ${#BUCKET_NAME} -lt 3 ]] || [[ ${#BUCKET_NAME} -gt 63 ]]; then
    echo -e "${RED}ERROR: Invalid bucket name${NC}"
    echo ""
    echo "Bucket names must:"
    echo "  - Be 3-63 characters long"
    echo "  - Start and end with a letter or number"
    echo "  - Contain only lowercase letters, numbers, hyphens, and periods"
    exit 1
fi

# ==================================================
# Check MinIO health
# ==================================================
echo -e "${YELLOW}Checking MinIO health...${NC}"

if ! curl -sf "http://${MINIO_HOST}:${API_PORT}/minio/health/live" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: MinIO is not healthy${NC}"
    echo "Start MinIO first: ./scripts/start.sh"
    exit 1
fi

echo -e "${GREEN}✓ MinIO is healthy${NC}"

# ==================================================
# MinIO Client command
# ==================================================
MC_CMD="docker run --rm --network host -e MC_HOST_${MC_ALIAS}=http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@${MINIO_HOST}:${API_PORT} minio/mc"

# ==================================================
# Check if bucket exists
# ==================================================
echo -e "\n${YELLOW}Checking if bucket exists...${NC}"

if $MC_CMD ls ${MC_ALIAS}/${BUCKET_NAME} > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Bucket '${BUCKET_NAME}' already exists (no changes made)${NC}"
    echo ""
    echo "Existing buckets and objects are never modified or deleted."
    exit 0
fi

# ==================================================
# Create bucket
# ==================================================
echo -e "\n${YELLOW}Creating bucket '${BUCKET_NAME}'...${NC}"

if $MC_CMD mb ${MC_ALIAS}/${BUCKET_NAME} 2>&1; then
    echo -e "${GREEN}✓ Bucket '${BUCKET_NAME}' created successfully${NC}"
else
    echo -e "${RED}ERROR: Failed to create bucket${NC}"
    exit 1
fi

# ==================================================
# Summary
# ==================================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Bucket created successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Bucket: s3://${BUCKET_NAME}"
echo ""
echo "Access via AWS CLI:"
echo "  aws --endpoint-url http://${MINIO_HOST}:${API_PORT} s3 ls s3://${BUCKET_NAME}/"
echo ""
echo "To give a user access, create or update a policy."
echo ""
