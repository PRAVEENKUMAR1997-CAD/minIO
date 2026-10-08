#!/usr/bin/env bash
# ==================================================
# MinIO S3 Platform - Stop Script
# ==================================================
# Stops MinIO services while preserving data volumes.
#
# Usage:
#   ./scripts/stop.sh

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

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}MinIO S3 Platform - Stopping${NC}"
echo -e "${BLUE}========================================${NC}"

# Check if services are running
if ! docker compose ps --quiet 2>/dev/null | grep -q .; then
    echo -e "${YELLOW}No running services found${NC}"
    exit 0
fi

# Stop services
echo -e "\n${YELLOW}Stopping services...${NC}"
docker compose down

echo -e "\n${GREEN}✓ Services stopped${NC}"
echo ""
echo -e "${BLUE}Note:${NC} Data volume (minio_data) has been preserved."
echo ""
echo "To restart:  ./scripts/start.sh"
echo "To reset:    ./scripts/reset.sh (WARNING: deletes all data)"
echo ""
