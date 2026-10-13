#!/usr/bin/env bash
# ==================================================
# Start MinIO with External S3 Browser
# ==================================================
# Starts both MinIO and the External S3 Browser service.
# Users can browse AWS S3 buckets with read-only access.
#
# Prerequisites:
#   1. Copy .env.example to .env and configure
#   2. Set S3_BROWSER_* variables in .env
#   3. Configure AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
#   4. Set APPROVED_S3_BUCKETS with allowed bucket names
#
# Usage:
#   ./scripts/start-with-s3-browser.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=============================================="
echo "MinIO + External S3 Browser Startup"
echo "=============================================="

# Check for .env file
if [[ ! -f ".env" ]]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Copy .env.example to .env and configure:"
    echo "  cp .env.example .env"
    exit 1
fi

# Source .env to check required variables
set -a
source .env
set +a

# Validate required S3 Browser variables
MISSING_VARS=()

if [[ -z "${S3_BROWSER_SECRET_KEY:-}" || "${S3_BROWSER_SECRET_KEY:-}" == "CHANGE_THIS_GENERATE_A_RANDOM_SECRET" ]]; then
    MISSING_VARS+=("S3_BROWSER_SECRET_KEY")
fi

if [[ -z "${APPROVED_S3_BUCKETS:-}" ]]; then
    MISSING_VARS+=("APPROVED_S3_BUCKETS")
fi

# Check AWS credentials (unless using instance role)
if [[ -z "${AWS_ACCESS_KEY_ID:-}" && -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
    echo -e "${YELLOW}Warning: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY not set${NC}"
    echo "The S3 browser will attempt to use EC2 instance role or other default credentials."
    echo ""
fi

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
    echo -e "${RED}Error: Missing required environment variables:${NC}"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    echo ""
    echo "Configure these variables in .env before starting."
    echo ""
    echo "Generate a secret key with:"
    echo "  python3 -c \"import secrets; print(secrets.token_hex(32))\""
    exit 1
fi

echo "Configuration validated."
echo ""

# Build and start services
echo "Building images..."
docker compose -f docker-compose.yml -f docker-compose.s3-browser.yml build

echo ""
echo "Starting services..."
docker compose -f docker-compose.yml -f docker-compose.s3-browser.yml up -d

echo ""
echo "Waiting for services to be healthy..."

# Wait for MinIO
echo -n "  MinIO: "
timeout=60
while [[ $timeout -gt 0 ]]; do
    if docker compose -f docker-compose.yml -f docker-compose.s3-browser.yml exec -T minio curl -sf http://localhost:9000/minio/health/live > /dev/null 2>&1; then
        echo -e "${GREEN}healthy${NC}"
        break
    fi
    sleep 1
    ((timeout--))
done
if [[ $timeout -eq 0 ]]; then
    echo -e "${RED}timeout${NC}"
fi

# Wait for S3 Browser
echo -n "  S3 Browser: "
timeout=30
while [[ $timeout -gt 0 ]]; do
    if curl -sf "http://${MINIO_BIND_ADDRESS:-127.0.0.1}:${S3_BROWSER_PORT:-8080}/login" > /dev/null 2>&1; then
        echo -e "${GREEN}healthy${NC}"
        break
    fi
    sleep 1
    ((timeout--))
done
if [[ $timeout -eq 0 ]]; then
    echo -e "${RED}timeout${NC}"
fi

echo ""
echo "=============================================="
echo -e "${GREEN}Services Started Successfully${NC}"
echo "=============================================="
echo ""
echo "Access points:"
echo "  MinIO Console:     http://${MINIO_BIND_ADDRESS:-127.0.0.1}:${MINIO_CONSOLE_PORT:-9001}"
echo "  MinIO S3 API:      http://${MINIO_BIND_ADDRESS:-127.0.0.1}:${MINIO_API_PORT:-9000}"
echo "  External S3 Browser: http://${MINIO_BIND_ADDRESS:-127.0.0.1}:${S3_BROWSER_PORT:-8080}"
echo ""
echo "Login to the S3 Browser with your MinIO credentials."
echo "You will see the approved AWS S3 buckets: ${APPROVED_S3_BUCKETS}"
echo ""
echo "View logs: docker compose -f docker-compose.yml -f docker-compose.s3-browser.yml logs -f"
echo "Stop:      docker compose -f docker-compose.yml -f docker-compose.s3-browser.yml down"
