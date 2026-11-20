# M9 — Action Center and notifications

**Goal:** one place for everything that waits on the player, one history of notices, quiet hours, and a short digest at login. Release: `v0.9.0`.

**Exit criterion:** in game, a craft request and a bank request both appear in the Action Center. Nothing pops up during quiet hours or combat, and the login digest lists what changed since the last session.

### M9.1 — Specification
- Branch: `step/m9-1-spec`
- Scope: write a new SPEC-13 ("Centro azioni e avvisi"), in Italian. It defines the provider interface modules register with, the notice levels, quiet hours and the digest.
- Done when:
  - [ ] SPEC-13 is linked from the spec index; `tools/check_docs.py` passes.

### M9.2 — Action Center
- Branch: `step/m9-2-action-center`
- Spec: SPEC-13
- Scope: an inbox of pending items. Modules register a provider: craft requests, bank requests and the officers' inbox now; sign-ups, trials and polls later. Each item opens its own view.
- Done when:
  - [ ] Items from three providers show in one list, sorted by urgency and date; resolving one in its view removes it.

### M9.3 — Notification centre
- Branch: `step/m9-3-notifications`
- Spec: SPEC-13
- Scope: a history of notices with read and unread, a switch per module, and a choice of chat line, toast or sound. It replaces the bank notices of M5 without changing their defaults.
- Done when:
  - [ ] The M5 options still work; a muted module produces no notice but still adds to the history.

### M9.4 — Quiet hours
- Branch: `step/m9-4-quiet`
- Spec: SPEC-13
- Scope: quiet hours set by the player; notices are held during combat and in instances, and released after.
- Done when:
  - [ ] Held notices come out once, in order, after combat or the quiet hours.

### M9.5 — Login digest
- Branch: `step/m9-5-digest`
- Spec: SPEC-13
- Scope: a short summary a few seconds after login: new and departed members, pending items, likes received (the number only), bank changes. Each line links to its view.
- Done when:
  - [ ] The digest is empty and silent when nothing changed; it never names who gave a like.

### M9.6 — In-game check and release
- Branch: `step/m9-6-check`
- Scope: `docs/checklists/M9.md` and the README status. The owner releases `v0.9.0`.
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.9.0`.
