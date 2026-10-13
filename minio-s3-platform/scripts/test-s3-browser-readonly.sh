#!/usr/bin/env bash
# ==================================================
# Test S3 Browser Read-Only Enforcement
# ==================================================
# Verifies that the S3 Browser only allows read operations.
#
# Prerequisites:
#   - Running S3 Browser service
#   - AWS CLI configured with the S3 Browser IAM credentials
#   - At least one approved bucket with test data
#
# Usage:
#   ./scripts/test-s3-browser-readonly.sh <bucket-name>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

BUCKET="${1:-}"

if [[ -z "$BUCKET" ]]; then
    echo "Usage: $0 <bucket-name>"
    echo ""
    echo "Tests that the S3 Browser IAM credentials are read-only."
    echo "Uses AWS CLI with credentials from environment or AWS_PROFILE."
    exit 1
fi

echo "=============================================="
echo "S3 Browser Read-Only Enforcement Test"
echo "=============================================="
echo "Testing bucket: $BUCKET"
echo ""

PASS=0
FAIL=0

# Test function
test_operation() {
    local description="$1"
    local should_succeed="$2"
    shift 2
    local cmd=("$@")
    
    echo -n "  $description: "
    
    if "${cmd[@]}" > /dev/null 2>&1; then
        if [[ "$should_succeed" == "yes" ]]; then
            echo -e "${GREEN}PASS${NC} (succeeded as expected)"
            ((PASS++))
        else
            echo -e "${RED}FAIL${NC} (should have been denied)"
            ((FAIL++))
        fi
    else
        if [[ "$should_succeed" == "no" ]]; then
            echo -e "${GREEN}PASS${NC} (denied as expected)"
            ((PASS++))
        else
            echo -e "${RED}FAIL${NC} (should have succeeded)"
            ((FAIL++))
        fi
    fi
}

echo "Read operations (should succeed):"
test_operation "List bucket contents" "yes" aws s3 ls "s3://$BUCKET/"
test_operation "Get bucket location" "yes" aws s3api get-bucket-location --bucket "$BUCKET"

echo ""
echo "Write operations (should be denied):"

# Create temporary test file
TEMP_FILE=$(mktemp)
echo "test data $(date)" > "$TEMP_FILE"
trap "rm -f '$TEMP_FILE'" EXIT

test_operation "Upload new file" "no" aws s3 cp "$TEMP_FILE" "s3://$BUCKET/test-readonly-$(date +%s).txt"
test_operation "Delete object" "no" aws s3 rm "s3://$BUCKET/nonexistent-file-$(date +%s).txt"
test_operation "Create bucket" "no" aws s3 mb "s3://test-readonly-bucket-$(date +%s)"

echo ""
echo "Admin operations (should be denied):"
test_operation "Put bucket policy" "no" aws s3api put-bucket-policy --bucket "$BUCKET" --policy '{"Version":"2012-10-17","Statement":[]}'
test_operation "Delete bucket policy" "no" aws s3api delete-bucket-policy --bucket "$BUCKET"
test_operation "Put bucket versioning" "no" aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled

echo ""
echo "=============================================="
echo "Test Results"
echo "=============================================="
echo -e "Passed: ${GREEN}$PASS${NC}"
echo -e "Failed: ${RED}$FAIL${NC}"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo -e "${RED}WARNING: Some tests failed!${NC}"
    echo "The IAM policy may grant more permissions than intended."
    echo "Review config/aws-iam/s3-browser-readonly-policy.json"
    exit 1
else
    echo ""
    echo -e "${GREEN}All tests passed. Read-only enforcement verified.${NC}"
fi
