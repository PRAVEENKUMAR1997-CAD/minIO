#!/usr/bin/env bash
# ==================================================
# MinIO S3 Platform - Production Deploy Script
# ==================================================
# Pulls latest code (optional), rebuilds images, rolls out containers,
# and verifies health. Intended for server-side use and CD pipelines.
#
# Usage:
#   ./scripts/deploy.sh                 # MinIO + External S3 Browser (default)
#   ./scripts/deploy.sh --minio-only    # MinIO only
#   ./scripts/deploy.sh --no-pull
#   ./scripts/deploy.sh --no-build
#
# Environment:
#   DEPLOY_REF   Git ref to deploy (default: main)
#
# On health-check failure after rollout, restores the previous running deploy
# (saved image tags and git revision) and exits non-zero.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

NO_PULL=false
NO_BUILD=false
WITH_S3_BROWSER=true

for arg in "$@"; do
    case $arg in
        --no-pull)
            NO_PULL=true
            ;;
        --no-build)
            NO_BUILD=true
            ;;
        --minio-only)
            WITH_S3_BROWSER=false
            ;;
        --with-s3-browser)
            WITH_S3_BROWSER=true
            ;;
        -h|--help)
            sed -n '2,15p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $arg${NC}"
            exit 1
            ;;
    esac
done

cd "$PROJECT_DIR"

COMPOSE_ARGS=(-f docker-compose.yml)
if [[ "$WITH_S3_BROWSER" == "true" ]]; then
    COMPOSE_ARGS+=(-f docker-compose.s3-browser.yml)
fi

MINIO_IMAGE="minio-s3-platform:local"
MINIO_ROLLBACK="minio-s3-platform:rollback"
BROWSER_IMAGE="external-s3-browser:local"
BROWSER_ROLLBACK="external-s3-browser:rollback"

ROLLBACK_AVAILABLE=false
PREVIOUS_GIT_SHA=""

snapshot_for_rollback() {
    ROLLBACK_AVAILABLE=false
    if docker image inspect "$MINIO_IMAGE" >/dev/null 2>&1; then
        docker tag "$MINIO_IMAGE" "$MINIO_ROLLBACK"
        ROLLBACK_AVAILABLE=true
        echo "Saved rollback snapshot: $MINIO_IMAGE"
    fi
    if [[ "$WITH_S3_BROWSER" == "true" ]] && docker image inspect "$BROWSER_IMAGE" >/dev/null 2>&1; then
        docker tag "$BROWSER_IMAGE" "$BROWSER_ROLLBACK"
        ROLLBACK_AVAILABLE=true
        echo "Saved rollback snapshot: $BROWSER_IMAGE"
    fi
}

restore_previous_deploy() {
    if [[ "$ROLLBACK_AVAILABLE" != "true" ]]; then
        echo -e "${YELLOW}No previous deploy snapshot available to roll back.${NC}"
        return 1
    fi

    echo -e "${YELLOW}Rolling back to previous deploy...${NC}"

    if docker image inspect "$MINIO_ROLLBACK" >/dev/null 2>&1; then
        docker tag "$MINIO_ROLLBACK" "$MINIO_IMAGE"
    fi
    if [[ "$WITH_S3_BROWSER" == "true" ]] && docker image inspect "$BROWSER_ROLLBACK" >/dev/null 2>&1; then
        docker tag "$BROWSER_ROLLBACK" "$BROWSER_IMAGE"
    fi

    if [[ -n "$PREVIOUS_GIT_SHA" ]] && git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        GIT_ROOT="$(git -C "$PROJECT_DIR" rev-parse --show-toplevel)"
        git -C "$GIT_ROOT" checkout --force "$PREVIOUS_GIT_SHA"
    fi

    if ! docker compose "${COMPOSE_ARGS[@]}" up -d --force-recreate --remove-orphans; then
        echo -e "${RED}ERROR: Rollback compose up failed${NC}"
        return 1
    fi

    if ! "$SCRIPT_DIR/health-check.sh" --quiet; then
        echo -e "${RED}ERROR: Rollback completed but health check still failing${NC}"
        return 1
    fi

    return 0
}

fail_deploy() {
    local reason="$1"
    echo -e "${RED}ERROR: ${reason}${NC}"
    docker compose "${COMPOSE_ARGS[@]}" logs --tail=50 || true
    if restore_previous_deploy; then
        echo -e "${GREEN}✓ Restored previous deploy${NC}"
    else
        echo -e "${RED}Rollback could not restore a healthy previous deploy${NC}"
    fi
    exit 1
}

echo -e "${BLUE}========================================${NC}"
if [[ "$WITH_S3_BROWSER" == "true" ]]; then
    DEPLOY_TITLE="MinIO + External S3 Browser - Deploy"
else
    DEPLOY_TITLE="MinIO S3 Platform - Deploy"
fi

echo -e "${BLUE}${DEPLOY_TITLE}${NC}"
echo -e "${BLUE}========================================${NC}"

echo -e "\n${YELLOW}[1/6] Validating configuration...${NC}"

if [[ ! -f ".env" ]]; then
    echo -e "${RED}ERROR: .env file not found${NC}"
    echo "Create .env from .env.example before deploying."
    exit 1
fi

# shellcheck source=/dev/null
source .env

if [[ -z "${MINIO_ROOT_USER:-}" || -z "${MINIO_ROOT_PASSWORD:-}" ]]; then
    echo -e "${RED}ERROR: MINIO_ROOT_USER and MINIO_ROOT_PASSWORD must be set in .env${NC}"
    exit 1
fi

