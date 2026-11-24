# M11 — Loot and guild handbook

**Goal:** the guild handbook: text pages that officers write and every member reads in game. Pages cover:
- extended guild info;
- extended rules;
- extended FAQ;
- raid management;
- roster management;
- loot management.

Loot is documented, not computed. The loot page says which system the guild uses and names its addon. Accord detects that addon in every member's client and, for FDCP, reads what FDCP publishes. Release: `v0.11.0`.

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

The loot and raid-roster addons that run on Forever, from a survey of their public pages on 2026-11-24 (CurseForge, GitHub, Wago, wowcalc.net, timesaver.gg, guildmanager.app). Guild-management addons are left out on purpose (M10 integration rule 6). None of it has been checked in the game; M11.1 checks the list again and M10.2 confirms the folder names in game.

| Addon | Kind | Loot system | Public API or exchange | Plan in Accord |
|---|---|---|---|---|
| **Finland Dragon Credit Points (FDCP)** | loot and raid (same owner) | credits: fewest credits wins, then the roll; council | none yet; Accord asks for a read-only versioned API (SPEC-10 Q10) | level 0 now; level 1 when FDCP publishes the API: season roster, lineup and bench, a member's credits and queue place, the rules summary |
| **Gargul** | loot | soft reserve, rolls and plus-ones, TMB or DFT wishlists, GDKP | imports from softres.it and TMB; no documented API found | level 0 |
| **RaidCore** | loot | soft reserve, loot council (from RCLootCouncil Classic) | JSON exports for its own website | level 0 |
| **WLC** | loot | loot council with votes | CSV and TMB-style export | level 0 |
| **Forever Loot Manager** | loot | DKP, open-bid auctions | CSV export, also of attendance | level 0 |
| **NostalgiaForeverLC** | loot (alpha) | hard and soft reserve, raid leader hands out | text import and export, softres.it CSV | level 0 |
| **RollForMe** | loot | +1 / MS / OS rolls, soft reserve, DKP, council | not known (the page did not load) | level 0, if M11.1 confirms it |

Notes:
- **RCLootCouncil** had no Forever file at the time of the survey; RaidCore says standalone RCLootCouncil clients do not get its council requests.
- **GDKP:** Blizzard stated that GDKP is not allowed in WoW Forever, at least in North America and Europe (reported by guildmanager.app, not checked at the source). Accord's templates and texts never propose it.

### M11.1 — Specification
- Branch: `step/m11-1-spec`
- Scope: write a new SPEC-15 ("Manuale di gilda e loot"), in Italian. It covers:
  - the `handbook` data set: pages, revisions, size limits, who can write;
  - the reader and the editor;
  - the default pages;
  - the loot page: the guild's loot system, the chosen addon, detection and the FDCP provider.

  It updates the survey above (which addons run on Forever then, their folder names, whether any has gained a public API). It records which data FDCP's API would give to a member's client and which only to an officer's.
- Done when:
  - [ ] SPEC-15 is linked from the spec index; SPEC-10 Q6 stays answered and Q10 is updated; `tools/check_docs.py` passes.

### M11.2 — Handbook data
- Branch: `step/m11-2-handbook-data`
- Spec: SPEC-15
- Scope:
  - each page has an id, title, body, order and revision, and keeps its last few revisions;
  - only ranks the guild chooses can write (officers by default);
  - pages are synced on `GUILD`, and long bodies are sent in parts.
- Done when:
  - [ ] A page from a non-writer is refused; two edits of the same revision keep the newer and flag the conflict to its author.

### M11.3 — Reader
- Branch: `step/m11-3-reader`
- Spec: SPEC-15; SPEC-04
- Scope: a Handbook view with:
  - the page list;
  - the reader, with headings, lists and links between pages;
  - search;
  - a mark on pages updated since the player last read them.
- Done when:
  - [ ] Every member can read every page offline from the last sync; the "updated" mark clears on reading.

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
    - the **loot addon**: one of the known addons of M10.2, "other" with a name, or none;
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
