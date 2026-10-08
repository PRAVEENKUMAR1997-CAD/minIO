#!/usr/bin/env bash
# ==================================================
# MinIO S3 Platform - Reset Script
# ==================================================
# DANGER: This script removes all containers AND volumes.
# All stored objects will be permanently deleted.
#
# Usage:
#   ./scripts/reset.sh
#   ./scripts/reset.sh --force  # Skip confirmation (CI/automation only)

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
FORCE=false
for arg in "$@"; do
    case $arg in
        --force|-f)
            FORCE=true
            shift
            ;;
    esac
done

echo -e "${RED}========================================${NC}"
echo -e "${RED}  WARNING: DESTRUCTIVE OPERATION${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${YELLOW}This will permanently delete:${NC}"
echo "  - All MinIO containers"
echo "  - All stored objects and buckets"
echo "  - All user data in the minio_data volume"
echo "  - All configuration applied via bootstrap"
echo ""
echo -e "${YELLOW}This action cannot be undone!${NC}"
echo ""

# Require confirmation unless --force
if [[ "$FORCE" != "true" ]]; then
    echo -e "Type ${RED}RESET${NC} to confirm deletion:"
    read -r CONFIRMATION
    
    if [[ "$CONFIRMATION" != "RESET" ]]; then
        echo ""
        echo -e "${GREEN}Reset cancelled.${NC}"
        echo "Your data is safe."
        exit 0
    fi
fi

echo ""
echo -e "${YELLOW}Stopping and removing containers...${NC}"
docker compose down --volumes --remove-orphans 2>/dev/null || true

# Also remove any orphaned volumes with our naming
echo -e "${YELLOW}Removing named volumes...${NC}"
docker volume rm minio_data 2>/dev/null || true

# Remove built image
echo -e "${YELLOW}Removing built image...${NC}"
docker image rm minio-s3-platform:local 2>/dev/null || true

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Reset complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "All MinIO data has been deleted."
echo ""
echo "To start fresh:"
echo "  1. Ensure .env is configured"
echo "  2. Run: ./scripts/start.sh"
echo "  3. Run: ./scripts/bootstrap.sh"
echo ""
