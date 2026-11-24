# Raid and loot addons

*Italiano: [[Addon di raid e di loot|Raid-and-Loot-Addons-it]]*

> Detection is in the code from step M10.2; reading Finland Dragon Credit Points comes with step M11.7. Nothing has been checked in the real game yet: the first tests are with the owner's guild.

Accord has **no loot engine and no attendance**. Your guild's raid and loot addons keep that data, and Accord works **with** them, never against them:

- **One source for every datum.** The season roster (MS1, MS2, OS) with the lineup and the bench belongs to one addon for the whole guild, and so do the loot data (a member's credits and place in the loot queue, the loot rules). The **officers** choose that source once for the guild, and every member's Accord follows the same choice. Until they choose, the season roster is Accord's own and there is no loot source.
- **Read-only.** Accord never writes another addon's data, never reads its saved files, and never loads, enables or disables it.

## The addons Accord knows

| Addon | Kind | What Accord does |
|---|---|---|
| **Finland Dragon Credit Points** (FDCP) | loot and raid roster | detects it; reads it through its public API (level 1) |
| Gargul, RaidCore, WLC, Forever Loot Manager, NostalgiaForeverLC, RollForMe | loot | detects it (level 0) |

The folder names of the addons other than FDCP come from their public pages and are confirmed in game before they are trusted. Guild-management addons that are not about loot or the raid roster are left out on purpose.

## Levels

- **Level 0, detection.** Accord sees that the addon is loaded on your computer, and its version.
- **Level 1, reading.** Accord reads what the addon publishes for other addons. Only FDCP publishes such an interface (`FinlandDragonCreditPointsAPI`), and Accord reads it only when its version is one Accord knows (version 1). With another version Accord goes back to level 0 and nothing breaks: update Accord.
- There is no level 2: Accord never sends anything to another addon.

`/accord debug` has an **Integrations** section with what was found on your computer (no names). Which addons the *other* members have comes later, with the guild's addon list (M9).
