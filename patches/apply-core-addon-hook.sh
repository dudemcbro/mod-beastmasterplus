#!/usr/bin/env bash
set -u

PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH="$PATCH_DIR/core-addon-hook-only.patch"
DECL_PATCH="$PATCH_DIR/core-addon-router-decl.patch"
CORE_FILE="src/server/game/Handlers/ChatHandler.cpp"

if ! [ -f "$CORE_FILE" ]; then
  echo "ERROR: $CORE_FILE not found. Run from AzerothCore repo root."
  exit 1
fi

if grep -Eq "AddonMessageRouter::Handle" "$CORE_FILE"; then
  if grep -Eq "namespace[[:space:]]+AddonMessageRouter" "$CORE_FILE"; then
    echo "AddonMessageRouter hook already present. Skipping."
    exit 0
  fi
  echo "AddonMessageRouter hook present but forward declaration missing. Applying decl patch..."
  git apply "$DECL_PATCH"
  echo "Decl patch applied."
  exit 0
fi

echo "Applying AddonMessageRouter hook patch..."
git apply "$PATCH"
echo "Patch applied."
