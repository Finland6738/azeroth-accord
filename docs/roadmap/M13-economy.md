# M13 — Economy

**Goal:**
- craft orders with states;
- the materials the guild needs;
- wishlists;
- a buy and sell board with a double manual confirmation;
- guild goals.

The addon never moves gold or items. Release: `v0.13.0`.

**Exit criterion:** in game:
- a member orders a craft, the crafter accepts it, and both mark it delivered;
- a guild goal shows its progress from the bank logs.

### M13.1 — Specification
- Branch: `step/m13-1-spec`
- Scope: write a new SPEC-17 ("Economia di gilda"), in Italian. It covers order states, material demand, the WTS/WTB board, goals, and a later host-authoritative auction design.
- Done when:
  - [ ] SPEC-17 is linked from the spec index; `tools/check_docs.py` passes.

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

### M13.4 — Buy and sell board
- Branch: `step/m13-4-board`
- Spec: SPEC-17
- Scope:
  - WTS and WTB posts with an expiry;
  - a deal is closed only when both players confirm it by hand;
  - prices are text, and the addon does not trade.
- Done when:
  - [ ] A deal confirmed by one side only stays open; posts expire by themselves.

### M13.5 — Guild goals
- Branch: `step/m13-5-goals`
- Spec: SPEC-17; SPEC-08
- Scope: officers set collective targets, in materials or gold. Progress is read from the bank logs of M5.
- Done when:
  - [ ] Progress matches the logs; a goal closes when reached or at its end date.

### M13.6 — Auctions (later, optional)
- Branch: `step/m13-6-auctions`
- Spec: SPEC-17
- Scope: guild auctions run by one officer's client, which acts as the host and has the final word. Do this step only if the owner asks for it after M13.5.
- Done when:
  - [ ] The owner has decided whether to do it (SPEC-10).

### M13.7 — In-game check and release
- Branch: `step/m13-7-check`
- Scope: `docs/checklists/M13.md` and the README status. The owner releases `v0.13.0`.
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.13.0`.
