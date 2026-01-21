# Uninstall / Revert

## 1) Remove module
Delete the module folder:
```
rm -rf modules/mod-bmp-v1
```

## 2) Revert core patch
From the AzerothCore root:
```
git apply -R modules/mod-bmp-v1/patches/core-addon-router.patch
```
If the module folder is already removed, undo these manually:
- Delete `src/server/game/Chat/AddonMessageRouter.h`
- Delete `src/server/game/Chat/AddonMessageRouter.cpp`
- Remove the `AddonMessageRouter` include and call in `src/server/game/Handlers/ChatHandler.cpp`

## 3) Rebuild
Re-run CMake (if needed) and rebuild `worldserver`.

## 4) Optional test data cleanup
Remove seeded pets:
```
DELETE FROM character_pet
WHERE owner = <character_guid_low>
  AND name LIKE 'BMP_Test_%';
```
