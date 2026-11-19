# M2 — Extended roster, alts and contacts

**Goal:** the Roster view with professions, alts grouped by account, the member card and contacts; co-play recording starts silently (D6).

**Exit criterion:** in game, clicking a member shows all characters of their account and their contacts (owner and a second player with the addon).

### M2.1 — Roster model
- Branch: `step/m2-1-roster-model`
- Spec: SPEC-05 §1
- Scope: `Data/Roster.lua` merging `GetGuildRosterInfo`, `GetGuildRosterLastOnline` and `C_Club.GetMemberInfo` (professions natively when available), refresh throttling.
- Done when:
  - [x] Roster of 1000 members builds in the mock within the budget.

### M2.2 — Account token and characters
- Branch: `step/m2-2-accounts`
- Spec: SPEC-05 §3; ADR 0006
- Scope: `Data/Accounts.lua`: token, character list per realm, main, sharing (always on), merge, note hints `alt:` / `main:`, stale characters.
- Done when:
  - [x] Alts of two simulated accounts are grouped on a third client; a forged list is refused.

### M2.3 — Roster table
- Branch: `step/m2-3-roster-table`
- Spec: SPEC-05 §1; SPEC-04 §2
- Scope: `UI/RosterModel.lua`, `UI/Roster.lua`: virtual rows, sort, search, filters, column chooser, grouped-by-account view.
- Done when:
  - [x] Sorting and filters are covered by model tests.

### M2.4 — Member card
- Branch: `step/m2-4-member-card`
- Spec: SPEC-05 §2
- Scope: card with details, notes (respecting `CanViewOfficerNote`), professions, the account's characters.
- Done when:
  - [x] The card shows details, professions with their source, the officers' note only when allowed, and all the characters of the account (covered by `Tests/test_member_card.lua`).

### M2.5 — Contacts
- Branch: `step/m2-5-contacts`
- Spec: SPEC-05 §4
- Scope: `Data/Contacts.lua` (BattleTag, Discord native or typed), copy box, Add BattleTag friend button, Discord field in the settings.
- Done when:
  - [x] BattleTag and Discord are published (always) and shown on the card; a click copies, the friend button calls the club API, the Discord field validates (covered by `Tests/test_contacts.lua`).

### M2.6 — Co-play recording
- Branch: `step/m2-6-coplay`
- Spec: SPEC-07 §3.1; ADR 0008
- Scope: `Data/CoPlay.lua`: one-minute sampling, pairs per day, hourly publishing, max merge, 90-day retention; no view yet (only `/accord debug` counts).
- Done when:
  - [x] Two observers of the same group give the maximum, not the sum.

### M2.7 — M2 in-game check and v0.2.0
- Branch: `step/m2-7-check`
- Scope: `docs/checklists/M2.md`, wiki "Guild Roster", tag `v0.2.0`.
