#!/usr/bin/env bash
set -u

PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH="$PATCH_DIR/core-beastmasterplus.patch"
CORE_FILE="src/server/game/Handlers/ChatHandler.cpp"
PET_FILE="src/server/game/Entities/Pet/Pet.cpp"
DB_FILE="src/server/database/Database/Implementation/CharacterDatabase.h"
HUNTER_FILE="src/server/scripts/Spells/spell_hunter.cpp"
SPELL_FILE="src/server/game/Spells/Spell.cpp"
SPELL_EFFECTS_FILE="src/server/game/Spells/SpellEffects.cpp"
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

# Normalize defaults if patch already present but default is false
if grep -Eq "BeastMasterPlus.AllowMultipleUnslottedPets\", false" "$PET_FILE"; then
  echo "Updating AllowMultipleUnslottedPets default in Pet.cpp -> true"
  perl -pi -e 's/BeastMasterPlus[.]AllowMultipleUnslottedPets\", false/BeastMasterPlus.AllowMultipleUnslottedPets\", true/' "$PET_FILE"
fi

if grep -Eq "BeastMasterPlus.AllowMultipleUnslottedPets\", false" "$HUNTER_FILE"; then
  echo "Updating AllowMultipleUnslottedPets default in spell_hunter.cpp -> true"
  perl -pi -e 's/BeastMasterPlus[.]AllowMultipleUnslottedPets\", false/BeastMasterPlus.AllowMultipleUnslottedPets\", true/' "$HUNTER_FILE"
fi

if grep -Eq "BeastMasterPlus.AllowMultipleUnslottedPets\", false" "$SPELL_FILE"; then
  echo "Updating AllowMultipleUnslottedPets default in Spell.cpp -> true"
  perl -pi -e 's/BeastMasterPlus[.]AllowMultipleUnslottedPets\", false/BeastMasterPlus.AllowMultipleUnslottedPets\", true/' "$SPELL_FILE"
fi

if grep -Eq "BeastMasterPlus.AllowMultipleUnslottedPets\", false" "$SPELL_EFFECTS_FILE"; then
  echo "Updating AllowMultipleUnslottedPets default in SpellEffects.cpp -> true"
  perl -pi -e 's/BeastMasterPlus[.]AllowMultipleUnslottedPets\", false/BeastMasterPlus.AllowMultipleUnslottedPets\", true/' "$SPELL_EFFECTS_FILE"
fi

# Normalize Pet.cpp + CharacterDatabase for multi-unslotted slot preservation
python3 - <<'PY'
from pathlib import Path

# CharacterDatabase.h: add new statement enum if missing
db_h = Path("src/server/database/Database/Implementation/CharacterDatabase.h")
if db_h.exists():
    lines = db_h.read_text().splitlines()
    if not any("CHAR_UPD_CHAR_PET_SLOT_BY_OWNER_EXCEPT" in l for l in lines):
        for i, line in enumerate(lines):
            if "CHAR_UPD_CHAR_PET_SLOT_BY_ID" in line:
                lines.insert(i + 1, "    CHAR_UPD_CHAR_PET_SLOT_BY_OWNER_EXCEPT,")
                break
        db_h.write_text("\n".join(lines) + "\n")

# CharacterDatabase.cpp: add prepared statement if missing
db_cpp = Path("src/server/database/Database/Implementation/CharacterDatabase.cpp")
if db_cpp.exists():
    lines = db_cpp.read_text().splitlines()
    if not any("CHAR_UPD_CHAR_PET_SLOT_BY_OWNER_EXCEPT" in l for l in lines):
        for i, line in enumerate(lines):
            if "PrepareStatement(CHAR_UPD_CHAR_PET_SLOT_BY_ID" in line:
                lines.insert(i + 1, "    PrepareStatement(CHAR_UPD_CHAR_PET_SLOT_BY_OWNER_EXCEPT, \"UPDATE character_pet SET slot = ? WHERE owner = ? AND slot = ? AND id <> ?\", CONNECTION_ASYNC);")
                break
        db_cpp.write_text("\n".join(lines) + "\n")

