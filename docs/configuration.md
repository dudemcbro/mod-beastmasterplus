# Configuration

Every option in `mod_beastmasterplus.conf`.

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
| `BeastMasterPlus.AllowMultipleUnslottedPets` | `1` | Keep several unslotted hunter pets at the same time. Required for the extended storage. Read by the [core patch](core-patches.md); if the config is not loaded, the patched core defaults to `1` so dismissed pets are not deleted. |
| `BeastMasterPlus.Summon.Cooldown` | `10` | Seconds between two summons through the addon. `0` disables the cooldown. |
| `BeastMasterPlus.Summon.AllowInBattleground` | `0` | Allow summons through the addon inside battlegrounds. Arenas are always refused. |
| `BeastMasterPlus.RequestLimit.Count` | `10` | Addon requests allowed per player and window. `0` disables the limit. |
| `BeastMasterPlus.RequestLimit.Window` | `10` | Length of the rate limit window in seconds. |

Options are re-read on `.reload config`.

## Notes on `AllowMultipleUnslottedPets`

- With `0`, dismissed pets can be removed when taming a new one.
- With `1`, the hunter pet action "Abandon" is treated as a dismiss
  (`PET_SAVE_NOT_IN_SLOT`, slot 100) so pets are not lost while taming.
- Dismiss is available through the addon button or `/bmp dismiss <petNumber>`
  and is not permanent.
