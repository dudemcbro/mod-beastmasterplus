# Installation

This module requires small core patches for addon routing and pet persistence.

## 1) Copy module
Place `mod-bmp-v1` under your AzerothCore `modules/` folder.

## 2) Apply core patches
From the AzerothCore root:
```
git apply modules/mod-bmp-v1/patches/core-addon-router.patch
git apply modules/mod-bmp-v1/patches/core-pet-save.patch
```

If you don’t use git, apply the patch manually or use `patch -p1`.

## 3) Configure & build
Add this to `worldserver.conf`:
```
BeastMasterPlus.AllowMultipleUnslottedPets = 1
```

Re-run CMake and rebuild `worldserver` with modules enabled.

## 4) Optional test data
Seed 99 non‑exotic pets for a character:
```
SET @owner := <character_guid_low>;
SET @n := 99;
SOURCE modules/mod-bmp-v1/sql/seed_bmp_test_pets.sql;
```

## Notes
- BMP uses `character_pet.id` as the petNumber (opaque).
- Outbound addon messages are sent as `CHAT_MSG_WHISPER` with `LANG_ADDON`.
