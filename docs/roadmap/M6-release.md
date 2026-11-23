# M6 — Release

**Goal:** `v0.6.0`: settings, Italian interface, polish, packaging, the images of the manual and the full manual, and the look of the owner's other addon, Finland Dragon Credit Points (FDCP), with the About page and the credits.

**The ecosystem look (M6.8–M6.17).** On 2026-11-23 the owner asked that Accord look like FDCP, so that the two addons read as one family, and approved this plan inside M6, so that `v0.6.0` ships with the new look. FDCP, in `../finland-dragon-credit-points`, is only read, never changed; its files are copied and adapted (names, prefixes, SavedVariables), with no shared library. Its graphic specification is FDCP's `docs/specs/ui-style.md`. Every step keeps the rules: no Blizzard art copied into the repository, no text written in the code (every string is a locale key, English and Italian), only the public name "Finland", and the pull request says what was not seen in game.

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
  - [ ] The in-game checks of M1 to M5 and of the release check pass; the changelog is promoted (`tools/release_notes.py --promote 0.6.0`); the tag `v0.6.0` (**not created**: it waits for the owner, [docs/RELEASING.md](../RELEASING.md)). The tag also waits for the ecosystem look, M6.8 to M6.17, whose checks M6.16 adds to the release checklist.

### M6.8 — Interface style specification
- Branch: `step/m6-8-ui-style`
- Spec: new `docs/specs/ui-style.md`; SPEC-04; ADR 0021
- Scope:
  - Accord's `docs/specs/ui-style.md`, in Italian. It names FDCP's `docs/specs/ui-style.md` as the base and writes down **only the differences**: the names and prefixes (`AzerothAccord`, `AzerothAccordDB`), where the personal settings are saved, the views turned into tabs (Roster · Professions · Reputation · Bank · Settings, with Info under Settings), the panel drawn inside the guild window as well as in the standalone window, and the three themes.
  - Themes: **Nebula** (default) and **Aurora** (light) with FDCP's tokens unchanged; a third theme, **Accord**, from the logo's palette (dark teal-green, gold, mint), as FDCP's "Drago" comes from its own logo. Token names stay FDCP's.
  - ADR 0021 "The interface follows the ecosystem style of FDCP"; the notes it adds to SPEC-04 (the game's own look in `UI/Skin.lua` is replaced) and to ADR 0019 (previews in the new look).
- Done when:
  - [x] `docs/specs/ui-style.md` and ADR 0021 exist and are indexed; SPEC-04 points to them; `tools/check_docs.py` passes.

### M6.9 — Media, fonts and licences
- Branch: `step/m6-9-media`
- Spec: `ui-style.md`; ADR 0021
- Scope:
  - `tools/make_media.py` and `tools/make_fonts.py` from FDCP. `AzerothAccord/Media/`: the white textures tinted at runtime (rounded fill, pill, circle, small and large glow, radial blob, icon sheet), the addon's logo as `logo_256` and `logo_64` from `assets/logo-source.webp`, and the NEBULA logos for the credits from `assets/nebula-logo-dark.png` and `assets/nebula-logo-light.png`.
  - `Media/Fonts/`: Outfit, JetBrains Mono and Orbitron with their SIL OFL 1.1 texts (Orbitron is a Reserved Font Name: shipped whole and unmodified).
  - `docs/third-party.md` with every font, texture and logo and its licence; the NEBULA logos are used with the guild's permission.
  - The logo becomes the icon of the AddOn Compartment and of the window. SPEC-10 Q2 (the tab's icon) gets the logo as a proposal for the owner.
- Done when:
  - [x] Running the two tools again changes no file; `tools/check_package.py` finds every texture and font in the package and every font's licence; `tools/check_addon.py` fails on a media file missing from `docs/third-party.md`.
- Real client: the TGA textures and the fonts load on Forever.

### M6.10 — Theme, assets and motion
- Branch: `step/m6-10-theme`
- Spec: `ui-style.md` §2, §7
- Scope:
  - `UI/Theme.lua`, `UI/Assets.lua` and `UI/Motion.lua` adapted from FDCP. Theme: tokens, tinting, a weak-keyed registry of themed regions so that a theme changes without `/reload`, `Px()` for pixel-exact lines, glows only on dark themes, the fonts with the game's fonts as fallback. Motion: fades, rise, slide, press, pulse at 120, 200 and 320 ms.
  - Personal settings, saved per account with a migration in `Core/Config.lua`: theme, neon effects, animations, font.
  - The mock client gains what the theme needs (textures and slice margins, animation groups, font objects), from FDCP's mocks.
- Tests: `Tests/test_theme.lua`: every theme has every token; a change of theme repaints every registered region; effects off hides the glows; animations off makes every motion immediate; a missing font falls back to the game's.
- Done when:
  - [x] The tests pass; nothing on screen changes yet.
- Real client: the fonts, the 9-slice and `Px()` at several UI scales.

### M6.11 — Widgets
- Branch: `step/m6-11-widgets`
- Spec: `ui-style.md` §3
- Scope: `UI/Widgets/` from FDCP: Button, Card, Badge, Tabs (with the moving indicator and an optional count badge), Segmented, Chip, TitleBar, Dialog, EditBox, ChoiceList, Switch, Slider, Select (menus without `UIDropDownMenu`), Snackbar, Skeleton, ClassMark, ThinBar, the addon's own Tooltip, and DataTable (FDCP's own pooled table with a thin scroll indicator, which behaves the same on every client; no ScrollBox, so no `FauxScrollFrame` fallback is needed, see `ui-style.md` §3). The old `UI/Widgets/Base.lua` stays until M6.14 and keeps `ns.Widgets`: the new widgets live in `ns.Kit`, which becomes `ns.Widgets` in M6.14.
- Tests: `Tests/test_widgets.lua`: every widget builds in every theme, follows a change of theme, and takes its texts only from locale keys.
- Done when:
  - [x] The tests pass.

### M6.12 — Window, title bar and tabs
- Branch: `step/m6-12-window`
- Spec: SPEC-04; `ui-style.md` §6
- Scope:
  - `UI/Shell.lua` and `UI/Window.lua` rebuilt: the standalone window gets the 52-point title bar (logo, name, sync state, pop in, close) and the tab bar with its indicator, which replaces the left navigation.
  - In the guild window (`UI/GuildTab.lua`) the panel is themed inside Blizzard's frame, with the same tabs; Blizzard's frame is still only observed (ADR 0003).
  - Size and position remembered, Esc, `/accord`, the compartment and the key binding work as before.
- Done when:
  - [x] The shell tests pass with the tabs; every view opens from its tab and from its command.
  - [x] Wiki: Interface Tour and Commands.
- Real client: the panel inside the guild window, taint, combat, resizing.

### M6.13 — Views, part 1: Roster, member card, Professions
- Branch: `step/m6-13-views-1`
- Spec: SPEC-05; SPEC-06; `ui-style.md`
- Scope: the Roster in a DataTable (sorting, search, filters with chips, grouped rows), the member card in cards with badges, the Professions view and "who can craft". Behaviour does not change.
- Done when:
  - [x] The existing tests of these views pass unchanged or with only layout changes; wiki pages Guild Roster and Professions and Recipes.
- Real client: how the Roster, the member card and the Professions list look and scroll (9-slice, class marks, clipping of the card, wheel), the Kit.Menu and Kit.Select popups over the guild window, the toolbar width with Italian texts, speed with a real 1000-member guild.

### M6.14 — Views, part 2: Reputation, Bank, Settings, and the old look removed
- Branch: `step/m6-14-views-2`
- Spec: SPEC-07; SPEC-08; SPEC-04 §4; `ui-style.md`
- Scope:
  - Likes, social index, group map, the seven Bank modes, the diagnostics and copy boxes.
  - Settings with a new **Appearance** card: theme, neon effects, animations, font; a change shows at once.
  - `UI/Skin.lua` and `UI/Widgets/Base.lua` are removed.
  - `tools/check_addon.py` gains `check_ui_colours` (no colour written outside `UI/Theme.lua`, as in FDCP).
- Tests: a test that no text reaches the screen without a locale key; `Tests/test_settings.lua` covers the Appearance card.
- Done when:
  - [x] All tests and checks pass; wiki pages Likes and Social Index, Guild Bank, Settings.
- Real client: every restyled view (pills, slots, cards that fit their text, switches), the Appearance card changing theme, effects, animations and font without `/reload`, the Settings page in the game's settings window, the logo on the guild-window tab.

### M6.15 — About and credits
- Branch: `step/m6-15-credits`
- Spec: SPEC-04 (a new "Informazioni" section); `ui-style.md`
- Scope: the owner asked (2026-11-22) for a credits and information section, in the addon and in the documentation. It was planned as M7.8 and moved here on 2026-11-23, so that it is drawn once, in the new look.
  - In the addon: an **Info** page under Settings, also opened by `/accord about`; `/accord about chat` prints the credits in the chat. The page shows:
    - the logo, the name, the version and two lines on what the addon does;
    - "Created and designed by Finland";
    - "Made with the Italian guild NEBULA", with the NEBULA logo of the theme (the dark one on dark themes, the light one on Aurora);
    - the links in read-only boxes to copy: the repository, the issues, the NEBULA page (https://nebula-community.github.io/giochi/wow-forever/), Ko-fi (https://ko-fi.com/finland6738);
    - the GPL-3.0 licence and a pointer to `docs/third-party.md`;
    - "The NEBULA logo is used with the guild's permission";
    - a fan-made disclaimer: not made by or affiliated with Blizzard Entertainment.
  - The TOC gains `## X-Credits` and `## X-Website`.
  - In the documentation: a **Credits** section in `README.md` and `README.it.md`; wiki pages `About.md` and `About-it.md`, linked from `_Sidebar.md` and Home. If an `assets/CURSEFORGE.md` is added (CurseForge is off, SPEC-10 Q9), it gets the same credits.
  - Only the facts the owner gave; no real names.
- Tests: `Tests/test_ui_about.lua`: the page in both languages and in every theme, the logo follows the theme, every text is a locale key, the chat command.
- Done when:
  - [ ] The tests pass; the README sections and both wiki pages exist; `tools/check_docs.py` passes.
- Real client: the page in the Settings view and in the game's settings window; selecting and copying a link.

### M6.16 — Design previews and the release check
- Branch: `step/m6-16-previews`
- Spec: SPEC-04 §5; ADR 0019; `ui-style.md` §8
- Scope:
  - The mockup tools take FDCP's style sheet and components; every design preview of M6.6 is drawn again in the new look, in Nebula, with a few in Aurora and in Accord, and the About page is added.
  - A comparison sheet puts Accord's previews beside FDCP's, to check that the two addons match.
  - `docs/checklists/release.md` gains the checks of the look: the three themes, effects and animations off, the fonts, several UI scales, the panel inside the guild window, the About page.
- Done when:
  - [ ] `tools/make_mockups.py` makes every preview; the wiki and both READMEs show the new ones; `tools/check_docs.py` passes.

### M6.17 — Italian wiki
- Branch: `step/m6-17-wiki-it`
- Spec: ADR 0015 (changed: the manual is also in Italian)
- Scope: an Italian twin `<Page>-it.md` of every wiki page, a language link at the top of each page, and both languages in `_Sidebar.md`. `tools/check_docs.py` checks that every page has its twin and that both show the same images.
- Done when:
  - [ ] Every wiki page has its Italian twin; ADR 0015 records the change; `tools/check_docs.py` passes.
