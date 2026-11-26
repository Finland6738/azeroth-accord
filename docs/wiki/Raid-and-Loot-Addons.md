# Raid and loot addons

*Italiano: [[Addon di raid e di loot|Raid-and-Loot-Addons-it]]*

> **Partly from `v0.10.0`**: the detection of other addons, the choice of the season roster's source and the section *Raid and loot addons in the guild* (step M10.2), in the [[Season|Season-Roster]] view. The **Raid** view, `/accord raid`, the *Loot* source and *Loot (FDCP)* on the member card (step M11.7) are in the code but switched off until milestone M11 is complete. Nothing has been checked in the real game. What follows describes how it should work.

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

`/accord debug` has an **Integrations** section with what was found on your computer and an **FDCP** section with the state of the notifications (no names). Which of these addons the *other* members have comes from the [[Guild addons|Guild-Addons]] list (`v0.9.0`): the [[Season|Season-Roster]] view shows it (and the Raid view, below).

## The Raid view

Open it with its tab or `/accord raid`.

- **At the top, the guild's sources**: *Season roster* (Accord or FDCP) and *Loot* (None or FDCP). Officers and the Guild Master change them with a click, and the choice reaches every member with Accord. Members see the same choice, locked. **Open FDCP** opens FDCP's own window while FDCP is loaded on your computer.
- **FDCP's state**: its version and where its data comes from on your computer, or why there is nothing: FDCP not installed or switched off, a version of its interface this Accord does not know, FDCP still reading the guild roster, or no season data yet.
- **Season roster**: the season and its pool, one line per main with class, role, MS1, MS2 and OS, and *trial* or *inactive*.
- **Lineup and bench**: the raid night open in FDCP, with who is in the raid and who is on the bench.
- **Loot**: your own credits and place in the loot queue, and a **read-only summary of FDCP's loot rules** (preset, priority, credits at the start, how items are awarded, the cost by item quality, the response multipliers, late joiners, the bench). The rules are changed in FDCP, never in Accord. The guild's loot page of the handbook will show the same summary beside its text (M11).

- **Raid and loot addons in the guild**, at the bottom: for each addon of the table above, what Accord found on your computer (loaded, switched off, installed or not installed, its version, level 0 or 1, and whether its folder name is confirmed yet) and, from the [[Guild addons|Guild-Addons]] list, how many members who share their addon list have it loaded, out of how many, with the versions. **Officers and the Guild Master** also see who has it, with the version and the characters; everybody else sees the counts and their own entry. If the addon list is switched off, nobody shares a list yet, or you do not share yours, a line says so.

With **Accord** as the source of the season roster, the view points to the [[Season|Season-Roster]] view, where each raider declares.

## On the member card

With FDCP chosen for the loot, the member card has a **Loot (FDCP)** section: the member's credits and place in the loot queue, as FDCP shows them. An alt shows its main's credits. An inactive main has credits but no place.

## Officers' and members' clients

FDCP does not give every client the same data, and Accord says so instead of showing empty lists:

| | Officer's client | Member's client |
|---|---|---|
| Season and pool | every main, with MS1, MS2 and OS | the playing mains, with MS1 only |
| Lineup and bench | the open night | not on members' clients |
| Credits and place | yes | yes, from the table an officer sent |
| Loot rules | the guild's rules | the defaults of FDCP's Patto preset (the guild's rules are on officers' clients) |

**Attendance is never shown**: FDCP keeps it for its officers and does not share it with other addons, and Accord counts no presence at raids. Accord saves and sends nothing of what it reads from FDCP.
