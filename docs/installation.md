# Installation and updating

Requirements, install steps, SQL and updating.

- [Requirements](#requirements)
- [Installation](#installation)
- [SQL](#sql)
- [Updating](#updating)

## Requirements

- AzerothCore WotLK (3.3.5a) with the core patch in `patches/` (pet storage
  only). It is made against
  [azerothcore-wotlk](https://github.com/azerothcore/azerothcore-wotlk)
  `master` (November 2026). See [The core patch](core-patches.md).
- bash and git on the machine that applies the core patch.
- The BeastmasterPlus client addon (see [The client addon](addon.md)).

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
   modules/mod-beastmasterplus/patches/apply-core-patch.sh
   ```

   It applies `patches/core-beastmasterplus.patch`, prints `APPLIED` the first
   time and `OK: already applied` after that. What the patch changes, what to
   do if it fails, and how to remove it are in
   [The core patch](core-patches.md).

3. Re-run CMake and rebuild the core, for example:

   ```sh
   ./acore.sh compiler build
   ```

   or run `cmake` and `make install` in your build folder. CMake has to run
   again so it picks up the new module and its config file.

4. Set up the config file (see [Configuration](configuration.md)).

5. Install the client addon (see [The client addon](addon.md)) and
   restart `worldserver`.

## SQL

None is required. The module adds no tables and nothing is imported
automatically.

For development only, `sql/characters/optional_seed_bmp_test_pets.sql` seeds
test pets for one character. Run it manually against the **characters**
database while `worldserver` is stopped. It deletes that character's
existing pets first; read the header of the file before using it, and never
run it on production data.

## Updating

```sh
cd <azerothcore>/modules/mod-beastmasterplus
git pull
```

Then:

1. If the changelog says the core patch changed, revert the old one with
   `git apply -R` (using the old file) and run `patches/apply-core-patch.sh`
   from the AzerothCore root.
2. Re-run CMake, rebuild and restart `worldserver`.
3. Compare your `mod_beastmasterplus.conf` with the new
   `mod_beastmasterplus.conf.dist` and add any new options.
4. Copy the addon folder to the client again, replacing the old one.

See [CHANGELOG.md](../CHANGELOG.md) for what changed.
