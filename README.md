# mod-beastmasterplus

BeastMasterPlus (HunterStablePlus) module for AzerothCore WotLK.

## What this module does
- Server authoritative extended hunter pet storage
- No retame
- No pet delete or recreate
- Pets persist 1:1 in DB
- Addon driven UI over CHAT_MSG_ADDON
- Avoids stable logic, slots, and NPC flows

## Installation (fresh server)

1) Copy module into AzerothCore:
   modules/mod-beastmasterplus

2) Apply required core hook (one time):
   cd /path/to/azerothcore
   modules/mod-beastmasterplus/patches/apply-core-addon-hook.sh

3) Configure (optional):
   cp modules/mod-beastmasterplus/conf/mod_beastmasterplus.conf.dist \
      env/dist/etc/mod_beastmasterplus.conf

4) Build:
   ./acore.sh compiler

5) Apply SQL (optional test data only):
   sql/world/base/optional_seed_bmp_test_pets.sql

## Notes
- This module intentionally does not modify stable limits
- All pet data remains in character_pet
- Addon UI is required for interaction

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

## Layout

- src/  
  Server-side module source code

- data/BeastmasterPlus/  
  Required client addon (copy to Interface/AddOns/BeastmasterPlus)

- conf/  
  Module configuration templates

- sql/world/base/optional_seed_bmp_test_pets.sql  
  Optional test data only (not required for normal operation)

- tools/  
  Developer and audit utilities

- patches/  
  Minimal required core hook (LANG_ADDON routing)

