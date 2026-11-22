# M7 — Data trust and quality

**Goal:** every value says where it comes from and how old it is. Alts in other guilds show that guild. A demo mode, a personal backup, a "what I share" panel and an About page with the credits are added. The network is hardened against bad peers and very large guilds. Release: `v0.7.0`.

**Exit criterion:** in game, the member card of a player with an alt in another guild shows "Other guild: <name>" with the date that alt was last seen. The "what I share" panel lists exactly what the player's own records contain.

**Before it starts:** M1–M6 are released one by one as `v0.1.0` … `v0.6.0`, each after its in-game check. This milestone may start while the owner runs those checks.

### M7.1 — Specification
- Branch: `step/m7-1-spec`
- Scope: write a new SPEC-11 ("Fiducia nei dati"), in Italian. It covers provenance labels, the guild of alts outside the guild, demo mode, backup, the privacy panel and the hardening limits. Update SPEC-03 (the `chars` fields), SPEC-05 (ACC-03) and add a note to ADR 0006: the guild of each listed character is shared, by the owner's decision of 2026-11-20.
- Done when:
  - [ ] SPEC-11 exists, is linked from the spec index, and the ADR index is updated; `tools/check_docs.py` passes.

### M7.2 — Provenance labels
- Branch: `step/m7-2-provenance`
- Spec: SPEC-11
- Scope: one label widget used by every view. It shows the source (`native`, `shared`, `own`, `note`) and the age (`observedAt`), with a tooltip saying who reported the value.
- Done when:
  - [ ] Roster cells, the member card, recipes, likes and bank show the label. Old shared values are dimmed after a threshold set in SPEC-11.

### M7.3 — Guild of alts outside the guild
- Branch: `step/m7-3-alt-guilds`
- Spec: SPEC-11; SPEC-03; SPEC-05 ACC-03; ADR 0006 note
- Scope:
  - `chars` entries of the `accounts` record gain `guild` (the guild name, or empty for no guild) and `seen` (the last login of that character with the addon). They are taken from the local `AzerothAccordDB.chars`.
  - The member card and the grouped Roster rows show "Other guild: <name> · seen N days ago" or "No guild" instead of the bare "not in guild".
  - Characters known only from a public note show no guild.
  - Older clients ignore the new fields. The record stays inside its size limit.
- Done when:
  - [ ] On a third client, an alt in another guild shows that guild's name and age; an alt with no guild shows "No guild"; a change of guild shows after that alt logs in again (`Tests/test_accounts.lua`).
  - [ ] The wiki page on alts explains what is shown, that it is as old as the last login of that alt, and that the other guild does not see Accord's data.
- Real client: the guild name read at login (`GetGuildInfo("player")`) on an alt in another guild, and its spelling with spaces and accents.

### M7.4 — Demo mode
- Branch: `step/m7-4-demo`
- Spec: SPEC-11
- Scope: `/accord demo` fills every view from a synthetic guild with invented names. It sends nothing, saves nothing, and shows a strip saying "Demo". The mockup tools of ADR 0019 can reuse the same data.
- Done when:
  - [ ] Every view opens in demo mode with no guild and no network; leaving demo mode restores the real data untouched.

### M7.5 — Personal backup
- Branch: `step/m7-5-backup`
- Spec: SPEC-11
- Scope: export the player's own data (characters, main, settings, own records, the account token) to a text in a selectable box. Import it on another computer, with validation and a preview of what changes.
- Done when:
  - [ ] A round trip restores the same data; a damaged or foreign text is refused with a clear message; guild data of other players is never in the export.

### M7.6 — "What I share" panel
- Branch: `step/m7-6-privacy-panel`
- Spec: SPEC-11; SPEC-04
- Scope: a Settings page listing every data set this character publishes and its current content. That includes the alt list with their guilds, BattleTag and Discord (always shared, D3), recipes, co-play and bank snapshots. What can be switched off has its switch there.
- Done when:
  - [ ] The panel shows the same content as the records the client last sent (`Tests/test_settings.lua`).

### M7.7 — Hardening
- Branch: `step/m7-7-hardening`
- Spec: SPEC-02 §6; SPEC-09 §5
- Scope:
  - malicious-peer tests: oversized and malformed payloads, forged authors, replayed revisions, floods;
  - a burst test with 1000 members logging in together in the simulator;
  - a check of Forever full names with spaces ("Name Surname") in Compat, names and notes.
- Done when:
  - [ ] Every bad-peer case is refused without errors and without blocking the queue; the burst stays inside the traffic budget; names with spaces round-trip through every data set.

### M7.8 — About and credits
- Branch: `step/m7-8-credits`
- Spec: SPEC-04 (a new "About" section); SPEC-11
- Scope: the owner asked (2026-11-22) for a credits and information section, in the addon and in the documentation. It tells the addon's story: it was created and designed by **Finland** (the owner) for the Italian guild **NEBULA**.
  - In the addon: an **About** page, reached from the Settings view and the game's settings panel, and with `/accord about`. It shows:
    - the name, the version and two lines on what the addon does;
    - "Created and designed by Finland";
    - "Made with the Italian guild NEBULA";
    - the GPL-3.0 licence;
    - the repository address as selectable text.
    It is in English and Italian. The TOC gains `## X-Credits`.
  - In the documentation: a **Credits** section in `README.md` and `README.it.md`, and a wiki page **About** linked from Home, the sidebar and the footer.
  - A design preview of the About page is added to the mockups (ADR 0019).
  - Use only the facts the owner gave. Further details (realm, Discord invite, logo, other people to thank) go in only if the owner provides them.
- Done when:
  - [ ] The About page opens from Settings and from `/accord about` in both languages; the texts are locale keys (`Tests/test_locales.lua`); the wiki page and both README sections exist; `tools/check_docs.py` passes.
- Real client: the page in the Settings view and in the game's settings window.

### M7.9 — In-game check and release
- Branch: `step/m7-9-check`
- Scope: `docs/checklists/M7.md` and the README status. The owner releases `v0.7.0`.
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.7.0`.
