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

run_py() {
  local tmp pycache
  tmp="$(mktemp)"
  pycache="$(mktemp -d)"
  cat > "$tmp"
  if ! PYTHONPYCACHEPREFIX="$pycache" python3 -m py_compile "$tmp"; then
    echo "ERROR: python syntax check failed in patch helper." >&2
    rm -f "$tmp"
    rm -rf "$pycache"
    exit 1
  fi
  if ! PYTHONPYCACHEPREFIX="$pycache" python3 "$tmp"; then
    rm -f "$tmp"
    rm -rf "$pycache"
    exit 1
  fi
  rm -f "$tmp"
  rm -rf "$pycache"
}

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
run_py <<'PY'
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
                        "                LOG_INFO(\"module.bmp\", \"BMP SAVE: owner={} petNumber={} mode={} move other slot=0 -> NOT_IN_SLOT\",",
                        "                    ownerLowGUID, m_charmInfo->GetPetNumber(), uint32(mode));",
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
run_py <<'PY'
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
    if '#include "Log.h"' not in lines:
        for i, line in enumerate(lines):
            if line.strip() == '#include "Config.h"':
                lines.insert(i + 1, '#include "Log.h"')
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
                    "                uint32 targetEntry = GetExplTargetUnit() ? GetExplTargetUnit()->GetEntry() : 0;",
                    "                LOG_INFO(\"module.bmp\", \"BMP TAME CHECK: player={} guidLow={} targetEntry={} activePetGuid={} currentPet={} unslottedCount={}\",",
                    "                    player->GetName(), player->GetGUID().GetCounter(), targetEntry, player->GetPetGUID().GetCounter(),",
                    "                    petStable->CurrentPet ? 1 : 0, petStable->UnslottedPets.size());",
                    "                bool allowMultipleUnslotted = sConfigMgr->GetOption<bool>(\"BeastMasterPlus.AllowMultipleUnslottedPets\", true);",
                    "                if (petStable->CurrentPet)",
                    "                {",
                    "                    if (!allowMultipleUnslotted || player->GetPetGUID())",
                    "                    {",
                    "                        LOG_INFO(\"module.bmp\", \"BMP TAME BLOCKED: player={} guidLow={} allowMultiple={} currentPet=1 activePetGuid={}\",",
                    "                            player->GetName(), player->GetGUID().GetCounter(), allowMultipleUnslotted, player->GetPetGUID().GetCounter());",
                    "                        return SPELL_FAILED_ALREADY_HAVE_SUMMON;",
                    "                    }",
                    "                }",
                    "",
                    "                if (!allowMultipleUnslotted && petStable->GetUnslottedHunterPet())",
                    "                {",
                    "                    LOG_INFO(\"module.bmp\", \"BMP TAME BLOCKED: player={} guidLow={} allowMultiple={} unslottedCount={}\",",
                    "                        player->GetName(), player->GetGUID().GetCounter(), allowMultipleUnslotted, petStable->UnslottedPets.size());",
                    "                    caster->SendTameFailure(PET_TAME_TOO_MANY);",
                    "                    return SPELL_FAILED_DONT_REPORT;",
                    "                }",
                    "            }",
                ]
                lines[if_idx:end_i + 1] = new_block
                hunter_cpp.write_text("\n".join(lines) + "\n")
PY

# Add tame start/fail logging in spell_hunter.cpp
run_py <<'PY'
from pathlib import Path

