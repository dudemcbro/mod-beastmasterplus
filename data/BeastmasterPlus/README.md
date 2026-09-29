# BeastmasterPlus

This is a **client addon**, not a server-side module. It is not compiled by the core and has no server SQL.

Install by copying the folder to your WoW client AddOns directory:
- `Interface/AddOns/BeastmasterPlus`

Notes:
- Use the in-game UI to list and summon pets.
- Dismiss is available via the UI button or `/bmp dismiss <petNumber>` (not permanent).
- The server can refuse a summon (for example in combat, while mounted, on cooldown, or for a
  pet in a stable slot when no stable master is near). The reason is shown in chat and in the
  red error text at the top of the screen. See the
  [module README](../../README.md#summon-rules) for the full list.
