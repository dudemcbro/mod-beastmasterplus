#!/usr/bin/env bash
set -u

PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH="$PATCH_DIR/core-beastmasterplus.patch"

# Run this from the AzerothCore repo root.
if ! [ -f "src/server/game/Entities/Pet/Pet.cpp" ]; then
  echo "ERROR: src/server/game/Entities/Pet/Pet.cpp not found. Run this from the AzerothCore repo root."
  exit 1
fi

# If the patch is already applied, reverse-check will succeed.
if git apply --reverse --check "$PATCH" >/dev/null 2>&1; then
  echo "OK: already applied: $(basename "$PATCH")"
  exit 0
fi

# If it is not applied yet, ensure it can be applied cleanly.
if git apply --check "$PATCH" >/dev/null 2>&1; then
  git apply "$PATCH"
  echo "APPLIED: $(basename "$PATCH")"
  exit 0
fi

echo "ERROR: cannot apply cleanly: $(basename "$PATCH")" >&2
echo "Hint: check local core modifications: (git status && git diff)" >&2
exit 1
