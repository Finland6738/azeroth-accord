# 0022. Integrations with raid and loot addons: one source per datum, read-only, the game calendar shared

- Status: Accepted
- Date: 2026-11-24 ([M10 integration rules](../roadmap/M10-calendar-raids.md#integration-rules-owner-2026-11-24), [SPEC-10 Q10](../specs/SPEC-10-risks-open-questions.md))

## Context

M10 (calendar, raids and the season roster) and M11 (loot and the guild handbook) were first planned as features of Accord alone. A review against Finland Dragon Credit Points (FDCP, the loot and raid addon of the same author) and the other loot addons that run on WoW Forever showed that they overlap: FDCP already keeps the season pool (MS1, MS2, OS), the bench rotation and the attendance per boss, and it reads the sign-ups of the game's calendar. Two addons keeping the same datum would show two truths to the guild. On 2026-11-24 the owner set the integration rules of M10 and M11 and answered SPEC-10 Q10: FDCP publishes a read-only, versioned API in its own repository. FDCP shipped it the same day (its step M8-1, its ADR 0009): the global table `FinlandDragonCreditPointsAPI`, `API_VERSION` 1.

## Decision

1. **One source per datum, chosen by the officers.** The season roster with the lineup and the bench (`raid`) and the loot data (`loot`: a member's credits and queue place, the rules summary) each belong to one addon per guild. The choice is a guild setting written only by officers and synced to every member (the record `sources` of the data set `guildcfg`, [SPEC-03 §8](../specs/SPEC-03-data-model.md#8-impostazioni-della-gilda-guildcfg)), never a guess of each client, so every member sees the same truth. Defaults: `raid` = Accord, `loot` = none.
2. **Read-only, through a documented and versioned public API only.** Accord never writes another addon's data, never reads another addon's SavedVariables or private namespace (`C_AddOns.GetAddOnLocalTable` is not used), and never loads, enables or disables another addon.
3. **Three levels.** Level 0, detection: the addon is loaded, its version, and a way to open it. Level 1, reading: only through the addon's public API, and only when its version is the one Accord knows; any other version falls back to level 0 without an error. Level 2, a two-way exchange: never. Today only FDCP has level 1 (`API_VERSION == 1`); Gargul, RaidCore, WLC, Forever Loot Manager, NostalgiaForeverLC and RollForMe stay at level 0, and their folder names are confirmed in game before they are trusted.
4. **Only loot and raid-roster addons.** Other guild-management addons are not detected and not read.
5. **No loot engine and no attendance in Accord.** FDCP does not expose attendance either; nothing Accord shows from FDCP counts presence at raids.
6. **The game calendar is the shared ground** for events and sign-ups (M10.5): every addon then sees the same answers.
7. **Load order is not a dependency.** The TOC names FDCP in `## OptionalDeps` (a hint that loads it first when it is installed), and Accord looks for the table again at `PLAYER_LOGIN` and on `ADDON_LOADED` of a known folder. Each getter is guarded; `nil` means "not on this client", never "empty".
8. **Callbacks only while needed.** Accord registers FDCP's callbacks only while the guild chose FDCP as a source and level 1 holds, and unregisters them when the source changes away from FDCP (M11.7).
9. **Where it shows** (M11.7): the officers choose the sources in the **Raid** view, which also shows FDCP's season pool, the night's lineup and bench and the rules summary; the member card shows a member's credits and queue place. Until the handbook's loot page exists (M11.6), the rules summary lives in the Raid view only. Nothing read from FDCP is saved or sent.

## Alternatives considered

- **Each client guesses the source** (FDCP if it is loaded, else Accord). Members with and without FDCP would see different rosters.
- **Read FDCP's SavedVariables.** No contract: their layout changes without notice, and they hold attendance that FDCP keeps for officers only.
- **A two-way exchange** (Accord writing declarations into FDCP). Two writers of one datum, and FDCP would depend on Accord.
- **A hard dependency** (`## Dependencies`). Accord would not load without FDCP; the two addons stay independent ([ADR 0021](0021-interface-follows-the-ecosystem-style-of-fdcp.md)).

## Consequences

- Positive: one truth per datum for the whole guild; FDCP can change its internals freely while `API_VERSION` holds; a new reader version is a small, tested change.
- Negative: a member's client sees less than an officer's (FDCP's snapshot has no MS2, OS, availability, night or guild rules), and Accord must say so instead of showing empty lists; the other loot addons offer no API, so Accord only points to them; nothing is verified in the real client until the owner's checks (the two addons loaded together, a `/reload`, the load order).
