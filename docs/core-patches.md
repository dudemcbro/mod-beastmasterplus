# The core patch

The module requires this core patch for pet storage.

## What it changes

[`patches/core-beastmasterplus.patch`](../patches/core-beastmasterplus.patch)
lets a hunter keep several pets out of the stable: taming no longer deletes
them, unsummoning keeps them, and abandoning from the pet bar dismisses the pet
instead. Every change reads `BeastMasterPlus.AllowMultipleUnslottedPets` (see
[Configuration](configuration.md)) and is marked `mod-beastmasterplus` in the
source.

It is made against
[azerothcore-wotlk](https://github.com/azerothcore/azerothcore-wotlk)
`master` (November 2026).

## Applying it

You need bash and git on the machine that applies the patch. Run
[`patches/apply-core-patch.sh`](../patches/apply-core-patch.sh) once, from the
AzerothCore repository root:

```sh
cd <azerothcore>
modules/mod-beastmasterplus/patches/apply-core-patch.sh
```

It prints `APPLIED` the first time and `OK: already applied` after that. If
your core differs, it stops with an error and changes nothing; apply the patch
by hand using the file as the reference.

Then re-run CMake and rebuild the core (see [Installation](installation.md)).

## Removing it

```sh
git apply -R modules/mod-beastmasterplus/patches/core-beastmasterplus.patch
```

## When the patch changes

If the changelog says the core patch changed, revert the old one with
`git apply -R` (using the old file) and run `patches/apply-core-patch.sh` from
the AzerothCore root. See [Updating](installation.md#updating).

## Older patched cores

Cores patched by older versions of this module call
`AddonMessageRouter::Handle` from `ChatHandler.cpp`. The module still provides
it, so those cores keep building.
