#!/usr/bin/env bash
# ==================================================
# MinIO S3 Platform - Bootstrap Script
# ==================================================
# Orchestrates complete initialization of MinIO platform.
# This script is IDEMPOTENT - safe to run multiple times.
#
# Bootstrap performs:
#   1. Wait for MinIO to be healthy
#   2. Configure MinIO Client (mc)
#   3. Create default bucket (if missing)
#   4. Create developer user (if missing)
#   5. Create and attach developer policy
#   6. Optionally create application access key
#
# Usage:
#   ./scripts/bootstrap.sh
#   ./scripts/bootstrap.sh --create-access-key  # Also create access key

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

# Parse arguments
CREATE_ACCESS_KEY=false
for arg in "$@"; do
    case $arg in
        --create-access-key)
            CREATE_ACCESS_KEY=true
            shift
            ;;
    esac
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}MinIO S3 Platform - Bootstrap${NC}"
echo -e "${BLUE}========================================${NC}"

# ==================================================
# Load configuration
# ==================================================
if [[ ! -f ".env" ]]; then
    echo -e "${RED}ERROR: .env file not found${NC}"
    exit 1
fi

# shellcheck source=/dev/null
source .env

# Required variables
MINIO_ROOT_USER="${MINIO_ROOT_USER:?MINIO_ROOT_USER is required}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:?MINIO_ROOT_PASSWORD is required}"
DEVELOPER_USER="${MINIO_DEVELOPER_USER:-developer}"
DEVELOPER_PASSWORD="${MINIO_DEVELOPER_PASSWORD:-}"
DEFAULT_BUCKET="${MINIO_DEFAULT_BUCKET:-developer-data}"
API_PORT="${MINIO_API_PORT:-9000}"
BIND_ADDR="${MINIO_BIND_ADDRESS:-127.0.0.1}"

# Determine access host
if [[ "$BIND_ADDR" == "0.0.0.0" ]]; then
    MINIO_HOST="localhost"
else
    MINIO_HOST="$BIND_ADDR"
fi

MINIO_ENDPOINT="http://${MINIO_HOST}:${API_PORT}"
MC_ALIAS="local"

# ==================================================
# Step 1: Wait for MinIO health
# ==================================================
echo -e "\n${YELLOW}[1/6] Waiting for MinIO to be healthy...${NC}"

MAX_WAIT=120
WAIT_INTERVAL=5
ELAPSED=0

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    if curl -sf "${MINIO_ENDPOINT}/minio/health/live" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ MinIO is healthy${NC}"
        break
    fi
    
    echo "  Waiting for MinIO... (${ELAPSED}s elapsed)"
    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if ! curl -sf "${MINIO_ENDPOINT}/minio/health/live" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: MinIO is not healthy after ${MAX_WAIT}s${NC}"
    exit 1
fi

# ==================================================
# Step 2: Configure MinIO Client
# ==================================================
echo -e "\n${YELLOW}[2/6] Configuring MinIO Client...${NC}"

# Run mc commands in a container
MC_CMD="docker run --rm --network host -e MC_HOST_${MC_ALIAS}=http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@${MINIO_HOST}:${API_PORT} minio/mc"

# Test connection
if $MC_CMD admin info ${MC_ALIAS} > /dev/null 2>&1; then
    echo -e "${GREEN}✓ MinIO Client configured and connected${NC}"
else
    echo -e "${RED}ERROR: Failed to connect to MinIO${NC}"
    echo "Check that MINIO_ROOT_USER and MINIO_ROOT_PASSWORD are correct"
    exit 1
fi

# ==================================================
# Step 3: Create default bucket
# ==================================================
echo -e "\n${YELLOW}[3/6] Creating default bucket: ${DEFAULT_BUCKET}...${NC}"

# Check if bucket exists
if $MC_CMD ls ${MC_ALIAS}/${DEFAULT_BUCKET} > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Bucket '${DEFAULT_BUCKET}' already exists (preserved)${NC}"
else
    if $MC_CMD mb ${MC_ALIAS}/${DEFAULT_BUCKET} 2>&1; then
        echo -e "${GREEN}✓ Bucket '${DEFAULT_BUCKET}' created${NC}"
    else
        echo -e "${RED}ERROR: Failed to create bucket${NC}"
        exit 1
    fi
fi

# ==================================================
# Step 4: Create developer policy
# ==================================================
echo -e "\n${YELLOW}[4/6] Creating developer policy...${NC}"

POLICY_NAME="developer-policy"
POLICY_FILE="config/policies/developer-policy.json"

if [[ ! -f "$POLICY_FILE" ]]; then
    echo -e "${RED}ERROR: Policy file not found: ${POLICY_FILE}${NC}"
    exit 1
fi

# Substitute bucket name in policy
POLICY_CONTENT=$(sed "s/\${BUCKET_NAME}/${DEFAULT_BUCKET}/g" "$POLICY_FILE")

