#!/usr/bin/env bash
# ==================================================
# MinIO S3 Platform - Start Script
# ==================================================
# Validates configuration, builds/pulls images, starts services,
# and waits for health before printing endpoints.
#
# Usage:
#   ./scripts/start.sh
#   ./scripts/start.sh --no-build  # Skip image build

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

# Parse arguments
NO_BUILD=false
for arg in "$@"; do
    case $arg in
        --no-build)
            NO_BUILD=true
            shift
            ;;
    esac
done

cd "$PROJECT_DIR"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}MinIO S3 Platform - Starting${NC}"
echo -e "${BLUE}========================================${NC}"

# ==================================================
# Step 1: Validate .env file exists
# ==================================================
echo -e "\n${YELLOW}[1/6] Validating configuration...${NC}"

if [[ ! -f ".env" ]]; then
    echo -e "${RED}ERROR: .env file not found${NC}"
    echo "Please create .env from .env.example:"
    echo "  cp .env.example .env"
    echo "  # Edit .env with your configuration"
    exit 1
fi

# Source .env for validation (without exporting)
# shellcheck source=/dev/null
source .env

# Validate required variables
REQUIRED_VARS=("MINIO_ROOT_USER" "MINIO_ROOT_PASSWORD")
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        echo -e "${RED}ERROR: Required variable $var is not set in .env${NC}"
        exit 1
    fi
done

# Validate password strength (basic check)
if [[ ${#MINIO_ROOT_PASSWORD} -lt 8 ]]; then
    echo -e "${YELLOW}WARNING: MINIO_ROOT_PASSWORD is less than 8 characters${NC}"
    echo "Consider using a stronger password for production."
fi

echo -e "${GREEN}✓ Configuration validated${NC}"

# ==================================================
# Step 2: Build image (unless --no-build)
# ==================================================
echo -e "\n${YELLOW}[2/6] Building MinIO image...${NC}"

if [[ "$NO_BUILD" == "true" ]]; then
    echo "Skipping build (--no-build specified)"
else
    if ! docker compose build --no-cache 2>&1; then
        echo -e "${RED}ERROR: Failed to build MinIO image${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ Image ready${NC}"

# ==================================================
# Step 3: Start services
# ==================================================
echo -e "\n${YELLOW}[3/6] Starting services...${NC}"

if ! docker compose up -d 2>&1; then
    echo -e "${RED}ERROR: Failed to start services${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Services started${NC}"

# ==================================================
# Step 4: Wait for health
# ==================================================
echo -e "\n${YELLOW}[4/6] Waiting for MinIO to be healthy...${NC}"

MAX_WAIT=120
WAIT_INTERVAL=5
ELAPSED=0

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    HEALTH=$(docker inspect --format='{{.State.Health.Status}}' minio-server 2>/dev/null || echo "unknown")
    
    if [[ "$HEALTH" == "healthy" ]]; then
        echo -e "${GREEN}✓ MinIO is healthy${NC}"
        break
    fi
    
    echo "  Waiting... (${ELAPSED}s elapsed, status: $HEALTH)"
    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [[ "$HEALTH" != "healthy" ]]; then
    echo -e "${RED}ERROR: MinIO did not become healthy within ${MAX_WAIT}s${NC}"
    echo "Check logs with: docker compose logs minio"
    exit 1
fi

# ==================================================
# Step 5: Verify endpoints
# ==================================================
echo -e "\n${YELLOW}[5/6] Verifying endpoints...${NC}"

API_PORT="${MINIO_API_PORT:-9000}"
CONSOLE_PORT="${MINIO_CONSOLE_PORT:-9001}"
BIND_ADDR="${MINIO_BIND_ADDRESS:-127.0.0.1}"

# Determine access host
if [[ "$BIND_ADDR" == "0.0.0.0" ]]; then
    ACCESS_HOST="localhost"
else
    ACCESS_HOST="$BIND_ADDR"
fi

# Test S3 API
if curl -sf "http://${ACCESS_HOST}:${API_PORT}/minio/health/live" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ S3 API reachable${NC}"
else
    echo -e "${YELLOW}⚠ S3 API not responding (may need a moment)${NC}"
fi

# Test Console
if curl -sf "http://${ACCESS_HOST}:${CONSOLE_PORT}/" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Console reachable${NC}"
else
    echo -e "${YELLOW}⚠ Console not responding (may need a moment)${NC}"
fi

# ==================================================
# Step 6: Print access information
# ==================================================
echo -e "\n${YELLOW}[6/6] Access Information${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}MinIO S3 Platform is running!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "S3 API Endpoint:    ${GREEN}http://${ACCESS_HOST}:${API_PORT}${NC}"
echo -e "Web Console:        ${GREEN}http://${ACCESS_HOST}:${CONSOLE_PORT}${NC}"
echo ""
echo -e "Root User:          ${YELLOW}${MINIO_ROOT_USER}${NC}"
echo -e "Root Password:      ${YELLOW}[configured in .env]${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "1. Run bootstrap to create developer user and bucket:"
echo "   ./scripts/bootstrap.sh"
echo ""
echo "2. Access the console at http://${ACCESS_HOST}:${CONSOLE_PORT}"
echo ""
echo "3. Use AWS CLI:"
echo "   aws --endpoint-url http://${ACCESS_HOST}:${API_PORT} s3 ls"
echo ""
echo -e "${BLUE}Commands:${NC}"
echo "  ./scripts/health-check.sh   # Check health status"
echo "  ./scripts/stop.sh           # Stop services"
echo "  docker compose logs -f      # View logs"
echo ""
