# mod-beastmasterplus

<img src="icon.png" alt="" width="64" align="right">

BeastMasterPlus (HunterStablePlus) is an [AzerothCore](https://www.azerothcore.org/)
(WotLK 3.3.5a) module that gives hunters extended pet storage, driven by a
client addon. Dismissed pets are kept instead of lost, so hunters never have to
retame them, and the addon lists and summons them anywhere the game's own pet
swapping rules allow.

- **Author:** [dudemcbro](https://github.com/dudemcbro)
- **License:** [GNU GPL v3.0](LICENSE)
- **Works with:** AzerothCore WotLK (3.3.5a) with the required core patch in
  `patches/`, made against
  [azerothcore-wotlk](https://github.com/azerothcore/azerothcore-wotlk)
  `master` (November 2026).

## Features

- **Server-authoritative pet storage.** Dismissed pets are kept as unslotted
  pets (`character_pet.slot = 100`) instead of being lost.
- **No retaming.** Pets are never deleted and recreated.
- **No new tables.** Pets persist 1:1 in the `character_pet` table.
- **Addon UI.** A client addon talks to the server over `CHAT_MSG_ADDON`
  (prefix `BMP`). Type `/bmp` in game to open the pet manager.
- **No stable masters needed.** The extended storage does not use stable slots
  or stable master NPCs.
- **The game's own summon rules.** Summons are refused
  in combat, while mounted, on cooldown and in the other cases the game refuses
  a pet swap, and addon requests are rate limited. See
  [Summon rules](docs/how-it-works.md#summon-rules).

## Quick start

1. Clone into your AzerothCore `modules/` folder (keep the name `mod-beastmasterplus`):
   ```sh
   cd <azerothcore>/modules
   git clone https://github.com/dudemcbro/mod-beastmasterplus.git
   ```
2. **Required:** apply the core patch (once), from the AzerothCore repository
   root. It needs bash and git:
   ```sh
   cd <azerothcore>
   modules/mod-beastmasterplus/patches/apply-core-patch.sh
   ```
   It prints `APPLIED` the first time and `OK: already applied` after that.
   See [The core patch](docs/core-patches.md).
3. Re-run CMake, build and install the core (for example
   `./acore.sh compiler build`).
4. Set up `mod_beastmasterplus.conf` from `mod_beastmasterplus.conf.dist`
   (see [Configuration](docs/configuration.md)). No SQL import is needed.
5. **Required:** give your players the client addon: copy
   [`data/BeastmasterPlus`](data/BeastmasterPlus) to the WoW client as
   `Interface/AddOns/BeastmasterPlus` and enable it on the character selection
   screen. See [The client addon](docs/addon.md).
6. Restart `worldserver`.

The full steps, requirements and updating are in
[docs/installation.md](docs/installation.md).

## Documentation

| Page | What's in it |
| --- | --- |
| [Installation](docs/installation.md) | Requirements, install, SQL (none required, plus a dev-only seed script), updating |
| [The core patch](docs/core-patches.md) | What the required core patch changes, applying and removing it |
| [The client addon](docs/addon.md) | Installing the BeastmasterPlus addon and the `/bmp` commands |
| [Configuration](docs/configuration.md) | Every option in `mod_beastmasterplus.conf` |
| [How it works](docs/how-it-works.md) | Pet storage, addon messages, summon rules and rate limits |
| [Contributing](docs/contributing.md) | How to help, and the repository layout |

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/dudemcbro/mod-beastmasterplus). For larger
changes, please open an issue first, describe how you tested your change, and
add a line to [CHANGELOG.md](CHANGELOG.md). The repository layout is in
[docs/contributing.md](docs/contributing.md).

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).
