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
  - [ ] Only the buyer and the crafter change an order; old M3 requests are migrated.

### M13.3 — Material demand and wishlist
- Branch: `step/m13-3-materials`
- Spec: SPEC-17
- Scope:
  - the materials needed by open orders and goals, summed;
  - a personal wishlist of items, visible to the guild.
- Done when:
  - [ ] The demand updates when an order closes; a wishlist entry expires.

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
  - [ ] Owned/needed is right for the bags, the bank and an alt; the breakdown switch changes the totals; the bank request holds only what is missing.

### M13.5 — Buy and sell board
- Branch: `step/m13-5-board`
- Spec: SPEC-17
- Scope:
  - WTS and WTB posts with an expiry;
  - a deal is closed only when both players confirm it by hand;
  - prices are text, and the addon does not trade.
- Done when:
  - [ ] A deal confirmed by one side only stays open; posts expire by themselves.

### M13.6 — Guild goals
- Branch: `step/m13-6-goals`
- Spec: SPEC-17; SPEC-08
- Scope: officers set collective targets, in materials or gold. Progress is read from the bank logs of M5.
- Done when:
  - [ ] Progress matches the logs; a goal closes when reached or at its end date.

### M13.7 — Auctions (later, optional)
- Branch: `step/m13-7-auctions`
- Spec: SPEC-17
- Scope: guild auctions run by one officer's client, which acts as the host and has the final word. Do this step only if the owner asks for it after M13.6.
- Done when:
  - [ ] The owner has decided whether to do it (SPEC-10).

### M13.8 — In-game check and release
- Branch: `step/m13-8-check`
- Scope: `docs/checklists/M13.md` and the README status. The owner releases `v0.13.0`.
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.13.0`.
