# The client addon

Installing the required BeastmasterPlus addon, and using it in game.

The server module loads without the addon, but all interaction goes through
the addon UI.

## Installation (required)

1. Copy the folder [`data/BeastmasterPlus`](../data/BeastmasterPlus) to the WoW
   client as `Interface/AddOns/BeastmasterPlus`.
2. Check that the folder contains `BeastmasterPlus.toc`,
   `BeastmasterPlus.lua`, `BeastmasterPlusUI.lua` and
   `BeastmasterPlusFamilyMap.lua`.
3. Enable the addon on the character selection screen.

When you update the module, copy the addon folder to the client again,
replacing the old one.

## In game

Type `/bmp` to open the pet manager and `/bmp help` to list the commands.
Refused requests are shown in chat and in the red error text at the top of the
screen. The reasons a summon can be refused are listed in
[Summon rules](how-it-works.md#summon-rules).

Dismiss is available through the addon button or `/bmp dismiss <petNumber>`
and is not permanent.
