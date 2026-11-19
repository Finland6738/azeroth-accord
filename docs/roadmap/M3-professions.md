# M3 — Professions and recipes

**Goal:** from a profession cell to the member's recipes; "who can craft"; craft requests.

**Exit criterion:** in game, the owner opens a guildmate's recipes from the roster and finds who can craft an item.

### M3.1 — Native recipe adapter
- Branch: `step/m3-1-native-recipes`
- Spec: SPEC-06 §1; ADR 0010
- Scope: `Data/Recipes.lua` native source (as decided by M0.4), with request pacing and cache.
- Done when:
  - [x] The native source sits behind the `guildRecipesNative` capability check and works against the mock directory with pacing, timeout and cache; with the source off or unreadable the shared lists are the only source (covered by `Tests/test_recipes.lua`). The choice between the sources is confirmed by the M0.4 results, which are not in yet.

### M3.2 — Own recipe scan and encoding
- Branch: `step/m3-2-recipe-scan`
- Spec: SPEC-06 §1, §3
- Scope: scan on `TRADE_SKILL_SHOW` / `TRADE_SKILL_LIST_UPDATE`, delta-varint encoding, hash, publishing rule PRO-06.
- Done when:
  - [x] The profession window is read, its learned recipes are encoded as delta varints in Base64 and published as one `recipes` record per profession, once every 10 minutes at most, only when the hash changes; the encoding round-trips and refuses malformed text (covered by `Tests/test_recipe_scan.lua`).

### M3.3 — Recipe sync
- Branch: `step/m3-3-recipe-sync`
- Scope: `recipes` data set in Store and Sync, on-demand requests when a view needs a member's list.
- Done when:
  - [x] Simulator: a recipe list reaches 20 clients within the traffic budget (`Tests/test_recipe_sync.lua`: 400 recipes reach 20 clients in under 10 s with about 1.3 KB in all; a late login stays inside the 8 KB login cost; an unchanged list adds no traffic).

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