if [[ "$WITH_S3_BROWSER" == "true" ]]; then
    MISSING_VARS=()
    if [[ -z "${S3_BROWSER_SECRET_KEY:-}" || "${S3_BROWSER_SECRET_KEY}" == "CHANGE_THIS_GENERATE_A_RANDOM_SECRET" ]]; then
        MISSING_VARS+=("S3_BROWSER_SECRET_KEY")
    fi
    if [[ -z "${APPROVED_S3_BUCKETS:-}" ]]; then
        MISSING_VARS+=("APPROVED_S3_BUCKETS")
    fi
    if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
        echo -e "${RED}ERROR: S3 Browser deploy requires these .env variables:${NC}"
        for var in "${MISSING_VARS[@]}"; do
            echo "  - $var"
        done
        exit 1
    fi
    if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        if [[ -z "${AWS_ACCESS_KEY_ID:-}" && -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
            echo -e "${YELLOW}WARNING: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY not set; using default AWS credential chain${NC}"
        else
            echo -e "${RED}ERROR: Both AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set (or neither for instance role)${NC}"
            exit 1
        fi
    fi
fi

echo -e "${GREEN}✓ Configuration validated${NC}"

echo -e "\n${YELLOW}[2/6] Preparing rollback snapshot...${NC}"

snapshot_for_rollback

if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    GIT_ROOT="$(git -C "$PROJECT_DIR" rev-parse --show-toplevel)"
    PREVIOUS_GIT_SHA="$(git -C "$GIT_ROOT" rev-parse HEAD)"
    echo "Saved git rollback point: ${PREVIOUS_GIT_SHA:0:8}"
fi

echo -e "\n${YELLOW}[3/6] Updating source...${NC}"

if [[ "$NO_PULL" == "true" ]]; then
    echo "Skipping git pull (--no-pull)"
elif [[ -n "${GIT_ROOT:-}" ]]; then
    DEPLOY_REF="${DEPLOY_REF:-main}"
    echo "Fetching and fast-forwarding to origin/${DEPLOY_REF} in ${GIT_ROOT}"
    git -C "$GIT_ROOT" fetch origin "$DEPLOY_REF"
    git -C "$GIT_ROOT" checkout "$DEPLOY_REF"
    git -C "$GIT_ROOT" pull --ff-only origin "$DEPLOY_REF"
    echo -e "${GREEN}✓ Source updated${NC}"
else
    echo "Not a git repository; skipping pull"
fi

echo -e "\n${YELLOW}[4/6] Building images...${NC}"

if [[ "$NO_BUILD" == "true" ]]; then
    echo "Skipping build (--no-build)"
else
    if ! docker compose "${COMPOSE_ARGS[@]}" build; then
        echo -e "${RED}ERROR: docker compose build failed${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ Images ready${NC}"

echo -e "\n${YELLOW}[5/6] Rolling out services...${NC}"

if ! docker compose "${COMPOSE_ARGS[@]}" up -d --remove-orphans; then
    fail_deploy "docker compose up failed"
fi

echo -e "${GREEN}✓ Services updated${NC}"

echo -e "\n${YELLOW}[6/6] Verifying health...${NC}"

echo "Checking MinIO..."

MAX_WAIT=120
WAIT_INTERVAL=5
ELAPSED=0
HEALTH="unknown"

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    HEALTH=$(docker inspect --format='{{.State.Health.Status}}' minio-server 2>/dev/null || echo "unknown")
    if [[ "$HEALTH" == "healthy" ]]; then
        break
    fi
    echo "  Waiting for MinIO... (${ELAPSED}s, status: ${HEALTH})"
    sleep "$WAIT_INTERVAL"
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [[ "$HEALTH" != "healthy" ]]; then
    fail_deploy "MinIO did not become healthy within ${MAX_WAIT}s"
fi

if ! "$SCRIPT_DIR/health-check.sh" --quiet; then
    fail_deploy "Post-deploy health check failed"
fi

if [[ "$WITH_S3_BROWSER" == "true" ]]; then
    echo "Checking S3 Browser..."

    BROWSER_WAIT=60
    BROWSER_ELAPSED=0
    BROWSER_HEALTH="unknown"

    while [[ $BROWSER_ELAPSED -lt $BROWSER_WAIT ]]; do
        BROWSER_HEALTH=$(docker inspect --format='{{.State.Health.Status}}' external-s3-browser 2>/dev/null || echo "unknown")
        if [[ "$BROWSER_HEALTH" == "healthy" ]]; then
            break
        fi
        echo "  Waiting for S3 Browser... (${BROWSER_ELAPSED}s, status: ${BROWSER_HEALTH})"
        sleep 5
        BROWSER_ELAPSED=$((BROWSER_ELAPSED + 5))
    done

    if [[ "$BROWSER_HEALTH" != "healthy" ]]; then
        docker compose "${COMPOSE_ARGS[@]}" logs s3-browser --tail=50 || true
        fail_deploy "S3 Browser did not become healthy within ${BROWSER_WAIT}s"
    fi

    BIND_ADDR="${MINIO_BIND_ADDRESS:-127.0.0.1}"
    if [[ "$BIND_ADDR" == "0.0.0.0" ]]; then
        BROWSER_HOST="localhost"
    else
        BROWSER_HOST="$BIND_ADDR"
    fi
    BROWSER_PORT="${S3_BROWSER_PORT:-8080}"

    if ! curl -sf "http://${BROWSER_HOST}:${BROWSER_PORT}/login" > /dev/null 2>&1; then
        fail_deploy "S3 Browser /login endpoint not reachable"
    fi

    echo -e "${GREEN}✓ S3 Browser healthy (http://${BROWSER_HOST}:${BROWSER_PORT})${NC}"
fi

echo -e "${GREEN}✓ Deploy completed successfully${NC}"
