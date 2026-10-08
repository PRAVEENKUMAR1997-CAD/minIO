#!/usr/bin/env bash
# ==================================================
# MinIO S3 Platform - Health Check Script
# ==================================================
# Verifies MinIO services are running and healthy.
# Returns non-zero exit code on failure.
#
# Usage:
#   ./scripts/health-check.sh
#   ./scripts/health-check.sh --quiet  # Minimal output

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
QUIET=false
for arg in "$@"; do
    case $arg in
        --quiet|-q)
            QUIET=true
            shift
            ;;
    esac
done

# Load configuration
if [[ -f ".env" ]]; then
    # shellcheck source=/dev/null
    source .env
fi

API_PORT="${MINIO_API_PORT:-9000}"
CONSOLE_PORT="${MINIO_CONSOLE_PORT:-9001}"
BIND_ADDR="${MINIO_BIND_ADDRESS:-127.0.0.1}"

# Determine access host
if [[ "$BIND_ADDR" == "0.0.0.0" ]]; then
    ACCESS_HOST="localhost"
else
    ACCESS_HOST="$BIND_ADDR"
fi

# Track failures
FAILURES=0

log() {
    if [[ "$QUIET" != "true" ]]; then
        echo "$@"
    fi
}

check_pass() {
    log -e "${GREEN}✓ $1${NC}"
}

check_fail() {
    log -e "${RED}✗ $1${NC}"
    FAILURES=$((FAILURES + 1))
}

check_warn() {
    log -e "${YELLOW}⚠ $1${NC}"
}

if [[ "$QUIET" != "true" ]]; then
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}MinIO S3 Platform - Health Check${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
fi

# ==================================================
# Check 1: Container running
# ==================================================
log -e "${YELLOW}[1/5] Checking container status...${NC}"

CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' minio-server 2>/dev/null || echo "not_found")

if [[ "$CONTAINER_STATUS" == "running" ]]; then
    check_pass "Container is running"
else
    check_fail "Container is not running (status: $CONTAINER_STATUS)"
fi

# ==================================================
# Check 2: Docker health status
# ==================================================
log -e "\n${YELLOW}[2/5] Checking Docker health status...${NC}"

HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' minio-server 2>/dev/null || echo "unknown")

if [[ "$HEALTH_STATUS" == "healthy" ]]; then
    check_pass "Docker health: healthy"
elif [[ "$HEALTH_STATUS" == "starting" ]]; then
    check_warn "Docker health: starting (still initializing)"
else
    check_fail "Docker health: $HEALTH_STATUS"
fi

# ==================================================
# Check 3: MinIO live endpoint
# ==================================================
log -e "\n${YELLOW}[3/5] Checking MinIO live endpoint...${NC}"

if curl -sf "http://${ACCESS_HOST}:${API_PORT}/minio/health/live" > /dev/null 2>&1; then
    check_pass "MinIO live endpoint responding"
else
    check_fail "MinIO live endpoint not responding"
fi

# ==================================================
# Check 4: S3 API endpoint
# ==================================================
log -e "\n${YELLOW}[4/5] Checking S3 API endpoint...${NC}"

# Try to access the API (will return 403 without auth, but that means it's working)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${ACCESS_HOST}:${API_PORT}/" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "403" || "$HTTP_CODE" == "200" ]]; then
    check_pass "S3 API endpoint responding (HTTP $HTTP_CODE)"
elif [[ "$HTTP_CODE" == "000" ]]; then
    check_fail "S3 API endpoint not reachable"
else
    check_warn "S3 API endpoint returned HTTP $HTTP_CODE"
fi

# ==================================================
# Check 5: Console endpoint
# ==================================================
log -e "\n${YELLOW}[5/5] Checking Console endpoint...${NC}"

CONSOLE_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${ACCESS_HOST}:${CONSOLE_PORT}/" 2>/dev/null || echo "000")

if [[ "$CONSOLE_CODE" == "200" || "$CONSOLE_CODE" == "302" ]]; then
    check_pass "Console endpoint responding (HTTP $CONSOLE_CODE)"
elif [[ "$CONSOLE_CODE" == "000" ]]; then
    check_fail "Console endpoint not reachable"
else
    check_warn "Console endpoint returned HTTP $CONSOLE_CODE"
fi

# ==================================================
# Summary
# ==================================================
if [[ "$QUIET" != "true" ]]; then
    echo ""
    echo -e "${BLUE}========================================${NC}"
    if [[ $FAILURES -eq 0 ]]; then
        echo -e "${GREEN}All health checks passed${NC}"
    else
        echo -e "${RED}$FAILURES health check(s) failed${NC}"
    fi
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Endpoints:"
    echo "  S3 API:   http://${ACCESS_HOST}:${API_PORT}"
    echo "  Console:  http://${ACCESS_HOST}:${CONSOLE_PORT}"
    echo ""
fi

# Exit with failure if any checks failed
if [[ $FAILURES -gt 0 ]]; then
    exit 1
fi

exit 0
