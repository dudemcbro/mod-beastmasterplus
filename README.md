# mod-beastmasterplus

BeastMasterPlus (HunterStablePlus) module for AzerothCore WotLK.

## What this module does
- Server authoritative extended hunter pet storage
- No retame
- No pet delete or recreate
- Pets persist 1:1 in DB
- Addon driven UI over CHAT_MSG_ADDON
- Avoids stable logic, slots, and NPC flows
- Owns the AddonMessageRouter implementation (core only forward-declares it)

## Requirements
- AzerothCore WotLK (3.3.5a). The core patch was checked against the
  mod-playerbots fork of azerothcore-wotlk (commit 2d2a522, January 2026).
- bash, git, python3 and perl on the machine that applies the core patch.
- The BeastmasterPlus client addon (see below).

## Installation (fresh server)

1) Copy module into AzerothCore:
   modules/mod-beastmasterplus

2) Apply required core patch (one time):
   cd /path/to/azerothcore
   modules/mod-beastmasterplus/patches/apply-core-addon-hook.sh
   # Applies the full BeastMasterPlus core patch (addon routing + pet-save changes).
   # The AddonMessageRouter implementation is provided by this module:
   #   src/BmpAddonMessageRouter.h / src/BmpAddonMessageRouter.cpp
   # If a partial hook already exists, the script will add any missing pieces.
   # Use --force to re-apply if core changed or patch defaults were updated:
   #   modules/mod-beastmasterplus/patches/apply-core-addon-hook.sh --force
   # Run it from the AzerothCore repo root. It is safe to run more than once.
   # Besides core-beastmasterplus.normalized.patch it edits these core files
   # directly (review with `git diff` afterwards):
   #   Handlers/ChatHandler.cpp, Handlers/PetHandler.cpp, Entities/Pet/Pet.cpp,
   #   Entities/Pet/Pet.h, Entities/Player/Player.cpp, Entities/Unit/Unit.cpp,
   #   Spells/Spell.cpp, Spells/SpellEffects.cpp, scripts/Spells/spell_hunter.cpp,
   #   database/.../CharacterDatabase.cpp and CharacterDatabase.h
   # If your core already ships its own AddonMessageRouter implementation
   # (some custom forks do), keep only one of the two implementations or the
   # symbols AddonMessageRouter::RegisterHandler/Handle are defined twice.

3) Configure (optional but recommended):
   cp modules/mod-beastmasterplus/conf/mod_beastmasterplus.conf.dist \
      env/dist/etc/modules/mod_beastmasterplus.conf
   # REQUIRED for extended storage: allow multiple unslotted hunter pets
   # BeastMasterPlus.AllowMultipleUnslottedPets = 1
   # If this config is not loaded by the server, the core patch now defaults
   # AllowMultipleUnslottedPets to true to avoid deleting dismissed pets.

4) Build:
   ./acore.sh compiler

5) SQL: none is required. The module does not add tables and nothing is
   auto-imported. For development only, sql/characters/optional_seed_bmp_test_pets.sql
   seeds test pets into the CHARACTERS database for one character. It deletes
   that character's existing pets first; read the header before running it.

## Notes
- This module intentionally does not modify stable limits
- All pet data remains in character_pet
- Addon UI is required for interaction
- AddonMessageRouter is owned by this module (core only forward-declares it)
- SQL seed is for testing only; do not use on production data
- If AllowMultipleUnslottedPets is 0, dismissed pets can be removed when taming new ones
- If AllowMultipleUnslottedPets is 1, the hunter pet action "Abandon" is treated as a dismiss
  (PET_SAVE_NOT_IN_SLOT / slot 100) to prevent losing pets while taming
- Dismiss is available via the UI button or `/bmp dismiss <petNumber>` (not permanent)

## Client Addon Installation (required)

This module requires the BeastMasterPlus addon on the client.

1) Copy the addon folder to the WoW client:
   Interface/AddOns/BeastmasterPlus

   The folder is provided in this module:
   modules/mod-beastmasterplus/data/BeastmasterPlus

2) Ensure the addon files exist:
   - BeastmasterPlus.toc
   - BeastmasterPlus.lua
   - BeastmasterPlusUI.lua

3) Enable the addon at the character select screen.

## Notes
- The server module will load without the addon, but no UI or interaction is possible
- All user interaction is addon UI only
- Communication uses CHAT_MSG_ADDON with prefix BMP
- Dismiss is available via the UI button or `/bmp dismiss <petNumber>`

## Layout

- src/  
  Server-side module source code

- data/BeastmasterPlus/  
  Required client addon (copy to Interface/AddOns/BeastmasterPlus)

- conf/  
  Module configuration templates

- sql/characters/optional_seed_bmp_test_pets.sql  
  Optional dev/test data for the characters DB (not required for normal operation)

- patches/  
  Core patch (addon routing + pet-save changes) and the apply script that
  applies it and performs the remaining scripted core edits
