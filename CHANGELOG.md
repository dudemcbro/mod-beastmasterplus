# Changelog

## Unreleased

## 0.1.0
- Packaged as an AzerothCore module under modules/mod-beastmasterplus
- Uses standard AzerothCore build flow via ./acore.sh compiler
- Added idempotent core hook patch for LANG_ADDON routing (ChatHandler.cpp)
- Vendored addon message router into module as BmpAddonMessageRouter
- Documented required client addon install (Interface/AddOns/BeastmasterPlus)
- Standardized SQL location for optional seed data
- Renamed main source file to src/BeastMasterPlus.cpp
