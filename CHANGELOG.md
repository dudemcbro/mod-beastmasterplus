# Changelog

## Unreleased
- Works on stock AzerothCore: the core patch is now made against
  azerothcore-wotlk `master`, and the apply script's scripted edits also
  match current AzerothCore, which renamed `m_caster` to `unitCaster` in
  `Spell::_cast` and `Spell::EffectTameCreature`. Before, the script skipped
  those two edits there without saying so
- apply-core-addon-hook.sh checks every core change at the end, lists any
  that are missing and exits with an error
- The core patch no longer declares `Pet::SavePetStateWithoutSlot()`, which
  the module never used
- The module only defines `AddonMessageRouter` when the core does not ship
  its own `AddonMessageRouter.h`, so cores that include it no longer get a
  second copy of the same functions
- SUMMON is now refused while dead, in combat, mounted, on a flight path, in
  a vehicle, while casting, while charmed or controlling a unit, in arenas
  and (unless `BeastMasterPlus.Summon.AllowInBattleground = 1`) in
  battlegrounds. All checks run before the active pet is dismissed
- SUMMON has a server-side cooldown, `BeastMasterPlus.Summon.Cooldown`
  (default 10 seconds)
- Pets in a real stable slot (1-4) can only be summoned near a stable master
  (GMs and open-stable auras are allowed), matching the core's stable
  checks. BMP's own storage of unslotted pets is unchanged
- Summoning the pet that is already active is refused instead of
  dismissing and reloading it
- All addon requests are rate limited per player,
  `BeastMasterPlus.RequestLimit.Count` requests per
  `BeastMasterPlus.RequestLimit.Window` seconds (default 10 per 10). The
  core's addon flood limit is loose and a chat mute does not stop addon
  messages from reaching the module
- A failed summon no longer drops the in-memory record of a pet that still
  exists in the database; only a record added by that request is removed
- The DISMISS diagnostic query only runs when `module.bmp` debug logging
  is enabled
- The addon shows readable text for every server error, also in the red
  error frame
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
