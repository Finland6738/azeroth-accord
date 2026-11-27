# Mockups and design previews

Pictures of the Azeroth Accord interface, made before the addon runs in the real client. They are **design previews, not screenshots**: drawn from the addon's own layout and texts, in the look of the interface (the widget kit and the three themes under the Material 3 rules, [`ui-style.md`](../ui-style.md) §9, [ADR 0021](../../adr/0021-interface-follows-the-ecosystem-style-of-fdcp.md) and [ADR 0027](../../adr/0027-material-3-rules-adapted-to-accord.md)), so the real window may differ in small details (the game's own font smoothing and textures, exact spacing, the way the guild window is dressed in the theme, [`ui-style.md`](../ui-style.md) §3, with generic line icons in place of the game's tab icons). Every image says so in its bottom strip.

Rules for every image here ([ADR 0019](../../adr/0019-design-previews-original-art-invented-data.md)):

- **Original art only.** Class squares, the guild window's themed frame and side tabs, tab icons and item pictures are made of CSS shapes and inline SVG. The only pictures are the addon's own logo and the NEBULA logos of [`assets/`](../../../assets/). The fonts are the ones the addon ships (Outfit, JetBrains Mono, Orbitron, SIL OFL 1.1, from `AzerothAccord/Media/Fonts/`). No game screenshot, icon, texture or font is used or copied, and nothing is loaded from the network when an image is made.
- **Invented data.** The guild (*Lantern Company*), the characters, the notes and the Discord and BattleTag names are made up; no real player, guild or account appears. Item and recipe names are the game's own words.
- **The texts are the addon's.** Every interface text is read from `AzerothAccord/Locale/enUS.lua` (and `itIT.lua` for the Italian previews), so a preview never disagrees with the addon; rerun the generator after a change of the interface.
- **Light files.** WebP, quality 80, about 35 to 90 KB each.

## What is here

| Folder | Content | Made by |
|---|---|---|
| [`html/`](html/) | the style sheet ([`accord.css`](html/accord.css): the three themes as tokens and the pieces of the widget kit, written from `tools/mockup_lib.py`) and the annotated main screens: `00-design-system`, `01-accord-tab`, `02-member-card`, `03-bank-requests` | `python -X utf8 tools/make_mockups.py --spec` |
| [`img/`](img/) and [`img/clean/`](img/clean/) | the same pages rendered, with numbered callouts and a legend (`img/`) and without them (`img/clean/`) | `bash docs/specs/mockups/render.sh` |
| [`previews/`](previews/README.md) | one image for each main view and state, in Nebula: the Accord tab, the Roster (table, grouped by account), the member card, recipes and *who can craft*, likes, the social index, the group map, *someone new*, every Bank mode (tabs, items, log, donations, money, requests, inbox), Settings (the Appearance card and the rest), the Info page, the diagnostics box, the standalone window; three in the light theme Aurora (the Roster, Bank requests, Info), two in the theme Accord (the member card, Bank items), and four Italian ones | `python -X utf8 tools/make_mockups.py` |
| [`compare/`](compare/README.md) | one sheet that puts Accord's previews beside the ones of Finland Dragon Credit Points, to check that the two addons look like one family | `python tools/make_compare.py` |

## Making the images again

Needs Python with Pillow (`python -m pip install pillow`; plain `python`, not `python -I`) and Chrome or Edge (the `CHROME` environment variable overrides the search; Edge is found on a standard Windows install). The browser runs headless and locally: it reads the style sheet, the fonts and the logos from this repository and nothing else.

```bash
python -X utf8 tools/make_mockups.py            # the previews (previews/*.webp and its README.md)
python -X utf8 tools/make_mockups.py bank       # only the previews whose name contains "bank"
python -X utf8 tools/make_mockups.py --spec     # the style sheet and the annotated pages (html/)
bash docs/specs/mockups/render.sh               # the annotated pages as images (img/ and img/clean/)
python tools/make_compare.py                    # the comparison sheet (needs ../finland-dragon-credit-points next to this repository, read only)
```

The scenes are `tools/mockup_scenes.py` and `tools/mockup_scenes2.py`, the building blocks and the tokens of the themes `tools/mockup_lib.py`, the annotated pages `tools/mockup_spec.py`. `tools/check_docs.py` builds every scene from the locale tables and fails if a preview or the style sheet is missing or out of date. The wiki and the READMEs embed these files with relative links; `tools/sync_wiki.py` copies the ones the wiki shows into its `images/` folder.

Adapted from the mockup tools of Azeroth Guild Finder (same owner, GPL-3.0, [ADR 0018](../../adr/0018-reuse-azeroth-guild-finder-foundations.md)), whose pipeline (headless browser, "Design preview" strip, WebP, index) is kept; and, for the look, from those of Finland Dragon Credit Points (read only, [ADR 0021](../../adr/0021-interface-follows-the-ecosystem-style-of-fdcp.md)): the style sheet and the components are FDCP's, with Accord's tokens.
