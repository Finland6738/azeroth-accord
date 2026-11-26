# M12 — Recruitment, trials and mentors

**Goal:** recruit for the roles the season roster is missing, follow trial members, welcome new members, and suggest mentors. Release: `v0.12.0`.

**Exit criterion:** in game:
- an officer copies a recruitment text built from the season gaps;
- a trial member shows in the Action Center when the trial ends;
- a new member sees a welcome checklist.

### M12.1 — Specification
- Branch: `step/m12-1-spec`
- Scope: write a new SPEC-16 ("Reclutamento, prove e mentori"), in Italian.
- Done when:
  - [x] SPEC-16 is linked from the spec index; `tools/check_docs.py` passes.

### M12.2 — Recruitment text
- Branch: `step/m12-2-recruitment`
- Spec: SPEC-16
- Scope: a recruitment text built from the season roster gaps (M10) and a short guild description from the handbook (M11). It is shown in a selectable box, for chat or Discord. The addon never posts it by itself.
- Done when:
  - [x] The text changes when the gaps change; nothing is sent to any channel.

### M12.3 — Trials
- Branch: `step/m12-3-trials`
- Spec: SPEC-16
- Scope:
  - officers mark a member as on trial, with a start date and a length;
  - officer-only feedback notes, under the same rules as M8.5;
  - a reminder in the Action Center when the trial ends.
- Done when:
  - [x] The reminder appears once, on the end date; the trial notes never reach a non-officer.

### M12.4 — Onboarding
- Branch: `step/m12-4-onboarding`
- Spec: SPEC-16
- Scope: a welcome checklist for new members:
  - read the handbook's guild info and rules;
  - choose a main;
  - add Discord;
  - declare for the season.
  Each item ticks itself when done.
- Done when:
  - [x] The checklist appears only for members who joined after the addon saw the roster; it can be dismissed.

### M12.5 — Mentors
- Branch: `step/m12-5-mentors`
- Spec: SPEC-16; SPEC-07
- Scope: an opt-in list of mentors. Suggested pairs come from co-play and the social graph, and are shown to officers only.
- Done when:
  - [x] Only opted-in members are suggested; a member can leave the list at any time.

### M12.6 — In-game check and release
- Branch: `step/m12-6-check`
- Scope: `docs/checklists/M12.md` and the README status. The owner releases `v0.12.0`.
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.12.0`.
