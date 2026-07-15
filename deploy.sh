#!/usr/bin/env bash
# "Deploy" = install the consumers exactly the way production does:
# wheels from the registry ONLY (--no-index), obeying each consumer's pins.
# The source tree under common/ plays NO part in what runs.
#
# usage: ./deploy.sh [env-label]     (defaults to the current branch name)
set -euo pipefail
command -v uv >/dev/null 2>&1 || export PATH="/opt/homebrew/bin:$PATH"

ROOT="$(cd "$(dirname "$0")" && pwd)"
REGISTRY="$ROOT/../registry"
BRANCH="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
ENV="${1:-${BRANCH:-detached}}"

echo "--- pinned-world: deploying '$ENV' (branch: ${BRANCH:-detached}) ---"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for CONSUMER in report worker; do
    VENV="$TMP/$CONSUMER-venv"
    uv venv -q "$VENV"
    uv pip install -q --python "$VENV/bin/python" \
        --no-index --find-links "$REGISTRY" \
        "$ROOT/consumers/$CONSUMER"
    OUT="$("$VENV/bin/python" -c "import $CONSUMER; print($CONSUMER.main())")"
    echo "[$CONSUMER on $ENV] $OUT"
done
