# mod-beastmasterplus

BeastMasterPlus (HunterStablePlus) is an [AzerothCore](https://www.azerothcore.org/)
(WotLK 3.3.5a) module that gives hunters extended pet storage, driven by a
client addon.

## What this module does

- Server-authoritative extended hunter pet storage: dismissed pets are kept
  as unslotted pets (`character_pet.slot = 100`) instead of being lost.
- No retaming, and pets are never deleted and recreated.
- Pets persist 1:1 in the `character_pet` table; the module adds no tables.
- The UI is a client addon that talks to the server over `CHAT_MSG_ADDON`
  (prefix `BMP`).
- The extended storage does not use stable slots or stable master NPCs.
  Pets in the regular stable slots (1-4) still follow the core's stable
  rules, see [Summon rules](#summon-rules).
- The module provides the `AddonMessageRouter` implementation when the core
  does not ship one (the core patch only forward-declares it).

## Summon rules

Summoning a pet from the addon swaps it with the active pet, so the server
applies the same limits as the game's own pet swapping. A summon is refused
with a message in the addon when:

- the hunter is dead, in combat, mounted, on a flight path, in a vehicle,
  casting, charmed or controlling another unit;
- the hunter is in an arena, or in a battleground unless
  `BeastMasterPlus.Summon.AllowInBattleground = 1`;
- the last summon was less than `BeastMasterPlus.Summon.Cooldown` seconds ago
  (default 10);
- the pet is in one of the regular stable slots (1-4) and no stable master is
  in interaction range. Pets in BMP's own storage (unslotted pets) can be
  summoned anywhere. GMs and hunters with an open-stable aura skip this check;
- the pet is already the active pet.

All addon requests (list, summon, dismiss and so on) are also rate limited
per player: at most `BeastMasterPlus.RequestLimit.Count` requests per
`BeastMasterPlus.RequestLimit.Window` seconds (default 10 per 10 seconds).
Requests over the limit are dropped and the addon shows "Too many requests"
once.

## Requirements

- AzerothCore WotLK (3.3.5a). No custom core fork is needed: the core patch
  and apply script bring their own changes. Tested on:
  - [azerothcore-wotlk](https://github.com/azerothcore/azerothcore-wotlk)
    `master` (commit 51c32b5, September 2026), where the patch applies as is;
  - the [mod-playerbots fork](https://github.com/mod-playerbots/azerothcore-wotlk)
    (`Playerbot` branch) and
    [azerothcore-wotlk-playerbots-custom](https://github.com/dudemcbro/azerothcore-wotlk-playerbots-custom),
    where the apply script makes the same changes with scripted edits.
- bash, git, python3 and perl on the machine that applies the core patch.
- The BeastmasterPlus client addon (see
  [Client addon installation](#client-addon-installation-required)).

## Installation

1. Clone the module into the core's `modules` folder:

   ```sh
   cd <azerothcore>/modules
   git clone https://github.com/dudemcbro/mod-beastmasterplus.git
   ```

2. Apply the required core patch (once), from the AzerothCore repository
   root:

   ```sh
   cd <azerothcore>
   modules/mod-beastmasterplus/patches/apply-core-addon-hook.sh
   ```

   - It applies `patches/core-beastmasterplus.normalized.patch` (addon
     routing and pet save changes) and performs the remaining core edits with
     scripted fallbacks. If a partial hook already exists, it adds only the
     missing pieces. It is safe to run more than once.
   - At the end it checks that every core change is in place and prints
     `BeastMasterPlus core changes are in place.` If your core's source
     differs too much for an edit, it lists each `MISSING:` change and exits
     with an error instead of leaving the core half patched. Apply those
     changes by hand, using the patch file as the reference.
   - Use `--force` to re-apply after the core changed or the patch defaults
     were updated.
   - Besides the patch it edits these core files directly; review them with
     `git diff` afterwards: `Handlers/ChatHandler.cpp`,
     `Handlers/PetHandler.cpp`, `Entities/Pet/Pet.cpp`,
     `Entities/Player/Player.cpp`, `Entities/Unit/Unit.cpp`,
     `Spells/Spell.cpp`, `Spells/SpellEffects.cpp`,
     `scripts/Spells/spell_hunter.cpp`, and `CharacterDatabase.cpp` /
     `CharacterDatabase.h` under `src/server/database/Database/Implementation/`.
   - The `AddonMessageRouter` implementation is provided by this module in
     `src/BmpAddonMessageRouter.h` and `src/BmpAddonMessageRouter.cpp`. Some
     custom forks already ship their own `AddonMessageRouter.h` and `.cpp`
     in `src/server/game/Chat/`. The module detects that header at compile
     time and then leaves the definitions to the core, so exactly one copy
     is built either way.

3. Re-run CMake and rebuild the core, for example:

   ```sh
   ./acore.sh compiler build
   ```

   or run `cmake` and `make install` in your build folder. CMake has to run
   again so it picks up the new module and its config file.

4. Set up the config file (see [Configuration](#configuration)).

5. Install the client addon (see
   [Client addon installation](#client-addon-installation-required)) and
   restart `worldserver`.

## Configuration

The build installs `mod_beastmasterplus.conf.dist` into the `modules` folder
next to `worldserver.conf` (`env/dist/etc/modules/` for `acore.sh` builds).
`./acore.sh compiler build` copies it to `mod_beastmasterplus.conf` if that
file does not exist yet. Otherwise copy it yourself:

```sh
cd <config folder>/modules
cp mod_beastmasterplus.conf.dist mod_beastmasterplus.conf
```

| Option | Default | Description |
| --- | --- | --- |
| `BeastMasterPlus.AllowMultipleUnslottedPets` | `1` | Keep several unslotted hunter pets at the same time. Required for the extended storage. Read by the core patch; if the config is not loaded, the patched core defaults to `1` so dismissed pets are not deleted. |
| `BeastMasterPlus.Summon.Cooldown` | `10` | Seconds between two summons through the addon. `0` disables the cooldown. |
| `BeastMasterPlus.Summon.AllowInBattleground` | `0` | Allow summons through the addon inside battlegrounds. Arenas are always refused. |
| `BeastMasterPlus.RequestLimit.Count` | `10` | Addon requests allowed per player and window. `0` disables the limit. |
| `BeastMasterPlus.RequestLimit.Window` | `10` | Length of the rate limit window in seconds. |

Options are re-read on `.reload config`.

Notes on `AllowMultipleUnslottedPets`:

- With `0`, dismissed pets can be removed when taming a new one.
- With `1`, the hunter pet action "Abandon" is treated as a dismiss
  (`PET_SAVE_NOT_IN_SLOT`, slot 100) so pets are not lost while taming.
- Dismiss is available through the addon button or `/bmp dismiss <petNumber>`
  and is not permanent.

## SQL

None is required. The module adds no tables and nothing is imported
automatically.

For development only, `sql/characters/optional_seed_bmp_test_pets.sql` seeds
test pets for one character. Run it manually against the **characters**
database while `worldserver` is stopped. It deletes that character's
existing pets first; read the header of the file before using it, and never
run it on production data.

## Client addon installation (required)

The server module loads without the addon, but all interaction goes through
the addon UI.

1. Copy the folder [`data/BeastmasterPlus`](data/BeastmasterPlus) to the WoW
   client as `Interface/AddOns/BeastmasterPlus`.
2. Check that the folder contains `BeastmasterPlus.toc`,
   `BeastmasterPlus.lua`, `BeastmasterPlusUI.lua` and
   `BeastmasterPlusFamilyMap.lua`.
3. Enable the addon on the character selection screen.

In game, type `/bmp` to open the pet manager and `/bmp help` to list the
commands. Refused requests are shown in chat and in the red error text at
the top of the screen.

## Updating

```sh
cd <azerothcore>/modules/mod-beastmasterplus
git pull
```

Then:

1. Run `patches/apply-core-addon-hook.sh` again from the AzerothCore root
   (with `--force` if the changelog says the patch changed).
2. Re-run CMake, rebuild and restart `worldserver`.
3. Compare your `mod_beastmasterplus.conf` with the new
   `mod_beastmasterplus.conf.dist` and add any new options.
4. Copy the addon folder to the client again, replacing the old one.

See [CHANGELOG.md](CHANGELOG.md) for what changed.

## Layout

| Path | Contents |
| --- | --- |
| `src/` | Server-side module source code |
| `data/BeastmasterPlus/` | Required client addon (copy to `Interface/AddOns/BeastmasterPlus`) |
| `conf/` | Module configuration template |
| `sql/characters/` | Optional development seed data for the characters database |
| `patches/` | Core patch and the script that applies it and performs the remaining core edits |

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/dudemcbro/mod-beastmasterplus). For larger
changes, please open an issue first, describe how you tested your change, and
add a line to [CHANGELOG.md](CHANGELOG.md).

## License

GNU General Public License v3.0, see [LICENSE](LICENSE).
