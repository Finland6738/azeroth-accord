# Mockups and design previews

Pictures of the Azeroth Accord interface, made before the addon runs in the real client. They are **design previews, not screenshots**: drawn from the addon's own layout and texts, in the look of the game's guild window (the panel is drawn with the client's own frame templates, font objects and colours, [SPEC-04 §5](../SPEC-04-ui-guild-tab-shell.md)), so the real window may differ in small details (the game's fonts and textures, icons, exact spacing). Every image says so in its bottom strip.

Rules for every image here ([ADR 0019](../../adr/0019-design-previews-original-art-invented-data.md)):

- **Original art only.** Class badges, the guild emblem, tab icons and item pictures are made of CSS shapes and inline SVG. No game screenshot, icon, texture or font is used or copied, and nothing is loaded from the network when an image is made.
- **Invented data.** The guild (*Lantern Company*), the characters, the notes and the Discord and BattleTag names are made up; no real player, guild or account appears. Item and recipe names are the game's own words.
- **The texts are the addon's.** Every interface text is read from `AzerothAccord/Locale/enUS.lua` (and `itIT.lua` for the Italian previews), so a preview never disagrees with the addon; rerun the generator after a change of the interface.
- **Light files.** WebP, quality 80, about 40 to 130 KB each.

## What is here

| Folder | Content | Made by |
|---|---|---|
| [`html/`](html/) | the design system ([`accord.css`](html/accord.css)) and the annotated main screens: `00-design-system`, `01-accord-tab`, `02-member-card`, `03-bank-requests` | `python -X utf8 tools/make_mockups.py --spec` |
| [`img/`](img/) and [`img/clean/`](img/clean/) | the same pages rendered, with numbered callouts and a legend (`img/`) and without them (`img/clean/`) | `bash docs/specs/mockups/render.sh` |
| [`previews/`](previews/README.md) | one image for each main view and state: the Accord tab, the Roster (table, grouped by account), the member card, recipes and *who can craft*, likes, the social index, the group map, *someone new*, every Bank mode (tabs, items, log, donations, money, requests, inbox), Settings (two parts), the diagnostics box, the standalone window, and three Italian ones | `python -X utf8 tools/make_mockups.py` |

## Making the images again

Needs Python with Pillow (`python -m pip install pillow`) and Chrome or Edge (the `CHROME` environment variable overrides the search; Edge is found on a standard Windows install).

```bash
python -X utf8 tools/make_mockups.py            # the previews (previews/*.webp and its README.md)
python -X utf8 tools/make_mockups.py bank       # only the previews whose name contains "bank"
python -X utf8 tools/make_mockups.py --spec     # the annotated pages (html/0*.html)
bash docs/specs/mockups/render.sh               # the annotated pages as images (img/ and img/clean/)
```

The scenes are `tools/mockup_scenes.py` and `tools/mockup_scenes2.py`, the building blocks `tools/mockup_lib.py` and `tools/mockup_spec.py`. The wiki and the READMEs embed these files with relative links; `tools/sync_wiki.py` copies the ones the wiki shows into its `images/` folder.

Adapted from the mockup tools of Azeroth Guild Finder (same owner, GPL-3.0, [ADR 0018](../../adr/0018-reuse-azeroth-guild-finder-foundations.md)): the pipeline (headless browser, "Design preview" strip, WebP, index) is the same; the look is not, because Accord's panel has the game's own look and Guild Finder's has its own parchment skin.
