# M13 — Economy

**Goal:**
- craft orders with states;
- the materials the guild needs;
- a personal **shopping list**: the materials of the recipes a player picks, against what they own (owner, 2026-11-27);
- wishlists;
- a buy and sell board with a double manual confirmation;
- guild goals.

The addon never moves gold or items. Release: `v0.13.0`.

**Exit criterion:** in game:
- a member orders a craft, the crafter accepts it, and both mark it delivered;
- a guild goal shows its progress from the bank logs.

### M13.1 — Specification
- Branch: `step/m13-1-spec`
- Scope: write a new SPEC-17 ("Economia di gilda"), in Italian. It covers order states, material demand, the shopping list (with the inventory counts M17 reuses), the WTS/WTB board, goals, and a later host-authoritative auction design.
- Done when:
  - [x] SPEC-17 is linked from the spec index; `tools/check_docs.py` passes.

### M13.2 — Craft orders
- Branch: `step/m13-2-orders`
- Spec: SPEC-17; SPEC-06
- Scope: the craft requests of M3 become orders with states: requested, accepted, in progress, ready, delivered and cancelled. An order is created from "who can craft".
- Done when:
  - [x] Only the buyer and the crafter change an order; old M3 requests are migrated.

### M13.3 — Material demand and wishlist
- Branch: `step/m13-3-materials`
- Spec: SPEC-17
- Scope:
  - the materials needed by open orders and goals, summed;
  - a personal wishlist of items, visible to the guild.
- Done when:
  - [x] The demand updates when an order closes; a wishlist entry expires.

### M13.4 — Shopping list
- Branch: `step/m13-4-shopping`
- Spec: SPEC-17; SPEC-06
- Scope (owner's decisions, 2026-11-27):
  - the player picks recipes from the profession's whole list (the recipe catalogue) and how many of each; Accord sums their materials, read from the game (`C_TradeSkillUI.GetRecipeSchematic`);
  - an on/off switch breaks **intermediate materials** down into raw ones (a bolt of cloth into cloth);
  - every material shows **owned/needed** with a bar and what is missing, owned being the sum of: the bags, the bank, the player's **alts** (Accord keeps each character's bags and bank at logout, on this computer only), and the **mail** (read when the mailbox opens, if the game gives it reliably); the **guild bank** has a column of its own (Accord's snapshot, M5);
  - **prices** from Auctionator when it is installed, read-only through its public API like FDCP (ADR 0022), never required;
  - **Ask the guild** publishes the missing materials as the player's wishlist (M13.3); **Ask the bank** prefills a guild-bank request (M5, M8.7) with the missing materials only;
  - the list is private until one of those buttons; it updates while the player loots and buys.
- Done when:
  - [x] Owned/needed is right for the bags, the bank and an alt; the breakdown switch changes the totals; the bank request holds only what is missing.

### M13.5 — Buy and sell board
- Branch: `step/m13-5-board`
- Spec: SPEC-17
- Scope:
  - WTS and WTB posts with an expiry;
  - a deal is closed only when both players confirm it by hand;
  - prices are text, and the addon does not trade.
- Done when:
  - [x] A deal confirmed by one side only stays open; posts expire by themselves.

### M13.6 — Interface: Material Symbols icons
- Branch: `step/m13-6-icons`
- Spec: [ui-style §9.10](../specs/ui-style.md#910-icone-material-symbols-proprietario-2026-11-27)
- Scope (owner, 2026-11-27): every icon of the addon's own interface comes from Google's **Material Symbols Rounded** (Apache 2.0), outlined, and filled for the active state:
  - a tool in `tools/` builds one atlas with only the icons used, from the official font or SVGs, with the licence in `docs/third-party.md` and the credits;
  - `UI/Assets.lua` maps names to cells;
  - the old custom icon sheet goes;
  - the game's own icons (classes, items) stay.
- Done when:
  - [x] No icon of the addon's interface comes from the old sheet; `tools/check_addon.py` checks the atlas and its licence entry.

### M13.7 — Interface: navigation rail and two levels
- Branch: `step/m13-7-navigation`
- Spec: [ui-style §9.11](../specs/ui-style.md#911-navigazione-due-livelli-proprietario-2026-11-27)
- Scope (owner, 2026-11-27):
  - the views move from the top tab bar to a vertical **navigation rail** on the left: icons only, the name in a tooltip on hover, the active one filled with the indicator;
  - the 15 views are grouped into the **8 destinations** of the map in ui-style §9.11 (Home, Guild, Raid, Groups, Professions, Economy, Community, Officers) plus Settings, each with its pages (owner, 2026-11-27);
  - inside a view, **one** row of tabs for its pages, the same in every view, with the view's name at its start;
  - no third navigation row: what was a sub-category becomes filter chips or a "Category" menu;
  - the guild window's panel and the Accord window both use it; More disappears.
- Done when:
  - [x] No view shows more than one row of tabs; every rail icon has its tooltip; the active view and page are visible at a glance.

### M13.8 — Interface: sortable tables everywhere
- Branch: `step/m13-8-tables`
- Spec: [ui-style §9.9](../specs/ui-style.md#99-tabelle-sempre-ordinabili-proprietario-2026-11-27)
- Scope (owner, 2026-11-27):
  - every list with columns uses `Widgets.DataTable` with a header whose click sorts ascending, then descending, with the arrow;
  - the hand-made lists (Bank, Bank log and requests, Events, Rallies, Mentors, Demand, Board, Raid, Season and the others) are migrated;
  - card lists without columns get a "Sort by" menu with the same behaviour;
  - with it (owner, 2026-11-27): the roster mark before a name becomes the role icon in the class colour.
- Done when:
  - [x] Every column header of every table sorts both ways; no hand-made columnar list is left.

### M13.9 — Guild goals
- Branch: `step/m13-9-goals`
- Spec: SPEC-17; SPEC-08
- Scope: officers set collective targets, in materials or gold. Progress is read from the bank logs of M5.
- Done when:
  - [x] Progress matches the logs; a goal closes when reached or at its end date.

### M13.10 — Auctions (later, optional)
- Branch: `step/m13-10-auctions`
- Spec: SPEC-17
- Scope: guild auctions run by one officer's client, which acts as the host and has the final word. Do this step only if the owner asks for it after M13.9.
- Done when:
  - [ ] The owner has decided whether to do it (SPEC-10).

### M13.11 — In-game check and release
- Branch: `step/m13-11-check`
- Scope: `docs/checklists/M13.md` and the README status. The owner releases `v0.13.0`.
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.13.0`.
