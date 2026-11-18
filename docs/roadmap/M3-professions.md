# M3 — Professions and recipes

**Goal:** from a profession cell to the member's recipes; "who can craft"; craft requests.

**Exit criterion:** in game, the owner opens a guildmate's recipes from the roster and finds who can craft an item.

### M3.1 — Native recipe adapter
- Branch: `step/m3-1-native-recipes`
- Spec: SPEC-06 §1; ADR 0010
- Scope: `Data/Recipes.lua` native source (as decided by M0.4), with request pacing and cache.

### M3.2 — Own recipe scan and encoding
- Branch: `step/m3-2-recipe-scan`
- Spec: SPEC-06 §1, §3
- Scope: scan on `TRADE_SKILL_SHOW` / `TRADE_SKILL_LIST_UPDATE`, delta-varint encoding, hash, publishing rule PRO-06.

### M3.3 — Recipe sync
- Branch: `step/m3-3-recipe-sync`
- Scope: `recipes` data set in Store and Sync, on-demand requests when a view needs a member's list.
- Done when:
  - [ ] Simulator: a recipe list reaches 20 clients within the traffic budget.

### M3.4 — Recipe view from the roster
- Branch: `step/m3-4-recipe-view`
- Spec: PRO-01–PRO-03
- Scope: clickable profession cells, recipe list with icons, tooltips, search, category filters, source and age.

### M3.5 — "Who can craft"
- Branch: `step/m3-5-who-can-craft`
- Spec: PRO-04
- Scope: the Professions view: reverse index from item or recipe name to members, online first, grouped by account.

### M3.6 — Craft request and v0.3.0
- Branch: `step/m3-6-craft-request`
- Spec: PRO-05
- Scope: prefilled whisper with the recipe link; `docs/checklists/M3.md`; wiki "Professions and Recipes"; tag `v0.3.0`.
