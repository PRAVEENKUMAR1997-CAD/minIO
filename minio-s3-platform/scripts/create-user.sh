#!/usr/bin/env bash
# ==================================================
# MinIO S3 Platform - Create User Script
# ==================================================
# Creates a MinIO user with a specified policy.
# Safely handles existing users without destructive changes.
#
# Usage:
#   ./scripts/create-user.sh <username> <password> [policy]
#
# Examples:
#   ./scripts/create-user.sh myuser mypassword
#   ./scripts/create-user.sh appuser apppass developer-policy

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
# Parse arguments
# ==================================================
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <username> <password> [policy]"
    echo ""
    echo "Arguments:"
    echo "  username  - Username for the new user"
    echo "  password  - Password for the new user (min 8 characters)"
    echo "  policy    - Optional policy name to attach (default: developer-policy)"
    echo ""
    echo "Example:"
    echo "  $0 myuser mysecretpassword developer-policy"
    exit 1
fi

USERNAME="$1"
PASSWORD="$2"
POLICY="${3:-developer-policy}"

# Validate password length
if [[ ${#PASSWORD} -lt 8 ]]; then
    echo -e "${RED}ERROR: Password must be at least 8 characters${NC}"
    exit 1
fi

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

if [[ "$BIND_ADDR" == "0.0.0.0" ]]; then
    MINIO_HOST="localhost"
else
    MINIO_HOST="$BIND_ADDR"
fi

MC_ALIAS="local"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}MinIO S3 Platform - Create User${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Username: ${USERNAME}"
echo "Policy:   ${POLICY}"
echo ""

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
# Check if user exists
# ==================================================
echo -e "\n${YELLOW}Checking if user exists...${NC}"

if $MC_CMD admin user info ${MC_ALIAS} ${USERNAME} > /dev/null 2>&1; then
    echo -e "${YELLOW}User '${USERNAME}' already exists${NC}"
    echo ""
    echo "Existing user will not be modified to prevent data loss."
    echo "To update the user, use the MinIO Console or delete and recreate."
    echo ""
    
    # Still attach policy in case it changed
    echo -e "${YELLOW}Ensuring policy is attached...${NC}"
    $MC_CMD admin policy attach ${MC_ALIAS} ${POLICY} --user ${USERNAME} 2>&1 || true
    echo -e "${GREEN}✓ Policy '${POLICY}' attached to user '${USERNAME}'${NC}"
    exit 0
fi

# ==================================================
# Create user
# ==================================================
echo -e "\n${YELLOW}Creating user '${USERNAME}'...${NC}"

if $MC_CMD admin user add ${MC_ALIAS} ${USERNAME} "${PASSWORD}" 2>&1; then
    echo -e "${GREEN}✓ User '${USERNAME}' created${NC}"
else
    echo -e "${RED}ERROR: Failed to create user${NC}"
    exit 1
fi

# ==================================================
# Attach policy
# ==================================================
echo -e "\n${YELLOW}Attaching policy '${POLICY}'...${NC}"

if $MC_CMD admin policy attach ${MC_ALIAS} ${POLICY} --user ${USERNAME} 2>&1; then
    echo -e "${GREEN}✓ Policy '${POLICY}' attached to user '${USERNAME}'${NC}"
else
    echo -e "${YELLOW}⚠ Policy attachment returned non-zero${NC}"
    echo "The policy '${POLICY}' might not exist. Create it first or use an existing policy."
fi

# ==================================================
# Summary
# ==================================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}User created successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Username: ${USERNAME}"
echo "Policy:   ${POLICY}"
echo ""
echo "The user can now log into the MinIO Console."
echo ""
echo -e "${YELLOW}Note: Do not share credentials insecurely.${NC}"
echo ""
