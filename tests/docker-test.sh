#!/bin/bash
# ---------------------------------------------------------------------------
# Docker-based kvmd config validation test.
#
# Builds a container with PiKVM's kvmd (from GitHub -- see tests/Dockerfile for
# why not PyPI), adds a platform-specific main.yaml, and runs the patch
# validation suite against kvmd's real config engine.
#
# Usage:
#   bash tests/docker-test.sh              # build + run
#   bash tests/docker-test.sh --no-build   # skip build, reuse image
# ---------------------------------------------------------------------------
set -euo pipefail

IMAGE_NAME="pikvm-optimizer-test"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "${1:-}" = "--no-build" ]; then
    echo "==> Skipping build, reusing $IMAGE_NAME"
else
    echo "==> Building test image..."
    # Prefer BuildKit: the legacy builder is deprecated, and on some daemons
    # (e.g. OrbStack) it fails silently -- no step output and no image.
    if docker buildx version >/dev/null 2>&1; then
        docker buildx build --load -t "$IMAGE_NAME" -f "$SCRIPT_DIR/Dockerfile" "$REPO_DIR"
    else
        docker build -t "$IMAGE_NAME" -f "$SCRIPT_DIR/Dockerfile" "$REPO_DIR"
    fi
fi

echo ""
echo "==> Running patch validation suite..."
docker run --rm "$IMAGE_NAME" python /app/tests/validate_patches.py
