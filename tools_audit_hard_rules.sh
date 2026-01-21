#!/usr/bin/env bash
set -u

MODROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$MODROOT/src"
PATCHDIR="$MODROOT/patches"

pass() { printf "PASS: %s\n" "$1"; }
fail() { printf "FAIL: %s\n" "$1"; }
unk()  { printf "UNKNOWN: %s\n" "$1"; }

echo "== HARD RULES AUDIT =="
echo

# NO_RETAME: heuristics, no direct proof without runtime, but we can flag suspicious calls
if grep -RIn --exclude-dir=sql --exclude-dir=BeastmasterPlus -E '\bTame\b|\bHandleTame\b|TameCreature|SPELL_EFFECT_TAMECREATURE|PetTame' "$SRC" >/dev/null; then
  fail "NO_RETAME (found tame related symbols in module sources)"
else
  pass "NO_RETAME (no tame related symbols found in module sources)"
fi

# NO_PET_DELETE_RECREATE: flag delete and create patterns
if grep -RIn --exclude-dir=sql --exclude-dir=BeastmasterPlus -E '\bDELETE\b|\bDelete\b|RemovePet|DeleteFromDB|DeletePet|DELETE FROM character_pet|INSERT INTO character_pet' "$SRC" >/dev/null; then
  echo "Evidence for NO_PET_DELETE_RECREATE check:"
  grep -RIn --exclude-dir=sql --exclude-dir=BeastmasterPlus -E '\bDELETE\b|\bDelete\b|RemovePet|DeleteFromDB|DeletePet|DELETE FROM character_pet|INSERT INTO character_pet' "$SRC" | head -n 50
  echo
  unk "NO_PET_DELETE_RECREATE (suspicious patterns found, needs manual review of lines above)"
else
  pass "NO_PET_DELETE_RECREATE (no obvious delete or recreate patterns found)"
fi

# DB_PET_1_TO_1: look for updates vs inserts, and table usage
if grep -RIn -E 'character_pet' "$SRC" >/dev/null; then
  echo "character_pet references:"
  grep -RIn -E 'character_pet' "$SRC" | head -n 50
  echo
  # if only SELECT/UPDATE and no INSERT/DELETE, that's a good sign
  if grep -RIn -E 'INSERT\s+INTO\s+character_pet|DELETE\s+FROM\s+character_pet' "$SRC" >/dev/null; then
    unk "DB_PET_1_TO_1 (module writes inserts or deletes to character_pet, needs manual verification)"
  else
    pass "DB_PET_1_TO_1 (no inserts or deletes to character_pet detected; verify updates only)"
  fi
else
  unk "DB_PET_1_TO_1 (no character_pet references found, unexpected)"
fi

# SERVER_AUTHORITATIVE: check addon messages are handled server side and responses sent from server
if grep -RIn -E 'CHAT_MSG_ADDON|LANG_ADDON|BuildChatPacket|SendPacket|TryHandleAddon|RegisterHandler' "$SRC" >/dev/null; then
  pass "SERVER_AUTHORITATIVE (server handles addon messages and sends responses)"
else
  unk "SERVER_AUTHORITATIVE (did not find expected server side addon handling markers)"
fi

# ADDON_UI_ONLY: check for gossip, npc, stablemaster, trainer hooks etc
if grep -RIn -E 'Gossip|OnGossip|GOSSIP|StableMaster|NPC|Vendor|Trainer|CreatureScript|ScriptedGossip' "$SRC" >/dev/null; then
  echo "Evidence for ADDON_UI_ONLY check:"
  grep -RIn -E 'Gossip|OnGossip|GOSSIP|StableMaster|NPC|Vendor|Trainer|CreatureScript|ScriptedGossip' "$SRC" | head -n 50
  echo
  unk "ADDON_UI_ONLY (found npc or gossip related symbols, needs manual review)"
else
  pass "ADDON_UI_ONLY (no npc or gossip hooks detected in module sources)"
fi

# AVOID_STABLE_LOGIC: you explicitly manipulate PetStable in code, so this depends on your definition.
# If your rule means avoid stable slots and stablemaster flows, but still may read PetStable, mark as UNKNOWN and show evidence.
if grep -RIn -E '\bPetStable\b|\bGetOrInitPetStable\b|\bStabledPets\b|\bUnslottedPets\b' "$SRC" >/dev/null; then
  echo "PetStable usage:"
  grep -RIn -E '\bPetStable\b|\bGetOrInitPetStable\b|\bStabledPets\b|\bUnslottedPets\b' "$SRC" | head -n 80
  echo
  unk "AVOID_STABLE_LOGIC (module uses PetStable data structures; confirm it bypasses stable limits and flows as intended)"
else
  pass "AVOID_STABLE_LOGIC (no PetStable usage detected)"
fi

echo
echo "== PATCH REQUIREMENTS =="
if [ -f "$PATCHDIR/apply-core-addon-hook.sh" ] && [ -f "$PATCHDIR/core-addon-hook-only.patch" ]; then
  pass "Core hook patch is packaged (apply-core-addon-hook.sh)"
else
  fail "Core hook patch missing"
fi

echo
echo "== END AUDIT =="
