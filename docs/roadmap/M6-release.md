# M6 — Release

**Goal:** `v0.6.0`: settings, Italian interface, polish, packaging, the images of the manual and the full manual.

### M6.1 — Settings
- Branch: `step/m6-1-settings`
- Spec: SPEC-04 §4 ("Impostazioni")
- Scope: Settings view and the game's Settings panel: Discord handle, main character, columns, notifications, data sizes and "clear guild data".
- Done when:
  - [x] `UI/SettingsModel.lua` (the options `notifyOfficer` and `notifyDecision` with defaults, validation and `SETTINGS_CHANGED`; main character choice; Roster columns; sizes of the saved data per data set; "Clear guild data" that keeps what only this computer knows) and `UI/Settings.lua` (one scrolling page drawn in the Settings view of the panel and in a canvas panel registered with `Settings.RegisterCanvasLayoutCategory` when the client has it); the bank notices follow the options; a change in one page shows in the other (`Tests/test_settings.lua`).
  - [ ] In game: the panel appears in the game's Settings window, the page scrolls, "Clear guild data" refills from the guild ([the release check](../checklists/release.md)).

### M6.2 — Italian interface
- Branch: `step/m6-2-itit`
- Spec: ADR 0015
- Scope: complete `Locale/itIT.lua`; a test that checks every key in both locales.
- Done when:
  - [x] `Locale/itIT.lua` has all 351 keys (reviewed: the Settings texts, "In arrivo" instead of "Posta" for the officers' inbox, which would be read as the game's mail); `Tests/test_locales.lua` checks keys, placeholders and their order, codes, untranslated strings, the keys the code reads and the key families, and runs an Italian client through every view.
  - [ ] In game with an Italian client: no English left on screen, no overflowing text ([the release check](../checklists/release.md)).

### M6.3 — Polish and performance
- Branch: `step/m6-3-polish`
- Scope: empty states, loading states, error texts, large-guild profiling (S11 numbers), memory and SavedVariables sizes.
- Spec: SPEC-09 §5
- Done when:
  - [x] A view that raises while it is built shows an error text and leaves the panel and the other views working (`Tests/test_states.lua`); every view opens in a guild whose roster has not loaded and in a client without the optional APIs; the empty-state texts are pinned; the Settings page counts only while shown.
  - [x] A 1000-member guild with 400 addon users and 90 days of co-play: the saved file, memory and the time of each heavy step stay inside budgets, numbers in SPEC-09 §5 (`Tests/test_large_guild.lua`); `/accord debug` reports the addon's memory.
  - [ ] In game: the S11 numbers (roster and index with 500+ members), the memory figure and the size of the saved file after a week of play.

### M6.4 — Diagnostics and bug reports
- Branch: `step/m6-4-diagnostics`
- Scope: `/accord debug` report box without names, issue form fields aligned.
- Spec: SPEC-09 §6
- Done when:
  - [x] A guild full of names yields a report with none of them, no token, no character id; a name in an error message is replaced by a placeholder; the header has the form's facts (addon, client, locale, role, guild size); the report is capped and the box shows its size (`Tests/test_report.lua`); the bug and in-game report forms name the report lines and `tools/check_addon.py` checks it.

### M6.5 — Packaging and release workflow
- Branch: `step/m6-5-packaging`
- Scope: BigWigs packager, GitHub Releases, optional CurseForge (disabled until the owner decides, SPEC-10 Q9), `docs/RELEASING.md`.
- Spec: SPEC-09 §4
- Done when:
  - [x] The release workflow (BigWigs packager, package and zip checks, GitHub Release with the notes of `CHANGELOG.md`, CurseForge only with `CF_API_KEY` and a project id in the TOC) is in place and has **not run**: no tag exists; `tools/release_notes.py` writes the notes and promotes *Unreleased* (self-tested by `tools/check_docs.py`); the TOC has the commented CurseForge line; `docs/RELEASING.md` lists the versions, the checks that come first and the owner's steps; SPEC-10 Q9 records the CurseForge decision.
  - [ ] The first dry run of the workflow (Actions, *Run workflow*, nothing published) and a draft release, then the real tag: the owner, after the in-game checks.

### M6.6 — Wiki mockups and images
- Branch: `step/m6-6-mockups`
- Spec: SPEC-04 §5
- Scope: port and adapt the mockup tools of Azeroth Guild Finder (`docs/specs/mockups/`, `tools/make_mockups.py`, `tools/mockup_lib.py`, `tools/mockup_scenes*.py`): design previews of every main view drawn from the addon's real layout and English texts, with a "Design preview" strip because nothing has run in the real client yet; embedded in the wiki pages and in `README.md` / `README.it.md`.
- Spec: SPEC-04 §5; ADR 0019
- Done when:
  - [x] `tools/make_mockups.py`, `mockup_lib.py`, `mockup_scenes.py`, `mockup_scenes2.py`, `mockup_spec.py` and `docs/specs/mockups/` (`html/accord.css`, `accord.js`, four annotated pages, `render.sh`, `optimize_images.py`, `README.md`) make 24 design previews (the Accord tab, Roster table and grouped, member card, recipes, who can craft, likes, social index, group map, someone new, the seven Bank modes, Settings in two parts, the diagnostics box, the standalone window, three Italian ones) and four annotated mockups in WebP, from the addon's own texts, with original art and invented data and a "Design preview" strip; embedded in every wiki page of a feature, in the Interface Tour and in both READMEs.
  - [ ] Replace a preview with a real screenshot, view by view, as the in-game checks run (ADR 0019 rule 6).

### M6.7 — Release checklist and v0.6.0
- Branch: `step/m6-7-release`
- Scope: `docs/checklists/release.md` in game, wiki complete, READMEs, tag `v0.6.0` (the tag waits for the owner; `v1.0.0` comes after M15, [ADR 0020](../adr/0020-one-version-per-milestone.md)).
- Done when:
  - [x] [`docs/checklists/release.md`](../checklists/release.md) (the order of the checks M1 to M5 and this one, what is not known yet, the package, Settings and the game's settings window, Italian, performance and S11, errors and the report, the pictures, the workflow dry run and test tag, the owner's open decisions, the release steps), the wiki (every page with its images, the Settings page, FAQ, Installation, Reporting), both READMEs, the status of every document.
  - [ ] The in-game checks of M1 to M5 and of the release check pass; the changelog is promoted (`tools/release_notes.py --promote 0.6.0`); the tag `v0.6.0` (**not created**: it waits for the owner, [docs/RELEASING.md](../RELEASING.md)).