hunter_cpp = Path("src/server/scripts/Spells/spell_hunter.cpp")
if hunter_cpp.exists():
    text = hunter_cpp.read_text()

    if "BMP TAME CHECK START" not in text:
        needle = "        Player* player = GetCaster()->ToPlayer();\n"
        insert = (
            "        Player* player = GetCaster()->ToPlayer();\n"
            "        uint32 targetEntry = GetExplTargetUnit() ? GetExplTargetUnit()->GetEntry() : 0;\n"
            "        LOG_INFO(\"module.bmp\", \"BMP TAME CHECK START: player={} guidLow={} targetEntry={} activePetGuid={}\",\n"
            "            player->GetName(), player->GetGUID().GetCounter(), targetEntry, player->GetPetGUID().GetCounter());\n"
        )
        if needle in text:
            text = text.replace(needle, insert)

    if "BMP TAME FAIL:" not in text:
        replacements = {
            "            player->SendTameFailure(PET_TAME_TOO_HIGHLEVEL);":
                "            LOG_INFO(\"module.bmp\", \"BMP TAME FAIL: TOO_HIGHLEVEL player={} guidLow={}\", player->GetName(), player->GetGUID().GetCounter());\n"
                "            player->SendTameFailure(PET_TAME_TOO_HIGHLEVEL);",
            "                player->SendTameFailure(PET_TAME_CANT_CONTROL_EXOTIC);":
                "                LOG_INFO(\"module.bmp\", \"BMP TAME FAIL: CANT_CONTROL_EXOTIC player={} guidLow={}\", player->GetName(), player->GetGUID().GetCounter());\n"
                "                player->SendTameFailure(PET_TAME_CANT_CONTROL_EXOTIC);",
            "                player->SendTameFailure(PET_TAME_NOT_TAMEABLE);":
                "                LOG_INFO(\"module.bmp\", \"BMP TAME FAIL: NOT_TAMEABLE player={} guidLow={}\", player->GetName(), player->GetGUID().GetCounter());\n"
                "                player->SendTameFailure(PET_TAME_NOT_TAMEABLE);",
            "                player->SendTameFailure(PET_TAME_ANOTHER_SUMMON_ACTIVE);":
                "                LOG_INFO(\"module.bmp\", \"BMP TAME FAIL: ANOTHER_SUMMON_ACTIVE player={} guidLow={}\", player->GetName(), player->GetGUID().GetCounter());\n"
                "                player->SendTameFailure(PET_TAME_ANOTHER_SUMMON_ACTIVE);",
            "                player->SendTameFailure(PET_TAME_CREATURE_ALREADY_OWNED);":
                "                LOG_INFO(\"module.bmp\", \"BMP TAME FAIL: CREATURE_ALREADY_OWNED player={} guidLow={}\", player->GetName(), player->GetGUID().GetCounter());\n"
                "                player->SendTameFailure(PET_TAME_CREATURE_ALREADY_OWNED);",
            "            player->SendTameFailure(PET_TAME_INVALID_CREATURE);":
                "            LOG_INFO(\"module.bmp\", \"BMP TAME FAIL: INVALID_CREATURE player={} guidLow={}\", player->GetName(), player->GetGUID().GetCounter());\n"
                "            player->SendTameFailure(PET_TAME_INVALID_CREATURE);",
        }
        for k, v in replacements.items():
            text = text.replace(k, v)

    hunter_cpp.write_text(text)
PY

# Normalize SpellEffects.cpp: remove mis-inserted block in EffectJump and ensure tame path normalization exists
if [ -f "$SPELL_EFFECTS_FILE" ]; then
  run_py <<'PY'
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

# Insert tame fail logs for common early returns
def logify_return(cond_line, reason):
    for i in range(tame_start, te + 1):
        if text[i].strip() == cond_line and i + 1 <= te and text[i + 1].strip() == "return;":
            text[i:i + 2] = [
                text[i],
                "    {",
                "        if (m_caster->IsPlayer())",
                f"            LOG_INFO(\"module.bmp\", \"BMP TAME FAIL: {reason} player={{}} guidLow={{}}\",",
                "                m_caster->GetName(), m_caster->GetGUID().GetCounter());",
                "        return;",
                "    }",
            ]
            break

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
        # add early-return logs
        logify_return("if (m_caster->GetPetGUID())", "ALREADY_HAVE_PET")
        logify_return("if (!unitTarget)", "NO_TARGET")
        logify_return("if (!unitTarget->IsCreature())", "TARGET_NOT_CREATURE")
        logify_return("if (creatureTarget->IsPet())", "TARGET_IS_PET")
        logify_return("if (!m_caster->IsClass(CLASS_HUNTER, CLASS_CONTEXT_PET))", "NOT_HUNTER")

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
                        "        LOG_INFO(\"module.bmp\", \"BMP TAME START: player={} guidLow={} targetEntry={} targetGuid={} activePetGuid={} tempUnsummoned={}\",",
                        "            m_caster->GetName(), ownerLow, creatureTarget->GetEntry(), creatureTarget->GetGUID().GetCounter(),",
                        "            m_caster->GetPetGUID().GetCounter(), m_caster->ToPlayer()->GetTemporaryUnsummonedPetNumber());",
                        "        LOG_INFO(\"module.bmp\", \"BMP TAME SAVE: player={} guidLow={} newPetNumber={}\",",
                        "            m_caster->GetName(), ownerLow, newPetNumber);",
                        "        if (newPetNumber)",
                        "            CharacterDatabase.Execute(",
                        "                \"UPDATE character_pet SET slot = 100 WHERE owner = {} AND slot = 0 AND PetType = 1 AND id <> {}\",",
                        "                ownerLow, newPetNumber);",
                        "        pet->SavePetToDB(PET_SAVE_AS_CURRENT);",
                        "        m_caster->ToPlayer()->PetSpellInitialize();",
                        "        if (QueryResult q = CharacterDatabase.Query(\"SELECT COUNT(*), SUM(slot = 0), SUM(slot = 100) FROM character_pet WHERE owner = {}\", ownerLow))",
                        "        {",
                        "            Field* f = q->Fetch();",
                        "            LOG_INFO(\"module.bmp\", \"BMP TAME DB: owner={} total={} slot0={} slot100={}\",",
                        "                ownerLow, f[0].Get<uint64>(), f[1].Get<uint64>(), f[2].Get<uint64>());",
                        "        }",
                        "    }",
                    ]
                    text[idx:end + 1] = new_block

