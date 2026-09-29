# Changelog

## Unreleased
- Fixed apply-core-addon-hook.sh dropping the `m_removed` guard in
  Player::RemovePet (and repair trees patched by earlier versions)
- Made apply-core-addon-hook.sh reach its final state in one run
- Removed the corrupt, unused patches/core-beastmasterplus.patch
- Moved the test pet seed to sql/characters and made @owner mandatory
- README: requirements, core files touched, SQL target database

## 0.1.0
- Packaged as an AzerothCore module under modules/mod-beastmasterplus
- Uses standard AzerothCore build flow via ./acore.sh compiler
- Added idempotent core hook patch for LANG_ADDON routing (ChatHandler.cpp)
- Vendored addon message router into module as BmpAddonMessageRouter
- Documented required client addon install (Interface/AddOns/BeastmasterPlus)
- Standardized SQL location for optional seed data
- Renamed main source file to src/BeastMasterPlus.cpp
