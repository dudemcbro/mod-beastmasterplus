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

3) Configure (optional):
   cp modules/mod-beastmasterplus/conf/mod_beastmasterplus.conf.dist \
      env/dist/etc/mod_beastmasterplus.conf

4) Build:
   ./acore.sh compiler

5) Apply SQL (optional test data only; dev-only, can delete pets for @owner):
   sql/world/base/optional_seed_bmp_test_pets.sql

## Notes
- This module intentionally does not modify stable limits
- All pet data remains in character_pet
- Addon UI is required for interaction
- AddonMessageRouter is owned by this module (core only forward-declares it)
- SQL seed is for testing only; do not use on production data
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

- sql/world/base/optional_seed_bmp_test_pets.sql  
  Optional test data only (not required for normal operation)

- patches/  
  Combined core patch (addon routing + pet-save changes) and apply script