path.write_text("\n".join(text) + "\n")
PY
fi

# Unit.cpp: allow multiple unslotted pets when config enabled
run_py <<'PY'
from pathlib import Path

path = Path("src/server/game/Entities/Unit/Unit.cpp")
if path.exists():
    lines = path.read_text().splitlines()
    changed = False

    # ensure Config include
    if '#include "Config.h"' not in lines:
        for i, line in enumerate(lines):
            if line.strip() == '#include "Common.h"':
                lines.insert(i + 1, '#include "Config.h"')
                changed = True
                break

    text = "\n".join(lines)
    if "BeastMasterPlus.AllowMultipleUnslottedPets" not in text:
        old = (
            "    PetStable& petStable = player->GetOrInitPetStable();\n"
            "    if (petStable.CurrentPet || petStable.GetUnslottedHunterPet())\n"
            "        return false;\n"
        )
        new = (
            "    PetStable& petStable = player->GetOrInitPetStable();\n"
            "    bool allowMultipleUnslotted = sConfigMgr->GetOption<bool>(\"BeastMasterPlus.AllowMultipleUnslottedPets\", true);\n"
            "    if (!allowMultipleUnslotted)\n"
            "    {\n"
            "        if (petStable.CurrentPet || petStable.GetUnslottedHunterPet())\n"
            "            return false;\n"
            "    }\n"
            "    else\n"
            "    {\n"
            "        if (petStable.CurrentPet && !player->GetPetGUID())\n"
            "        {\n"
            "            petStable.UnslottedPets.push_back(std::move(*petStable.CurrentPet));\n"
            "            petStable.CurrentPet.reset();\n"
            "        }\n"
            "        if (player->GetPetGUID())\n"
            "            return false;\n"
            "    }\n"
        )
        if old in text:
            text = text.replace(old, new)
            changed = True

    if changed:
        path.write_text(text + "\n")
PY

# Add logging for dismiss + RemovePet + SavePetToDB early exits
run_py <<'PY'
from pathlib import Path

# SpellEffects.cpp: log regular dismiss pet
se = Path("src/server/game/Spells/SpellEffects.cpp")
if se.exists():
    lines = se.read_text().splitlines()
    if "BMP DISMISS:" not in se.read_text():
        start = None
        for i, line in enumerate(lines):
            if line.startswith("void Spell::EffectDismissPet"):
                start = i
                break
        if start is not None:
            for i in range(start, min(len(lines), start + 120)):
                if "Pet* pet = unitTarget->ToPet();" in lines[i]:
                    insert = [
                        "    if (Player* owner = pet->GetOwner() ? pet->GetOwner()->ToPlayer() : nullptr)",
                        "    {",
                        "        uint32 petNumber = pet->GetCharmInfo() ? pet->GetCharmInfo()->GetPetNumber() : 0;",
                        "        LOG_INFO(\"module.bmp\", \"BMP DISMISS: player={} guidLow={} petNumber={}\",",
                        "            owner->GetName(), owner->GetGUID().GetCounter(), petNumber);",
                        "    }",
                    ]
                    lines[i+1:i+1] = insert
                    se.write_text("\n".join(lines) + "\n")
                    break