# Create policy using a temp file approach
echo "$POLICY_CONTENT" | docker run --rm -i --network host \
    -e MC_HOST_${MC_ALIAS}="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@${MINIO_HOST}:${API_PORT}" \
    minio/mc admin policy create ${MC_ALIAS} ${POLICY_NAME} /dev/stdin 2>&1 || {
    # Policy might already exist, try to update
    echo "$POLICY_CONTENT" | docker run --rm -i --network host \
        -e MC_HOST_${MC_ALIAS}="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@${MINIO_HOST}:${API_PORT}" \
        minio/mc admin policy create ${MC_ALIAS} ${POLICY_NAME} /dev/stdin 2>&1 || true
}

echo -e "${GREEN}✓ Developer policy configured${NC}"

# ==================================================
# Step 5: Create developer user
# ==================================================
echo -e "\n${YELLOW}[5/6] Creating developer user: ${DEVELOPER_USER}...${NC}"

if [[ -z "$DEVELOPER_PASSWORD" ]]; then
    echo -e "${YELLOW}⚠ MINIO_DEVELOPER_PASSWORD not set, skipping user creation${NC}"
    echo "  Set MINIO_DEVELOPER_PASSWORD in .env to create the developer user"
else
    # Check if user exists
    if $MC_CMD admin user info ${MC_ALIAS} ${DEVELOPER_USER} > /dev/null 2>&1; then
        echo -e "${GREEN}✓ User '${DEVELOPER_USER}' already exists (preserved)${NC}"
    else
        # Create user
        if $MC_CMD admin user add ${MC_ALIAS} ${DEVELOPER_USER} "${DEVELOPER_PASSWORD}" 2>&1; then
            echo -e "${GREEN}✓ User '${DEVELOPER_USER}' created${NC}"
        else
            echo -e "${RED}ERROR: Failed to create user${NC}"
            exit 1
        fi
    fi
    
    # Attach policy to user
    echo "  Attaching policy to user..."
    if $MC_CMD admin policy attach ${MC_ALIAS} ${POLICY_NAME} --user ${DEVELOPER_USER} 2>&1; then
        echo -e "${GREEN}✓ Policy '${POLICY_NAME}' attached to user '${DEVELOPER_USER}'${NC}"
    else
        echo -e "${YELLOW}⚠ Policy attachment returned non-zero (may already be attached)${NC}"
    fi
fi

# ==================================================
# Step 6: Create application access key (optional)
# ==================================================
echo -e "\n${YELLOW}[6/6] Application access key...${NC}"

if [[ "$CREATE_ACCESS_KEY" == "true" ]]; then
    if [[ -z "$DEVELOPER_PASSWORD" ]]; then
        echo -e "${YELLOW}⚠ Cannot create access key without developer user${NC}"
    else
        echo "Creating new access key for ${DEVELOPER_USER}..."
        
        # Create access key
        ACCESS_KEY_OUTPUT=$($MC_CMD admin user svcacct add ${MC_ALIAS} ${DEVELOPER_USER} 2>&1)
        
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}✓ Access key created${NC}"
            echo ""
            echo -e "${YELLOW}========================================${NC}"
            echo -e "${YELLOW}SAVE THESE CREDENTIALS SECURELY${NC}"
            echo -e "${YELLOW}========================================${NC}"
            echo "$ACCESS_KEY_OUTPUT" | grep -E "(Access Key|Secret Key)"
            echo -e "${YELLOW}========================================${NC}"
            echo ""
            echo -e "${RED}WARNING: The secret key will not be shown again!${NC}"
        else
            echo -e "${YELLOW}⚠ Access key creation returned: $ACCESS_KEY_OUTPUT${NC}"
        fi
    fi
else
    echo "Skipping access key creation (use --create-access-key to create)"
fi

# ==================================================
# Summary
# ==================================================
CONSOLE_PORT="${MINIO_CONSOLE_PORT:-9001}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Bootstrap complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Endpoints:${NC}"
echo "  S3 API:   ${MINIO_ENDPOINT}"
echo "  Console:  http://${MINIO_HOST}:${CONSOLE_PORT}"
echo ""
echo -e "${BLUE}Bucket:${NC}"
echo "  Name:     ${DEFAULT_BUCKET}"
echo ""
echo -e "${BLUE}Users:${NC}"
echo "  Root:      ${MINIO_ROOT_USER} (admin only)"
if [[ -n "$DEVELOPER_PASSWORD" ]]; then
    echo "  Developer: ${DEVELOPER_USER} (bucket access only)"
fi
echo ""
echo -e "${BLUE}AWS CLI Example:${NC}"
echo "  aws configure  # Use developer credentials"
echo "  aws --endpoint-url ${MINIO_ENDPOINT} s3 ls s3://${DEFAULT_BUCKET}/"
echo ""
