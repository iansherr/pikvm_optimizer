#!/bin/bash
# ---------------------------------------------------------------------------
# Docker-based kvmd config validation test.
#
# Builds a lightweight container with kvmd installed from PyPI, copies a
# platform-specific main.yaml, and runs the patch validation suite.
#
# Usage:
#   bash tests/docker-test.sh              # build + run
#   bash tests/docker-test.sh --no-build   # skip build, reuse image
# ---------------------------------------------------------------------------
set -euo pipefail

IMAGE_NAME="pikvm-optimizer-test"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Building test image..."
docker build -t "$IMAGE_NAME" -f "$SCRIPT_DIR/Dockerfile" "$REPO_DIR"

echo ""
echo "==> Running patch validation suite..."
docker run --rm "$IMAGE_NAME" bash /app/tests/validate_patches.sh
