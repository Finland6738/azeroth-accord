# M8 — Officer tools and roster history

**Goal:** officers see what happened in the roster over time, which accounts are inactive (alts counted), and get a list of manual actions to do. Nothing is ever kicked or changed automatically. Release: `v0.8.0`.

**Exit criterion:** in game, an officer sees a member's joins, rank changes and level-ups on a timeline, and an inactive-accounts list that does not include a player who only plays an alt.

### M8.1 — Specification
- Branch: `step/m8-1-spec`
- Scope: write a new SPEC-12 ("Strumenti per ufficiali"), in Italian: timeline events, inactivity tiers, the cleanup wizard, the manual-ops queue, extended notes and exports. It also says who can see what, and where officer data goes when the officer channel (S5) is not proven.
- Done when:
  - [ ] SPEC-12 is linked from the spec index; `tools/check_docs.py` passes.

### M8.2 — Observed timeline
- Branch: `step/m8-2-timeline`
- Spec: SPEC-12
- Scope: the roster changes a client observes (join, leave, rank, level, public note), each with its date and observer. They are kept 365 days. Officers share them on `OFFICER` once S5 is proven; until then they stay local.
- Done when:
  - [ ] Two observers of the same change produce one event; a timeline is shown on the member card for officers.

### M8.3 — Inactivity tiers
- Branch: `step/m8-3-inactivity`
- Spec: SPEC-12
- Scope: inactivity per account, counted from the most recent of its characters. Tiers are configurable (default 14 / 30 / 60 / 90 days). Exceptions: a declared absence with a return date, set by the member or an officer.
- Done when:
  - [ ] A player active only on an alt is not inactive; a declared absence hides them until the return date.

### M8.4 — Cleanup wizard and manual-ops queue
- Branch: `step/m8-4-cleanup`
- Spec: SPEC-12
- Scope:
  - a non-destructive wizard: it proposes accounts to review by tier, and the officer chooses an action for each;
  - the chosen actions (promote, demote, remove, edit note) go into a queue to do by hand in the game window;
  - each queued action is ticked when the roster shows it done.
- Done when:
  - [ ] The addon never calls a protected roster action; a queued action is ticked by the roster change.

### M8.5 — Extended notes
- Branch: `step/m8-5-notes`
- Spec: SPEC-12
- Scope: longer officer notes per member. They are synced only on `OFFICER` once S5 is proven; until then they stay local.
- Done when:
  - [ ] Notes never travel on `GUILD` or `WHISPER` to a non-officer; a demoted officer loses them.

### M8.6 — Export
- Branch: `step/m8-6-export`
- Spec: SPEC-12
- Scope: the roster, inactive accounts and the timeline as CSV or as Discord-ready text, in a selectable box.
- Done when:
  - [ ] Each export round-trips through a CSV parser in the tests; no account token or GUID is in it.

### M8.7 — In-game check and release
- Branch: `step/m8-7-check`
- Scope: `docs/checklists/M8.md` and the README status. The owner releases `v0.8.0`.
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.8.0`.
