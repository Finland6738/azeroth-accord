# M11 — Loot and guild handbook

**Goal:** the guild handbook: text pages that officers write and every member reads in game. Pages cover:
- extended guild info;
- extended rules;
- extended FAQ;
- raid management;
- roster management;
- loot management.

Loot is documented, not computed. The loot page says which system the guild uses and names its addon. Accord detects that addon in every member's client and, for FDCP, reads what FDCP publishes. Release: `v0.11.0`.

**Switched off until complete (2026-11-25).** M11.7 landed ahead of the milestone. It ships hidden behind the switch `raid` of `AzerothAccord/Core/Features.lua` (no **Raid** view or `/accord raid`, no *Loot* source, no *Loot (FDCP)* row). Since M10.3 the M10 features have their own switch, `season` (detection, the season roster's source and FDCP's season pool in the **Season** view), turned on by M10.10 for `v0.10.0`; `raid` on turns `season` on too. `raid` is turned on when M11 is complete.

**Exit criterion:** in game:
- an officer edits the rules page, and a member who logs in later reads the new version marked as updated;
- the loot page names the guild's loot addon, and officers see who in the guild has it loaded.

**Owner's decision (2026-11-19):** no loot engine in Accord. The loot page says which system the guild uses and, if there is one, the addon for it. Accord points to that addon, and reads its data only if it turns out to be possible. This answers SPEC-10 Q6.

