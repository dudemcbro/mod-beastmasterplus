# How it works

What the module does with hunter pets, and the rules for summoning them.

## What this module does

- Server-authoritative extended hunter pet storage: dismissed pets are kept
  as unslotted pets (`character_pet.slot = 100`) instead of being lost.
- No retaming, and pets are never deleted and recreated.
- Pets persist 1:1 in the `character_pet` table; the module adds no tables.
- The UI is a client addon that talks to the server over `CHAT_MSG_ADDON`
  (prefix `BMP`). See [The client addon](addon.md).
- The extended storage does not use stable slots or stable master NPCs.
  Pets in the regular stable slots (1-4) still follow the core's stable
  rules, see [Summon rules](#summon-rules).
- Addon requests arrive as whispers to the hunter's own character. The
  module answers them through the core's existing chat hook, so the core
  needs no chat changes.

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

## Rate limits

All addon requests (list, summon, dismiss and so on) are also rate limited
per player: at most `BeastMasterPlus.RequestLimit.Count` requests per
`BeastMasterPlus.RequestLimit.Window` seconds (default 10 per 10 seconds).
Requests over the limit are dropped and the addon shows "Too many requests"
once.

These options are described in [Configuration](configuration.md).
