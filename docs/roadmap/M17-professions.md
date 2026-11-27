# M17 — Professions assistant

**Goal:** an assistant that levels every profession from 1 to 300 inside Accord. For each step it shows what to craft or where to gather, and the materials as **owned/needed**. A small movable tracker follows the player while they craft. The owner asked for it on 2026-11-27 and answered the design questions the same day (below). After M17 comes the release of `v1.0.0` ([ADR 0020](../adr/0020-one-version-per-milestone.md), update of 2026-11-27).

**Switched off until complete.** Everything of M17 ships behind a new switch `professions` in `AzerothAccord/Core/Features.lua`. The last step turns it on.

**Exit criterion:** in game, a player opens a crafting profession's window and sees:
- the current step of the route;
- the materials as owned/needed, counting the bags, the bank and an alt.

They craft until the next skill level, and the assistant moves to the next step by itself. Materials the player lacks go to the shopping list (M13.4) with one click.

## Owner's decisions (2026-11-27)

- **Everything native, no external links.** Accord shows no address of any website, and opens none.
- **Route data, option c: both of these.**
  - A full 1–300 route **computed by Accord**, from a bundled table of each recipe's skill thresholds (orange, yellow, green, grey). The table comes from an **open-source source whose licence allows it**; the source and the licence are proposed to the owner in M17.1, before use.
  - A live **best recipe now**, from the colours the game shows in the open profession window.
- **Guides of other sites are not copied.** They carry no licence, so all rights are reserved. Their routes, texts and tables stay out of Accord unless their author gives written permission. The owner may ask for it; with a permission, a route from such a site can be added as an option, credited in About. Without one, Accord computes its own route and builds its own tables from open data and from data gathered in game.
- **Owned** counts the bags, the bank, the player's alts and the mail, as the shopping list of M13.4 does (the same module). The guild bank has a column of its own.
- **Intermediate materials** are broken down into raw ones, with an on/off switch.
- **Prices** from Auctionator, read-only, when it is installed.
- **Missing materials** go to the shopping list, and from there to the guild (wishlist) or to the guild bank (request).
- **The "Create" button** in the tracker crafts directly when the game allows it. Otherwise it selects the recipe in the profession window.
- **Professions:**
  - crafting, with the full route, the tracker and "missing to the shopping list": Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, Cooking (with a Fishing + Cooking option), First Aid;
  - gathering, secondary and Forever skills, with internal tables of level bands, zones, spots or progression: Mining, Herbalism, Skinning, Fishing (alone and with Cooking), Lockpicking, Camping, Merchant's Favor.

## M17.1 — Specification
- Branch: `step/m17-1-spec`
- Scope: write a new SPEC-21 ("Assistente delle professioni"), in Italian. It covers:
  - **the data sources**: for each table (recipe thresholds; gathering bands and zones; Lockpicking, Camping and Merchant's Favor), an open source with its licence, or "gathered in game" with how. The proposal goes to the owner as a SPEC-10 question before M17.2. A tool in `tools/` builds each table, never by hand.
  - what the game gives on Forever: the whole recipe list and its reagents (`C_TradeSkillUI`); the recipe colours in the open window; the skill levels (`C_SkillInfo`); item counts (`C_Item.GetItemCount`); the mail; whether crafting from an addon is allowed, and with what.
  - the route algorithm: the cheapest by materials owned and prices, else by the fewest crafts, and how it chooses among orange and yellow recipes; how "best now" corrects it;
  - the views: the levelling page in the **Professions** tab, the tracker as an M3 side sheet ([ui-style §9](../specs/ui-style.md#9-le-regole-di-material-3-adr-0027)), owned/needed bars;
  - what is local and what is shared (nothing of the route is sent);
  - new SPEC-10 questions for what is still open.
- Done when:
  - [ ] SPEC-21 is linked from the spec index; the data sources are an answered SPEC-10 question; `tools/check_docs.py` passes.

## M17.2 — Data tables
- Branch: `step/m17-2-data`
- Spec: SPEC-21; the owner's answer on the sources
- Scope:
  - the tools that build the thresholds table and the gathering and Forever-skill tables from the approved sources, with each licence in `docs/third-party.md` and the credits;
  - the tables in `AzerothAccord/Data/`, as compact as the recipe encoding (`Recipes.Encode`).
- Done when:
  - [ ] The tables are rebuilt by the tools, not edited by hand; `tools/check_addon.py` checks they are listed with their licence.

## M17.3 — Route engine
- Branch: `step/m17-3-route`
- Spec: SPEC-21
- Scope:
  - the 1–300 route of a crafting profession from the thresholds and the recipe reagents (read from the game, cached with the recipe catalogue);
  - "best recipe now" from the colours of the open window;
  - recomputing when the skill rises (`SKILL_LINES_CHANGED`) or the owned materials change;
  - the Fishing + Cooking option.
- Done when:
  - [ ] The route for a test profession reaches 300 with only recipes the thresholds allow; a skill-up moves to the next step.

## M17.4 — Levelling page
- Branch: `step/m17-4-page`
- Spec: SPEC-21; ui-style §9
- Scope:
  - in the **Professions** tab, a **Levelling** page with the profession chooser, the route as a list of steps (skill range, recipe, how many crafts) and, for each step, its materials as **owned/needed** bars from the M13.4 counts (bags, bank, alts, mail; the guild bank apart);
  - prices from Auctionator when installed;
  - **Missing to the shopping list**.
- Done when:
  - [ ] Each step shows owned/needed that matches the counts of M13.4; the missing materials reach the shopping list.

## M17.5 — Tracker and "Create"
- Branch: `step/m17-5-tracker`
- Spec: SPEC-21
- Scope:
  - a small movable tracker, shown while a profession window is open: the current step, its materials as owned/needed, and how many crafts are possible now;
  - **Create**: direct crafting when the game allows it, else it selects the recipe in the profession window;
  - the tracker remembers its place.
- Done when:
  - [ ] The tracker moves to the next step at the next skill level; Create never errors when the game refuses (it falls back to selecting).

## M17.6 — Gathering and Forever skills
- Branch: `step/m17-6-gathering`
- Spec: SPEC-21
- Scope: the pages for Mining, Herbalism, Skinning and Fishing (level bands and where to go, from the tables of M17.2) and for Lockpicking, Camping and Merchant's Favor (their progression), with the player's skill level and the next band.
- Done when:
  - [ ] Each skill shows the band for the player's level and the next one; nothing points to a website.

## M17.7 — In-game check, `v0.17.0` and `v1.0.0`
- Branch: `step/m17-7-release`
- Scope:
  - `docs/checklists/M17.md`, and the switch `professions` turned on;
  - the full release check of `docs/checklists/release.md`, run again over everything;
  - the full test suite and CI back on (ADR 0012 point 9);
  - the wiki and both READMEs complete.
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.17.0`.
  - [ ] The full release check passes and the owner tags `v1.0.0`.
