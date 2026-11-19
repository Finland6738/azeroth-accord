# M5 — Guild bank

**Goal:** see the bank from the guild window, with logs, donations and an officer-approved request flow.

**Exit criterion:** in game, a member who never visits the vault sees the bank contents captured by another member, creates a withdrawal request, and an officer approves and fulfils it.

### M5.1 — Snapshot capture
- Branch: `step/m5-1-bank-capture`
- Spec: BANK-01; ADR 0009
- Scope: `Data/Bank.lua`: paced tab queries at `GUILDBANKFRAME_OPENED`, money, tab permissions.
- Done when:
  - [x] The open vault is read one tab at a time with a pause; only viewable tabs; money; an unchanged tab is not sent again for 30 minutes; a tab that never loaded is not published as empty; the snapshot of an officer is restricted (covered by `Tests/test_bank_capture.lua`). Unverified in game: the S9 behaviour listed in `docs/checklists/M5.md` (M5.7).

### M5.2 — Snapshot sync with permissions
- Branch: `step/m5-2-bank-sync`
- Spec: BANK-02, BANK-03
- Scope: newest per tab, `GUILD` / `OFFICER` / not shared by permission, authority for restricted tabs.
- Done when:
  - [x] A member's snapshot reaches every client and the newest per tab wins; a snapshot read by an officer goes on `OFFICER` only and no member holds it; a later officer receives it with `OHELLO`; with no addon messages on `OFFICER` it stays with its reader; forged restricted or foreign-id snapshots are refused; a rank sees only snapshots read by its own rank or above (`Tests/test_bank_sync.lua`, with the network simulator).

### M5.3 — Bank view
- Branch: `step/m5-3-bank-view`
- Spec: BANK-04
- Scope: tab grid and list view, search, totals per item, age of each tab.
- Done when:
  - [x] The Tabs mode draws a tab as 14 x 7 slots with icons, counts and tooltips, the money and the age of the tab with who read it; the Items mode lists each item once with its total and the tabs it is in, searchable by name, number and tab name; a rank sees only the tabs it may see; item names that load late fill in (`Tests/test_bank_view.lua`).

### M5.4 — Logs and donations
- Branch: `step/m5-4-logs-donations`
- Spec: BANK-10–BANK-12
- Scope: log merging without duplicates, donations per account (30 days, 365 days, all time), money over time.
- Done when:
  - [x] Logs read at the vault are merged over visits and guildmates without duplicates (also with the shifted hours of the game's log), identical events in one capture stay two; donations are counted per account over the three periods, only deposits; the money keeps a history; every client of the simulator shows the same merged list (`Tests/test_bank_log.lua`). Unverified in game: the log time format and the money-log query number (S9).

### M5.5 — Requests
- Branch: `step/m5-5-bank-requests`
- Spec: BANK-20–BANK-22; SPEC-03 §7
- Scope: `Data/BankRequests.lua` and the Requests view: create, cancel, officer status changes with history.
- Done when:
  - [x] Tests: status changes only from officers (a member's forged decision or a cancel in somebody else's name is refused by officers and members); simulator convergence (a request reaches everyone, approval and fulfilment converge, a decision racing a cancel ends the same on every client, a late login is served by an officer, an alt may cancel); the Requests mode (`Tests/test_bank_requests.lua`, `Tests/test_store.lua`).

### M5.6 — Officer inbox and notifications
- Branch: `step/m5-6-bank-inbox`
- Spec: BANK-23, BANK-24
- Scope: counter on the tab, officer inbox, requester notification, "mark as fulfilled" proposal from logs.

### M5.7 — M5 in-game check and v0.9.0 beta
- Branch: `step/m5-7-check`
- Scope: `docs/checklists/M5.md`, wiki "Guild Bank", tag `v0.9.0` (beta for the owner's guild).