# Player.cpp: log RemovePet
player_cpp = Path("src/server/game/Entities/Player/Player.cpp")
if player_cpp.exists():
    text = player_cpp.read_text()
    if "BMP RemovePet" not in text:
        needle = """        if (pet->m_removed)
            return;
    }

    if (returnreagent"""
        if needle in text:
            insert = """        if (pet->IsHunterPet())
        {
            uint32 petNumber = pet->GetCharmInfo() ? pet->GetCharmInfo()->GetPetNumber() : 0;
            LOG_INFO(\"module.bmp\", \"BMP RemovePet: player={} guidLow={} petNumber={} mode={} returnreagent={}\",
                GetName(), GetGUID().GetCounter(), petNumber, uint32(mode), returnreagent);
        }
    }

    if (returnreagent"""
            text = text.replace(needle, insert)
            player_cpp.write_text(text)

    text = player_cpp.read_text()
    if "BMP RemovePet (no active)" not in text:
        needle2 = """        if (mode == PET_SAVE_NOT_IN_SLOT && m_petStable && m_petStable->CurrentPet)
        {
            // Handle removing pet while it is in \"temporarily unsummoned\" state, for example on mount
"""
        if needle2 in text:
            insert2 = """        if (mode == PET_SAVE_NOT_IN_SLOT && m_petStable && m_petStable->CurrentPet)
        {
            LOG_INFO(\"module.bmp\", \"BMP RemovePet (no active): player={} guidLow={} petNumber={} mode={}\",
                GetName(), GetGUID().GetCounter(), m_petStable->CurrentPet->PetNumber, uint32(mode));
            // Handle removing pet while it is in \"temporarily unsummoned\" state, for example on mount
"""
            text = text.replace(needle2, insert2)
            player_cpp.write_text(text)

# Pet.cpp: log SavePetToDB early exits + temp unsummoned
pet_cpp = Path("src/server/game/Entities/Pet/Pet.cpp")
if pet_cpp.exists():
    text = pet_cpp.read_text()
    # replace older log signature (mode may be out of scope)
    if "BMP SavePetToDB skip: owner={} mode={}" in text:
        text = text.replace(
            'LOG_INFO(\"module.bmp\", \"BMP SavePetToDB skip: owner={} mode={} loading={} entry={} controlled={} removed={} charmInfo={}\",\\n'
            '                owner->GetGUID().GetCounter(), uint32(mode), m_loading, GetEntry(), isControlled(), m_removed, m_charmInfo ? 1 : 0);',
            'LOG_INFO(\"module.bmp\", \"BMP SavePetToDB skip: owner={} loading={} entry={} controlled={} removed={} charmInfo={}\",\\n'
            '                owner->GetGUID().GetCounter(), m_loading, GetEntry(), isControlled(), m_removed, m_charmInfo ? 1 : 0);'
        )
        pet_cpp.write_text(text)

    if "BMP SavePetToDB skip" not in text:
        needle = """    Player* owner = GetOwner()->ToPlayer();
    if (!owner || m_loading || !GetEntry() || !isControlled() || m_removed || !m_charmInfo)
        return;
"""
        if needle in text:
            repl = """    Player* owner = GetOwner()->ToPlayer();
    if (!owner || m_loading || !GetEntry() || !isControlled() || m_removed || !m_charmInfo)
    {
        if (owner && getPetType() == HUNTER_PET)
            LOG_INFO(\"module.bmp\", \"BMP SavePetToDB skip: owner={} loading={} entry={} controlled={} removed={} charmInfo={}\",
                owner->GetGUID().GetCounter(), m_loading, GetEntry(), isControlled(), m_removed, m_charmInfo ? 1 : 0);
        return;
    }
"""
            text = text.replace(needle, repl)
            pet_cpp.write_text(text)

    text = pet_cpp.read_text()
    if "BMP SavePetToDB temp unsummoned" not in text:
        needle2 = """    if (mode == PET_SAVE_AS_CURRENT && owner->GetTemporaryUnsummonedPetNumber() &&
            owner->GetTemporaryUnsummonedPetNumber() != m_charmInfo->GetPetNumber())
    {
        // pet will lost anyway at restore temporary unsummoned
        if (getPetType() == HUNTER_PET)
            return;
"""
        if needle2 in text:
            repl2 = """    if (mode == PET_SAVE_AS_CURRENT && owner->GetTemporaryUnsummonedPetNumber() &&
            owner->GetTemporaryUnsummonedPetNumber() != m_charmInfo->GetPetNumber())
    {
        // pet will lost anyway at restore temporary unsummoned
        if (getPetType() == HUNTER_PET)
        {
            LOG_INFO(\"module.bmp\", \"BMP SavePetToDB temp unsummoned: owner={} tempPet={} currentPet={} mode={}\",
                owner->GetGUID().GetCounter(), owner->GetTemporaryUnsummonedPetNumber(), m_charmInfo->GetPetNumber(), uint32(mode));
            return;
        }
"""
            text = text.replace(needle2, repl2)
            pet_cpp.write_text(text)
