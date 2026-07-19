#!/usr/bin/env bash
# Build a common package into the shared registry (the fake hosted registry).
# The registry is IMMUTABLE: a version, once published, can never be replaced.
set -euo pipefail
command -v uv >/dev/null 2>&1 || export PATH="/opt/homebrew/bin:$PATH"

ROOT="$(cd "$(dirname "$0")" && pwd)"
REGISTRY="$ROOT/../registry"
PKG="${1:?usage: ./publish.sh <pkg>   (pkg = qb | solver)}"

PYPROJECT="$ROOT/common/$PKG/pyproject.toml"
[ -f "$PYPROJECT" ] || { echo "no such package: $PKG" >&2; exit 1; }

VERSION="$(grep -m1 '^version' "$PYPROJECT" | cut -d'"' -f2)"
WHEEL="$REGISTRY/$PKG-$VERSION-py3-none-any.whl"

if [ -e "$WHEEL" ]; then
    echo "REFUSED: $PKG $VERSION is already in the registry." >&2
    echo "         The registry is immutable (like any hosted package registry). Bump the" >&2
    echo "         version in common/$PKG/pyproject.toml and publish again." >&2
    exit 1
fi

uv build -q --wheel "$ROOT/common/$PKG" -o "$REGISTRY"
echo "published: $(basename "$WHEEL")"
