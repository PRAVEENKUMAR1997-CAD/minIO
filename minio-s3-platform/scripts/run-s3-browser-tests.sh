#!/usr/bin/env bash
# Run unit tests for the External S3 Browser Flask app (no Docker/AWS required).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")/external-s3-browser"

cd "$APP_DIR"

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to run S3 browser tests"
    exit 1
fi

VENV="${APP_DIR}/.venv-test"
if [[ ! -d "$VENV" ]]; then
    python3 -m venv "$VENV"
fi

# shellcheck source=/dev/null
source "$VENV/bin/activate"
pip install -q -r requirements-test.txt
pytest -q tests/