**Integration rules (owner, 2026-11-24):** the rules of [M10](M10-calendar-raids.md#integration-rules-owner-2026-11-24) apply here too:
- one source for every datum;
- read-only integrations, through a documented public API only;
- levels 0 (detection) and 1 (reading), never level 2;
- only loot and raid-roster addons, never other guild-management addons;
- no loot engine and no attendance in Accord.

## Addons on WoW Forever

The loot and raid-roster addons that run on Forever. First survey on 2026-11-24 (CurseForge, GitHub, Wago, wowcalc.net, timesaver.gg, guildmanager.app); **checked again in M11.1 on 2026-11-26** from the public CurseForge and GitHub pages. Guild-management addons are left out on purpose (M10 integration rule 6). None of it has been checked in the game; the folder names are confirmed in game in M11.8 (as M10.2 planned), and only FDCP's is confirmed now.

| Addon | Kind | Loot system | On Forever (2026-11-26) | Folder name | Public API or exchange | Plan in Accord |
|---|---|---|---|---|---|---|
| **Finland Dragon Credit Points (FDCP)** | loot and raid (same owner) | credits: fewest credits wins, then the roll; council | yes | `FinlandDragonCreditPoints` (confirmed) | **yes**: `FinlandDragonCreditPointsAPI`, `API_VERSION` 1 (FDCP M8-1, 2026-11-24) | level 1: season roster, lineup and bench, a member's credits and queue place, the rules summary (M11.7 done; SPEC-15 §9) |
| **Gargul** | loot | rolls and plus-ones, soft reserve (softres.it), TMB or DFT wishlists, boosted rolls, GDKP | yes: a Forever file of 2026-11-24 (v8.1.1-forever) | `Gargul` (the repository has `Gargul.toc`; not confirmed in game) | imports from softres.it and TMB; no documented API for other addons | level 0 |
| **RaidCore** | loot | soft reserve, loot council (adapted from RCLootCouncil Classic), rolls | yes: Interface 16001, file of 2026-10-26 (1.0.8) | `RaidCore` (not confirmed) | JSON export and import for its own website; no API; it can switch Gargul off on a character | level 0 |
| **TLC - Loot Council** (new in M11.1) | loot | loot council, rolls MS/OS/transmog, soft reserve (softres.it CSV), priority lists, plus-ones, BiS lists | yes: "built and tested" for Forever, 1.60.1, file of 2026-11-19 (0.9.21) | not stated (`/tlc`); M11.6 adds it to `Integrations.KNOWN` unconfirmed | `/tlc export` and `/tlc sync` between officers; no API. It also keeps attendance, which Accord never reads | level 0 |
| **WLC** | loot | loot council with votes | not found again on 2026-11-26 | `WLC` (not confirmed) | CSV and TMB-style export | level 0, kept in `KNOWN` until M11.8 |
| **Forever Loot Manager** | loot | DKP, open-bid auctions | not found again on 2026-11-26 | `ForeverLootManager` (not confirmed) | CSV export, also of attendance | level 0, kept in `KNOWN` until M11.8 |
| **NostalgiaForeverLC** | loot (alpha) | hard and soft reserve, raid leader hands out | not found again on 2026-11-26 | `NostalgiaForeverLC` (not confirmed) | text import and export, softres.it CSV | level 0, kept in `KNOWN` until M11.8 |
| **RollForMe** | loot | +1 / MS / OS rolls, soft reserve, DKP, council | not found again on 2026-11-26 | `RollForMe` (not confirmed) | not known | level 0, kept in `KNOWN` until M11.8 |

Notes:
- **No public API** for other addons was found on any of these pages except FDCP's: every other addon stays at level 0 (ADR 0022 point 3).
- **Not on Forever** (no Forever file on their pages on 2026-11-26): RCLootCouncil (RaidCore says standalone RCLootCouncil clients do not get its council requests), the Gargul Loot Council Extension (Classic TBC only), MeltdownLC (MoP Classic only), LootReserve (no Forever flavor among the versions shown).
- Loot *windows* and loot *browsers* for Forever (Loot Forever, XLoot, AutoLooter, Forever Loot Finder, WoWForeverLoot…) are not loot-distribution addons and are left out.
- **GDKP:** Blizzard stated that GDKP is not allowed in WoW Forever, at least in North America and Europe (reported by guildmanager.app, not checked at the source). Accord's templates and texts never propose it (SPEC-15 §8.1).

### M11.1 — Specification
- Branch: `step/m11-1-spec`
- Scope: write a new SPEC-15 ("Manuale di gilda e loot"), in Italian. It covers:
  - the `handbook` data set: pages, revisions, size limits, who can write;
  - the reader and the editor;
  - the default pages;
  - the loot page: the guild's loot system, the chosen addon, detection and the FDCP provider.

  It updates the survey above (which addons run on Forever then, their folder names, whether any has gained a public API). It records which data FDCP's API would give to a member's client and which only to an officer's.
- Done when:
  - [x] SPEC-15 is linked from the spec index; SPEC-10 Q6 stays answered and Q10 is updated; `tools/check_docs.py` passes.
  - *Done (2026-11-26):* [SPEC-15](../specs/SPEC-15-guild-handbook-loot.md) covers the data set `handbook` (pages as records with the page revision, writers by rank chosen in `guildcfg`, limits, trust rules HBK-01…HBK-06, conflicts flagged to the losing author, past revisions kept locally), the sync (its own summary entry, no whisper pushes, pages sent once on `GUILD` for everybody waiting, in AceComm parts) and its traffic against SPEC-09 §7; the reader and the editor; the default pages, seeded once by a writer's click; the loot page (`guildcfg` record `loot`, chosen together with the loot source, who has the addon from the census, the download address, the FDCP suggestion as a locale text for writers) and what moves from the Raid view when M11.6 exists; what FDCP's API gives a member's client and an officer's (SPEC-15 §9); what `raid` covers in M11. New [ADR 0025](../adr/0025-guild-handbook-pages-shared-on-guild-revisions-local.md); SPEC-10 Q27–Q33 (applied as proposed until the owner answers) and R18; the survey above checked again.

### M11.2 — Handbook data
- Branch: `step/m11-2-handbook-data`
- Spec: SPEC-15
- Scope:
  - each page has an id, title, body, order and revision, and keeps its last few revisions;
  - only ranks the guild chooses can write (officers by default);
  - pages are synced on `GUILD`, and long bodies are sent in parts.
- Done when:
  - [x] A page from a non-writer is refused; two edits of the same revision keep the newer and flag the conflict to its author.
  - *Done (2026-11-26):* `Data/Handbook.lua` (the data set `handbook`, writers by rank from the `guildcfg` record `handbook`, the limits of Q29 as constants, the past revisions kept locally, conflicts with a notice and an Action Center row for the losing author); `Net/Store.lua` gains the set's `writer`, `rate`, `replaced` and `keepDeleted` rules; `Net/Sync.lua` the handbook's own summary (`hb`, `hbb`), no whisper push, requests answered once on GUILD, long pages alone in BULK. The simulator measure of SPEC-15 §3.7 needed the 10-minute wait before the first request (`Sync.HB_REQ_AFTER`). All behind `raid`; `Tests/test_handbook.lua`.

### M11.3 — Reader
- Branch: `step/m11-3-reader`
- Spec: SPEC-15; SPEC-04
- Scope: a Handbook view with:
  - the page list;
  - the reader, with headings, lists and links between pages;
  - search;
  - a mark on pages updated since the player last read them.
- Done when:
  - [x] Every member can read every page offline from the last sync; the "updated" mark clears on reading.
  - *Done (2026-11-26):* `Data/HandbookText.lua` (blocks, links, cleaning, HTML, search), the read marks in `Data/Handbook.lua` and the Handbook view `UI/Handbook.lua` with `/accord handbook`, one SimpleHTML per block, all behind `raid`; `Tests/test_handbook_view.lua`.
- Real client: how SimpleHTML draws the fonts, the links and the height of a block; scrolling to a heading.

### M11.4 — Editor
- Branch: `step/m11-4-editor`
- Spec: SPEC-15
- Scope: multi-line editing with a preview, the length shown against the limit, and a list of past revisions with "restore".
- Done when:
  - [ ] An edit that would exceed the limit cannot be saved; restore creates a new revision.

### M11.5 — Default pages
- Branch: `step/m11-5-default-pages`
- Spec: SPEC-15
- Scope: empty templates with headings for guild info, rules, FAQ, raid management, roster management (linked to the season roster of M10 and to its source) and loot management. Officers fill them in game; the templates hold no guild-specific text.
- Done when:
  - [ ] A new guild gets the templates once; deleting one does not bring it back.

### M11.6 — Loot page and loot addons
- Branch: `step/m11-6-loot`
- Spec: SPEC-15; ADR 0022
- Scope:
  - the loot page's text, written by officers, with a link to the season roster ("loot follows the declared spec");
  - two fields chosen by officers:
    - the guild's **loot system**: rolls MS/OS, soft reserve, loot council, DKP, credits, other;
    - the **loot addon**: one of the known addons of M10.2, "other" or none. "Other" is any loot addon published on CurseForge (owner, SPEC-10 Q30, 2026-11-26): its name, its folder (so the addon census shows who has it loaded, level 0) and its CurseForge address (Q32: `https://` on CurseForge only). Reading its data (level 1) stays for addons with a documented public API, today only FDCP;
  - who in the guild has that addon loaded (from the addon census of M9.9, through M10.2), with the version, and a list of who lacks it for officers;
  - the download address in a read-only box to copy;
  - with no addon chosen, the page shows nothing about addons and suggests FDCP, the family's loot addon.
- Done when:
  - [ ] Officers see who has the chosen addon; without an addon chosen, nothing is checked; the suggestion is a locale text, not guild data.

### M11.7 — FDCP reading
- Branch: `step/m11-7-fdcp`
- Spec: SPEC-15; ADR 0022; SPEC-10 Q10
- Depends on: FDCP's public read-only API (a step in the FDCP repository).
- Scope:
  - the FDCP provider at level 1: a member's credits and place in the loot queue on the member card, when this client has them;
  - the season roster and the lineup for M10;
  - FDCP's rules as a read-only summary beside the loot page, never copied into it;
  - an unknown API version falls back to level 0 without errors.
  - If FDCP has no API when this step comes, the step only records that and stays open.
  - *Done (2026-11-24), ahead of M11.1–M11.6 because FDCP published its API (FDCP M8-1):* `Data/FDCP.lua` reads every getter protected and keeps only the known fields; the new **Raid** view (`UI/Raid.lua`, `/accord raid`) holds the officers' choice of the sources (M10.2's guild setting), the pool, the lineup and bench, the player's credits and the rules summary; the member card gains *Loot (FDCP)*. Callbacks are registered only while FDCP is a source. The rules summary moves beside the loot page when M11.6 exists; SPEC-15 does not exist yet, so ADR 0022 and the wiki page *Raid and Loot Addons* describe the step. Follow-ups for FDCP's API are in SPEC-10 Q10.
- Done when:
  - [x] With FDCP loaded and its API known, the member card shows the credits that FDCP shows; with FDCP missing, disabled or of an unknown API version, nothing breaks and level 0 remains (`Tests/test_integrations.lua`).
- Real client: FDCP and Accord loaded together, a `/reload`, and the order in which the two addons load.

### M11.8 — In-game check and release
- Branch: `step/m11-8-check`
- Scope: `docs/checklists/M11.md` and the README status. The owner releases `v0.11.0`.
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.11.0`.
