#!/usr/bin/env bash
set -u

PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH="$PATCH_DIR/core-beastmasterplus.patch"
CORE_FILE="src/server/game/Handlers/ChatHandler.cpp"
PET_FILE="src/server/game/Entities/Pet/Pet.cpp"
DB_FILE="src/server/database/Database/Implementation/CharacterDatabase.h"
HUNTER_FILE="src/server/scripts/Spells/spell_hunter.cpp"
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --force|-f) FORCE=1 ;;
  esac
done

if ! [ -f "$CORE_FILE" ]; then
  echo "ERROR: $CORE_FILE not found. Run from AzerothCore repo root."
  exit 1
fi

HOOK_PRESENT=0
DECL_PRESENT=0
PET_PATCH_PRESENT=0
DB_PATCH_PRESENT=0
TAME_PATCH_PRESENT=0

grep -Eq "AddonMessageRouter::Handle" "$CORE_FILE" && HOOK_PRESENT=1
grep -Eq "namespace[[:space:]]+AddonMessageRouter" "$CORE_FILE" && DECL_PRESENT=1
grep -Eq "BeastMasterPlus.AllowMultipleUnslottedPets\", true" "$PET_FILE" && PET_PATCH_PRESENT=1
grep -Eq "CHAR_UPD_CHAR_PET_NO_SLOT" "$DB_FILE" && DB_PATCH_PRESENT=1
grep -Eq "BeastMasterPlus.AllowMultipleUnslottedPets\", true" "$HUNTER_FILE" && TAME_PATCH_PRESENT=1

if [ "$FORCE" -eq 0 ] && [ "$HOOK_PRESENT" -eq 1 ] && [ "$DECL_PRESENT" -eq 1 ] && [ "$PET_PATCH_PRESENT" -eq 1 ] && [ "$DB_PATCH_PRESENT" -eq 1 ] && [ "$TAME_PATCH_PRESENT" -eq 1 ]; then
  echo "BeastMasterPlus core patch already present. Skipping."
  exit 0
fi

if [ "$HOOK_PRESENT" -eq 0 ]; then
  echo "Applying BeastMasterPlus core patch..."
  if git apply "$PATCH"; then
    echo "Patch applied."
    exit 0
  fi
  echo "Patch failed (possibly due to partial core changes). Trying partial apply..."
fi

# Ensure forward declaration exists if the hook call already exists
if [ "$DECL_PRESENT" -eq 0 ]; then
  echo "Inserting AddonMessageRouter forward declaration..."
  perl -0777 -i -pe 'unless(/namespace AddonMessageRouter\s*\{/s){ s/(#include "WorldSession\.h"\n)/$1\n\/\/ mod-beastmasterplus provides AddonMessageRouter in src\/BmpAddonMessageRouter.*\nnamespace AddonMessageRouter\n{\n    bool Handle(WorldSession* session, std::string const& msg);\n}\n\n/s }' "$CORE_FILE"
fi

# Apply remaining (non-ChatHandler) hunks if needed
if [ "$PET_PATCH_PRESENT" -eq 0 ] || [ "$DB_PATCH_PRESENT" -eq 0 ] || [ "$TAME_PATCH_PRESENT" -eq 0 ]; then
  echo "Applying remaining BeastMasterPlus core hunks (excluding ChatHandler)..."
  if git apply --exclude=src/server/game/Handlers/ChatHandler.cpp "$PATCH"; then
    echo "Remaining hunks applied."
  else
    echo "ERROR: Remaining hunks failed to apply."
    exit 1
  fi
fi

# Insert hook call if missing
if [ "$HOOK_PRESENT" -eq 0 ]; then
  echo "Inserting AddonMessageRouter hook call..."
  perl -0777 -i -pe 's/(AddonChannelCommandHandler\(this\)\.ParseCommands\(msg\.c_str\(\)\)\n\s*return;\n)/$1            if (AddonMessageRouter::Handle(this, msg))\n                return;\n/s' "$CORE_FILE"
fi