# Pet.cpp: ensure allow-multiple branch updates slot=100 instead of deleting slot=0
pet_cpp = Path("src/server/game/Entities/Pet/Pet.cpp")
if pet_cpp.exists():
    lines = pet_cpp.read_text().splitlines()

    # ensure Config include
    if '#include "Config.h"' not in lines:
        for i, line in enumerate(lines):
            if line.strip() == '#include "Common.h"':
                lines.insert(i + 1, '#include "Config.h"')
                break

    # find SavePetToDB allow-multiple block
    block_start = None
    for i, line in enumerate(lines):
        if "prevent existence another hunter pet in PET_SAVE_AS_CURRENT" in line:
            block_start = i
            break
    if block_start is not None:
        if_idx = None
        for i in range(block_start, len(lines)):
            if "if (getPetType() == HUNTER_PET" in lines[i]:
                if_idx = i
                break
        if if_idx is not None:
            # find first '{' after if_idx
            brace_i = None
            for i in range(if_idx, len(lines)):
                if lines[i].strip() == "{":
                    brace_i = i
                    break
            if brace_i is not None:
                depth = 0
                end_i = None
                for i in range(brace_i, len(lines)):
                    if lines[i].strip() == "{":
                        depth += 1
                    if lines[i].strip() == "}":
                        depth -= 1
                        if depth == 0:
                            end_i = i
                            break
                if end_i is not None:
                    new_block = [
                        "        if (getPetType() == HUNTER_PET && (mode == PET_SAVE_AS_CURRENT || mode > PET_SAVE_LAST_STABLE_SLOT))",
                        "        {",
                        "            if (mode == PET_SAVE_AS_CURRENT)",
                        "            {",
                        "                stmt = CharacterDatabase.GetPreparedStatement(CHAR_UPD_CHAR_PET_SLOT_BY_OWNER_EXCEPT);",
                        "                stmt->SetData(0, uint8(PET_SAVE_NOT_IN_SLOT));",
                        "                stmt->SetData(1, ownerLowGUID);",
                        "                stmt->SetData(2, uint8(PET_SAVE_AS_CURRENT));",
                        "                stmt->SetData(3, m_charmInfo->GetPetNumber());",
                        "                trans->Append(stmt);",
                        "            }",
                        "        }",
                    ]
                    lines[if_idx:end_i + 1] = new_block
                    pet_cpp.write_text("\n".join(lines) + "\n")
PY

# Normalize spell_hunter.cpp tame check to allow multi-unslotted when no active pet
python3 - <<'PY'
from pathlib import Path

