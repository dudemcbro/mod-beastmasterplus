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


# ensure forward declaration exists in core (the module provides the implementation)
if ! grep -Eq "namespace[[:space:]]+AddonMessageRouter" "$CORE_FILE"; then
  echo "Inserting AddonMessageRouter forward declaration..."
  perl -0777 -i -pe 'unless(/namespace AddonMessageRouter\s*\{/s){ s/(#include "WorldSession\.h"\n)/$1\n\/\/ Forward declaration for module-provided addon message routing\nnamespace AddonMessageRouter\n{\n    bool Handle(WorldSession* session, std::string const& msg);\n}\n\n/s }' "$CORE_FILE"
fi

echo "Applying AddonMessageRouter hook patch..."
git apply "$PATCH"
echo "Patch applied."
