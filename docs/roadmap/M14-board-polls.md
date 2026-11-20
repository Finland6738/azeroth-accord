# M14 — Board, MOTD history, polls and kudos

**Goal:**
- a board of announcements;
- the history of the guild message;
- polls with one vote per account;
- a short reason that can go with a like.

Release: `v0.14.0`.

**Exit criterion:** in game:
- an officer opens a poll;
- two characters of the same account can vote only once;
- every client shows the same totals.

### M14.1 — Specification
- Branch: `step/m14-1-spec`
- Scope: write a new SPEC-18 ("Bacheca, sondaggi e riconoscimenti"), in Italian.
- Done when:
  - [ ] SPEC-18 is linked from the spec index; `tools/check_docs.py` passes.

### M14.2 — Board
- Branch: `step/m14-2-board`
- Spec: SPEC-18
- Scope: announcements that officers write, pin and give an expiry. Members read them and see new ones marked.
- Done when:
  - [ ] Only writers chosen by the guild can post; expired posts disappear.

### M14.3 — MOTD history
- Branch: `step/m14-3-motd`
- Spec: SPEC-18
- Scope: every change of the guild message seen by a client, with its date. The history is shared, so a member who was offline sees the old messages too.
- Done when:
  - [ ] Two clients that saw the same change keep one entry.

### M14.4 — Polls
- Branch: `step/m14-4-polls`
- Spec: SPEC-18; SPEC-07
- Scope:
  - officer polls with a closing time;
  - one vote per account, through the likes notary;
  - only the totals are shown.
- Done when:
  - [ ] A second vote from an alt is refused; the totals match on every client; nobody sees who voted for what.

### M14.5 — Kudos with a reason
- Branch: `step/m14-5-kudos`
- Spec: SPEC-18; SPEC-07
- Scope: an optional short text sent with a like. It travels in a whisper to the target and is kept only by them. The like itself stays anonymous.
- Done when:
  - [ ] The reason never travels on `GUILD`; the target sees it without the sender's name unless the sender chooses to sign it.

### M14.6 — In-game check and release
- Branch: `step/m14-6-check`
- Scope: `docs/checklists/M14.md` and the README status. The owner releases `v0.14.0`.
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.14.0`.