hunter_cpp = Path("src/server/scripts/Spells/spell_hunter.cpp")
if hunter_cpp.exists():
    lines = hunter_cpp.read_text().splitlines()

    # ensure Config include
    if '#include "Config.h"' not in lines:
        for i, line in enumerate(lines):
            if line.strip() == '#include "CellImpl.h"':
                lines.insert(i + 1, '#include "Config.h"')
                break

    # find the tame beast check block
    block_start = None
    for i, line in enumerate(lines):
        if "PetStable const* petStable = player->GetPetStable();" in line:
            block_start = i
            break

    if block_start is not None:
        # find "if (petStable)" block
        if_idx = None
        for i in range(block_start, len(lines)):
            if lines[i].strip() == "if (petStable)":
                if_idx = i
                break
        if if_idx is not None and if_idx + 1 < len(lines) and lines[if_idx + 1].strip() == "{":
            # find end of this if block
            depth = 0
            end_i = None
            for i in range(if_idx + 1, len(lines)):
                if lines[i].strip() == "{":
                    depth += 1
                if lines[i].strip() == "}":
                    depth -= 1
                    if depth == 0:
                        end_i = i
                        break
            if end_i is not None:
                new_block = [
                    "            if (petStable)",
                    "            {",
                    "                bool allowMultipleUnslotted = sConfigMgr->GetOption<bool>(\"BeastMasterPlus.AllowMultipleUnslottedPets\", true);",
                    "                if (petStable->CurrentPet)",
                    "                {",
                    "                    if (!allowMultipleUnslotted || player->GetPetGUID())",
                    "                        return SPELL_FAILED_ALREADY_HAVE_SUMMON;",
                    "                }",
                    "",
                    "                if (!allowMultipleUnslotted && petStable->GetUnslottedHunterPet())",
                    "                {",
                    "                    caster->SendTameFailure(PET_TAME_TOO_MANY);",
                    "                    return SPELL_FAILED_DONT_REPORT;",
                    "                }",
                    "            }",
                ]
                lines[if_idx:end_i + 1] = new_block
                hunter_cpp.write_text(\"\\n\".join(lines) + \"\\n\")
PY

# Normalize SpellEffects.cpp: remove mis-inserted block in EffectJump and ensure tame path normalization exists
if [ -f "$SPELL_EFFECTS_FILE" ]; then
  python3 - <<'PY'
from pathlib import Path

path = Path("src/server/game/Spells/SpellEffects.cpp")
text = path.read_text().splitlines()

# Ensure Config include
if '#include "Config.h"' not in text:
    for i, line in enumerate(text):
        if line.strip() == '#include "Common.h"':
            text.insert(i + 1, '#include "Config.h"')
            break

def find_func(name):
    for i, line in enumerate(text):
        if line.startswith(f"void Spell::{name}"):
            return i
    return None

def find_block(start):
    # find first '{' after start, then match braces
    brace = None
    for i in range(start, len(text)):
        if text[i].strip() == '{':
            brace = i
            break
    if brace is None:
        return None, None
    depth = 0
    for i in range(brace, len(text)):
        if text[i].strip() == '{':
            depth += 1
        if text[i].strip() == '}':
            depth -= 1
            if depth == 0:
                return brace, i
    return None, None

# Remove wrong block injected into EffectJump
jump_start = find_func("EffectJump")
if jump_start is not None:
    jb, je = find_block(jump_start)
    if jb is not None:
        # find block inside function that contains AllowMultipleUnslottedPets
        i = jb
        while i <= je:
            if "AllowMultipleUnslottedPets" in text[i]:
                # remove enclosing block: search upward for '{' at same indent and forward to matching '}'
                # find opening brace for this block
                open_i = None
                for j in range(i, jb, -1):
                    if text[j].strip() == '{':
                        open_i = j
                        break
                if open_i is not None:
                    depth = 0
                    close_i = None
                    for k in range(open_i, je + 1):
                        if text[k].strip() == '{':
                            depth += 1
                        if text[k].strip() == '}':
                            depth -= 1
                            if depth == 0:
                                close_i = k
                                break
                    if close_i is not None:
                        del text[open_i:close_i + 1]
                break
            i += 1

# Ensure tame creature block normalization
tame_start = find_func("EffectTameCreature")
if tame_start is not None:
    tb, te = find_block(tame_start)
    if tb is not None:
        # find the if (m_caster->IsPlayer()) block within tame
        marker = "    if (m_caster->IsPlayer())"
        idx = None
        for i in range(tame_start, te + 1):
            if text[i] == marker:
                idx = i
                break
        if idx is not None and idx + 1 < len(text) and text[idx + 1].strip() == '{':
            # find end of this if block
            depth = 0
            end = None
            for i in range(idx + 1, te + 1):
                if text[i].strip() == '{':
                    depth += 1
                if text[i].strip() == '}':
                    depth -= 1
                    if depth == 0:
                        end = i
                        break
            if end is not None:
                block = "\n".join(text[idx:end + 1])
                if "SavePetToDB(PET_SAVE_AS_CURRENT)" in block:
                    new_block = [
                        "    if (m_caster->IsPlayer())",
                        "    {",
                        "        ObjectGuid::LowType ownerLow = m_caster->GetGUID().GetCounter();",
                        "        uint32 newPetNumber = pet->GetCharmInfo() ? pet->GetCharmInfo()->GetPetNumber() : 0;",
                        "        if (newPetNumber)",
                        "            CharacterDatabase.Execute(",
                        "                \"UPDATE character_pet SET slot = 100 WHERE owner = {} AND slot = 0 AND PetType = 1 AND id <> {}\",",
                        "                ownerLow, newPetNumber);",
                        "        pet->SavePetToDB(PET_SAVE_AS_CURRENT);",
                        "        m_caster->ToPlayer()->PetSpellInitialize();",
                        "    }",
                    ]
                    text[idx:end + 1] = new_block

path.write_text("\n".join(text) + "\n")
PY
fi

HOOK_PRESENT=0
DECL_PRESENT=0
PET_PATCH_PRESENT=0
DB_PATCH_PRESENT=0
TAME_PATCH_PRESENT=0
SPELL_PATCH_PRESENT=0
SPELL_EFFECTS_PATCH_PRESENT=0

grep -Eq "AddonMessageRouter::Handle" "$CORE_FILE" && HOOK_PRESENT=1
grep -Eq "namespace[[:space:]]+AddonMessageRouter" "$CORE_FILE" && DECL_PRESENT=1
grep -Eq "SavePetStateWithoutSlot" "$PET_FILE" && PET_PATCH_PRESENT=1
grep -Eq "CHAR_UPD_CHAR_PET_NO_SLOT" "$DB_FILE" && DB_PATCH_PRESENT=1
grep -Eq "BeastMasterPlus.AllowMultipleUnslottedPets" "$HUNTER_FILE" && TAME_PATCH_PRESENT=1
grep -Eq "BeastMasterPlus.AllowMultipleUnslottedPets" "$SPELL_FILE" && SPELL_PATCH_PRESENT=1
if [ -f "$SPELL_EFFECTS_FILE" ]; then
  # After normalization, treat SpellEffects as patched
  SPELL_EFFECTS_PATCH_PRESENT=1
fi

if [ "$FORCE" -eq 0 ] && [ "$HOOK_PRESENT" -eq 1 ] && [ "$DECL_PRESENT" -eq 1 ] && [ "$PET_PATCH_PRESENT" -eq 1 ] && [ "$DB_PATCH_PRESENT" -eq 1 ] && [ "$TAME_PATCH_PRESENT" -eq 1 ] && [ "$SPELL_PATCH_PRESENT" -eq 1 ] && [ "$SPELL_EFFECTS_PATCH_PRESENT" -eq 1 ]; then
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
if [ "$PET_PATCH_PRESENT" -eq 0 ] || [ "$DB_PATCH_PRESENT" -eq 0 ] || [ "$TAME_PATCH_PRESENT" -eq 0 ] || [ "$SPELL_PATCH_PRESENT" -eq 0 ] || [ "$SPELL_EFFECTS_PATCH_PRESENT" -eq 0 ]; then
  echo "Applying remaining BeastMasterPlus core hunks (excluding ChatHandler)..."
  APPLIED=0

  if [ "$PET_PATCH_PRESENT" -eq 0 ]; then
    if git apply --include=src/server/game/Entities/Pet/Pet.cpp --include=src/server/game/Entities/Pet/Pet.h "$PATCH"; then
      APPLIED=1
    else
      echo "ERROR: Pet hunks failed to apply."
      exit 1
    fi
  fi

  if [ "$DB_PATCH_PRESENT" -eq 0 ]; then
    if git apply --include=src/server/database/Database/Implementation/CharacterDatabase.cpp --include=src/server/database/Database/Implementation/CharacterDatabase.h "$PATCH"; then
      APPLIED=1
    else
      echo "ERROR: CharacterDatabase hunks failed to apply."
      exit 1
    fi
  fi

  if [ "$TAME_PATCH_PRESENT" -eq 0 ]; then
    if git apply --include=src/server/scripts/Spells/spell_hunter.cpp "$PATCH"; then
      APPLIED=1
    else
      echo "ERROR: spell_hunter hunks failed to apply."
      exit 1
    fi
  fi

  if [ "$SPELL_PATCH_PRESENT" -eq 0 ]; then
    if git apply --include=src/server/game/Spells/Spell.cpp "$PATCH"; then
      APPLIED=1
    else
      echo "ERROR: Spell.cpp hunks failed to apply."
      exit 1
    fi
  fi

  if [ "$SPELL_EFFECTS_PATCH_PRESENT" -eq 0 ]; then
    if git apply --include=src/server/game/Spells/SpellEffects.cpp "$PATCH"; then
      APPLIED=1
    else
      echo "ERROR: SpellEffects.cpp hunks failed to apply."
      exit 1
    fi
  fi

  if [ "$APPLIED" -eq 1 ]; then
    echo "Remaining hunks applied."
  fi
fi

# Insert hook call if missing
if [ "$HOOK_PRESENT" -eq 0 ]; then
  echo "Inserting AddonMessageRouter hook call..."
  perl -0777 -i -pe 's/(AddonChannelCommandHandler\(this\)\.ParseCommands\(msg\.c_str\(\)\)\n\s*return;\n)/$1            if (AddonMessageRouter::Handle(this, msg))\n                return;\n/s' "$CORE_FILE"
fi
