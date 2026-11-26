# Raid and loot addons

*Italiano: [[Addon di raid e di loot|Raid-and-Loot-Addons-it]]*

> **From `v0.10.0`**: the detection of other addons, the choice of the season roster's source and the section *Raid and loot addons in the guild*, in the [[Season|Season-Roster]] view. **From `v0.11.0`**: the **Raid** view, `/accord raid`, *Loot (FDCP)* on the member card and the **loot page** with the choice of the guild's loot addon. The in-game checks are pending: nothing has been checked in the real game. What follows describes how it should work.

Accord has **no loot engine and no attendance**. Your guild's raid and loot addons keep that data, and Accord works **with** them, never against them:

- **One source for every datum.** The season roster (MS1, MS2, OS) with the lineup and the bench belongs to one addon for the whole guild, and so do the loot data (a member's credits and place in the loot queue, the loot rules). The **officers** choose once for the guild, and every member's Accord follows the same choice. Until they choose, the season roster is Accord's own and there is no loot addon.
- **Read-only.** Accord never writes another addon's data, never reads its saved files, and never loads, enables or disables it.

## The addons Accord knows

| Addon | Kind | What Accord does |
|---|---|---|
| **Finland Dragon Credit Points** (FDCP) | loot and raid roster | detects it; reads it through its public API (level 1) |
| Gargul, RaidCore, TLC - Loot Council, WLC, Forever Loot Manager, NostalgiaForeverLC, RollForMe | loot | detects it (level 0) |
| Any other loot addon on CurseForge | loot | detects it by the folder an officer writes (level 0) |

The folder names of the addons other than FDCP come from their public pages and are confirmed in game before they are trusted. Guild-management addons that are not about loot or the raid roster are left out on purpose.

## Levels

- **Level 0, detection.** Accord sees that the addon is loaded on your computer, and its version.
- **Level 1, reading.** Accord reads what the addon publishes for other addons. Only FDCP publishes such an interface (`FinlandDragonCreditPointsAPI`), and Accord reads it only when its version is one Accord knows (version 1). With another version Accord goes back to level 0 and nothing breaks: update Accord.
- There is no level 2: Accord never sends anything to another addon.

`/accord debug` has an **Integrations** section with what was found on your computer and an **FDCP** section with the state of the notifications (no names). Which of these addons the *other* members have comes from the [[Guild addons|Guild-Addons]] list (`v0.9.0`): the [[Season|Season-Roster]] view shows it (and the Raid view, below).

## The loot page

The [[guild handbook|Guild-Handbook]] page **Loot management** shows, above the text the writers write, the guild's loot choice. Accord describes loot and never computes it.

- **Loot system**: rolls (MS/OS), soft reserve, loot council, DKP, credits, or another with your own name.
- **Loot addon**: one of the loot addons above, or **Other (from CurseForge)**: any loot addon published on CurseForge, with its name, its **folder** name (the folder in `Interface/AddOns`) and its CurseForge address. Only an `https://` address on curseforge.com is accepted.
- **Officers and the Guild Master** change both with **Change** and **Save**. Choosing FDCP also makes Accord read FDCP's loot data; choosing another addon or none stops that. It is one choice.
- **On this client**: loaded (with its version), not loaded, not installed, or *folder not confirmed* (Accord has not yet seen that folder name in game).
- **Download**: the address, in a box to copy with Ctrl+C, when you do not have the addon loaded (writers always see it). Install addons only from sources you trust.
- **Who has it**, from the [[Guild addons|Guild-Addons]] list: everybody sees how many of the members who share their list have it loaded, with the versions, and their own line. **Officers and the Guild Master** also see who has it, who lacks it, and how many share no list or do not use Accord (never counted as missing). If the list is switched off or nobody shares one, a line says so.
- **With no addon chosen**, the page shows nothing about addons and nothing is checked. Writers see a suggestion for FDCP with its address, and officers **Choose FDCP** and **Choose a loot addon**.
- **With FDCP**: your credits and place in the loot queue, and a **read-only summary of FDCP's loot rules**, read from FDCP every time and never copied into the page. **Open FDCP** opens its window.

The search of the handbook also finds the names of the loot system and addon. While the loot page cannot be read (nobody created it, it was deleted, or it is still a template and you are not a writer), **Loot page** in the Raid view shows the same part there.

## The Raid view

Open it with its tab or `/accord raid`.

- **At the top**: the *Season roster* source (Accord or FDCP), which officers and the Guild Master change with a click and members see locked, and the guild's loot addon with the **Loot page** button. **Open FDCP** opens FDCP's own window while FDCP is loaded on your computer.
- **FDCP's state**: its version and where its data comes from on your computer, or why there is nothing: FDCP not installed or switched off, a version of its interface this Accord does not know, FDCP still reading the guild roster, or no season data yet.
- **Season roster**: the season and its pool, one line per main with class, role, MS1, MS2 and OS, and *trial* or *inactive*.
- **Lineup and bench**: the raid night open in FDCP, with who is in the raid and who is on the bench.
- **Loot**: with FDCP, your own credits and place in the loot queue. The summary of FDCP's loot rules (preset, priority, credits at the start, how items are awarded, the cost by item quality, the response multipliers, late joiners, the bench) is on the loot page. The rules are changed in FDCP, never in Accord.

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
