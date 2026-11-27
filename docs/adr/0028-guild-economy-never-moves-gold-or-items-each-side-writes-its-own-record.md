# 0028. Guild economy: Accord never moves gold or items, each side writes its own record, owned counts stay local

- Status: Accepted
- Date: 2026-11-27 ([M13.1](../roadmap/M13-economy.md), [SPEC-17](../specs/SPEC-17-guild-economy.md))

## Context

M13 adds a guild economy: craft orders with states (from the craft requests of M3), the materials the guild needs, a personal shopping list that compares the materials of chosen recipes with what the player owns, wishlists, a buy and sell board, and guild goals read from the bank logs. The owner decided the shopping list on 2026-11-27: owned counts from the bags, the bank, the player's alts and the mail, the guild bank in a column of its own, prices from Auctionator when it is installed, and two buttons that ask the guild or the guild bank for what is missing. M17 (the professions assistant) reuses the same counts. Three things need a lasting decision:

- **Money and items.** An order, a deal or a goal is about gold and items changing hands. An addon that moved them (trade, mail, auction or the game's own crafting orders) would act for the player, could lose their property to a bug or a forged message, and would turn Accord into a market engine.
- **Two people, one agreement.** An order has a buyer and a crafter; a deal has two traders. With the per-author sync (ADR 0005), one record written by both would have two writers of one `rev`, and one side could overwrite the other's word.
- **What a player owns.** The counts of every character's bags, bank and mail are private, and alts may be in another guild or none.

## Decision

1. **Accord never moves gold or items.** No module of M13 calls a function that trades, mails, buys, sells, bids, deposits or withdraws, nor the game's crafting orders (`C_CraftingOrders`). Orders, deals and goals record what players do by hand in the game; prices are text the player writes, never an amount Accord collects. Tests replace those functions with failing stubs.
2. **Each side writes its own record.** An order is two records: the buyer's (`O:<buyer>:<n>`, the content and the buyer's state) and the crafter's (`A:<buyer>:<n>`, the crafter's state). A deal on the board is the poster's post and the other trader's answer. The visible state is derived from both by every client in the same way. Nobody, officers included, writes the other side's record.
3. **Closed only by both.** An order is delivered, and a deal is closed, only when both sides have confirmed by hand. A confirmation from one side leaves it open and says who is missing.
4. **Owned counts stay on this computer.** Bags, bank and mail are read per character of the account and kept in the account's saved variables, outside any guild; they never travel and are not in the personal backup. The shopping list is private; *Ask the guild* publishes only the missing materials as the player's wishlist, and *Ask the bank* prefills an existing guild-bank request with a missing material. The counting module is the one interface M17 uses.
5. **Materials come from the game.** A recipe's reagents are read with `C_TradeSkillUI.GetRecipeSchematic` and cached per account; they are not shared and never guessed.
6. **Prices read-only from Auctionator.** The rules of ADR 0022 (read-only, a documented and versioned public API, levels 0 and 1, never a dependency, never its saved variables) also cover one price addon, Auctionator, through `Auctionator.API.v1`. Prices are read when shown, never stored and never sent. This widens point 4 of ADR 0022, which named only loot and raid-roster addons.
7. **Goals are computed, not written.** Officers write a goal (an item or gold, a target, a start and an end); its progress is the sum of the deposits in the merged bank logs, so two clients with the same logs show the same number, and a goal closes when reached or at its end date without a write.
8. **One new summary kind.** The four new data sets (`orders`, `wish`, `board`, `goals`) are unknown to every released client, so they share a summary kind of their own (`ec`, `ecb`), sent only while the switch `econ` is on (SPEC-02 §4).
9. **Auctions only if the owner asks.** A guild auction run by one officer's client as the host is described in SPEC-17 §9, not planned.

## Alternatives considered

- **Use the game's crafting orders.** They move gold and reagents through the game, may not run on WoW Forever, and would reach players outside the guild.
- **One record per order written by both sides.** Two writers of one record: a crafter's "ready" and a buyer's "cancel" written together would race, and a forged client could change the other side's word.
- **Share owned counts with the guild** (so others see who has what). It would publish every alt's bags; the wishlist and the board say what a player wants to share.
- **Ship a reagent database with the addon.** Data copied from outside, out of date at every patch; the game gives the reagents itself.
- **Read prices from Auctionator's saved variables.** No contract, as ADR 0022 says for FDCP.
- **Progress written by an officer.** One more writer per goal and a number that differs from the logs a member sees.

## Consequences

- Positive: no property is ever at stake in Accord's code; nobody can change another player's side of an order or a deal; owned counts are private; one counting module serves M13 and M17.
- Negative: two records per order or deal (a little more traffic); a member who sees fewer bank tabs sees a lower goal progress; owned counts are only as fresh as each character's last visit to the bank and the mailbox from this computer; nothing is verified in the real client: the fields of the reagent schematic, the bank bag indices, the mailbox functions and Auctionator on WoW Forever ([SPEC-10](../specs/SPEC-10-risks-open-questions.md) R21–R24).
