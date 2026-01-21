#!/usr/bin/env bash
set -u

PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH="$PATCH_DIR/core-addon-hook-only.patch"
CORE_FILE="src/server/game/Handlers/ChatHandler.cpp"

if ! [ -f "$CORE_FILE" ]; then
  echo "ERROR: $CORE_FILE not found. Run from AzerothCore repo root."
  exit 1
fi

if grep -Eq "AddonMessageRouter::Handle" "$CORE_FILE"; then
  echo "AddonMessageRouter hook already present. Skipping."
  exit 0
fi

echo "Applying AddonMessageRouter hook patch..."
git apply "$PATCH"
echo "Patch applied."