PY

# PetHandler.cpp: log explicit abandon paths (pet action + opcode)
run_py <<'PY'
from pathlib import Path
import re

pet_handler = Path("src/server/game/Handlers/PetHandler.cpp")
if pet_handler.exists():
    text = pet_handler.read_text()
    if '#include "Config.h"' not in text:
        # Insert Config include after Common include (handle any line endings)
        text, n = re.subn(r'(#include "Common\\.h"[^\\n]*\\n)', r'\\1#include "Config.h"\\n', text, count=1)
        if n == 0:
            text, _ = re.subn(r'(#include "[^"]+"[^\\n]*\\n)', r'\\1#include "Config.h"\\n', text, count=1)
        pet_handler.write_text(text)

    text = pet_handler.read_text()
    if "BMP ABANDON (pet action)->DISMISS" not in text:
        lines = text.splitlines()
        if_idx = None
        indent = ""
        for i, line in enumerate(lines):
            if "if (pet->ToPet()->getPetType() == HUNTER_PET)" in line:
                if_idx = i
                indent = line[:len(line) - len(line.lstrip())]
                break
        if if_idx is not None:
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
                        f"{indent}if (pet->ToPet()->getPetType() == HUNTER_PET)",
                        f"{indent}{{",
                        f"{indent}    uint32 petNumber = pet->ToPet()->GetCharmInfo() ? pet->ToPet()->GetCharmInfo()->GetPetNumber() : 0;",
                        f"{indent}    bool allowMultiple = sConfigMgr->GetOption<bool>(\"BeastMasterPlus.AllowMultipleUnslottedPets\", true);",
                        f"{indent}    if (allowMultiple)",
                        f"{indent}    {{",
                        f"{indent}        LOG_INFO(\"module.bmp\", \"BMP ABANDON (pet action)->DISMISS: player={{}} guidLow={{}} petNumber={{}}\",",
                        f"{indent}            GetPlayer()->GetName(), GetPlayer()->GetGUID().GetCounter(), petNumber);",
                        f"{indent}        GetPlayer()->RemovePet(pet->ToPet(), PET_SAVE_NOT_IN_SLOT);",
                        f"{indent}    }}",
                        f"{indent}    else",
                        f"{indent}    {{",
                        f"{indent}        LOG_INFO(\"module.bmp\", \"BMP ABANDON (pet action): player={{}} guidLow={{}} petNumber={{}}\",",
                        f"{indent}            GetPlayer()->GetName(), GetPlayer()->GetGUID().GetCounter(), petNumber);",
                        f"{indent}        GetPlayer()->RemovePet(pet->ToPet(), PET_SAVE_AS_DELETED);",
                        f"{indent}    }}",
                        f"{indent}}}",
                    ]
                    lines[if_idx:end_i + 1] = new_block
                    pet_handler.write_text("\n".join(lines) + "\n")

    text = pet_handler.read_text()
    if "BMP ABANDON (opcode)" not in text:
        old2 = """            _player->RemovePet(pet->ToPet(), PET_SAVE_AS_DELETED);
"""
        insert = """            uint32 petNumber = pet->ToPet()->GetCharmInfo() ? pet->ToPet()->GetCharmInfo()->GetPetNumber() : 0;
            LOG_INFO("module.bmp", "BMP ABANDON (opcode): player={} guidLow={} petNumber={}",
                _player->GetName(), _player->GetGUID().GetCounter(), petNumber);
            _player->RemovePet(pet->ToPet(), PET_SAVE_AS_DELETED);
"""
        if old2 in text:
            text = text.replace(old2, insert)
            pet_handler.write_text(text)
PY
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
