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

### M12.6 — Material 3: the base
- Branch: `step/m12-6-m3-base`
- Spec: [ui-style §9](../specs/ui-style.md#9-le-regole-di-material-3-adr-0027); [ADR 0027](../adr/0027-material-3-rules-adapted-to-accord.md)
- Scope:
  - the new colour roles in `UI/Theme.lua` for the three themes: `secondary-container`, `on-secondary-container`, `inverse-surface`, `inverse-on-surface` and `on-error`, with their contrast tests;
  - state layers in the content's colour (hover 8 %, focus and pressed 10 %, dragged 16 %, disabled 38 % / 12 %) in place of the white layers;
  - the shape slices 4, 16 and 28 (`tools/make_media.py`) and the radius of each component;
  - the type roles of ui-style §9.4.
- Done when:
  - [x] Every theme passes the contrast rules for the new roles; a hovered button on Aurora shows a darker, not a whiter, layer.

### M12.7 — Material 3: the components
- Branch: `step/m12-7-m3-components`
- Spec: ui-style §9.6
- Scope: `UI/Widgets/` as ui-style §9.6 says:
  - tabs (48 points, a 3-point rounded indicator, no glow and no fill);
  - buttons (filled, tonal, outlined, text) and icon buttons;
  - filter chips with a check mark, and segmented buttons;
  - menus, text fields, cards, the table, the member card as a side sheet, dialogs, plain and rich tooltips, badges, the switch and the snackbar.
- Done when:
  - [x] The widget tests check each component's measurements, roles and states as in ui-style §9.6.

### M12.8 — Material 3: the views
- Branch: `step/m12-8-m3-views`
- Spec: ui-style §9
- Scope:
  - every view uses the right component: one filled button per view, filters as chips, the selected row in `secondary-container`;
  - the design previews (ui-style §8), README images and the wiki pages (EN and IT) are redrawn.
- Done when:
  - [x] No view uses a token or a size outside ui-style §9; the previews show the new look.

### M12.9 — In-game check and release
- Branch: `step/m12-9-check`
- Scope: `docs/checklists/M12.md` and the README status. The owner releases `v0.12.0`.
- Done when:
  - [x] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.12.0`.
  - *Released (2026-11-27):* `v0.12.0` was tagged before the in-game checks, while the owner was away, under their standing approval for milestone tags (ADR 0020 update of 2026-11-25), and without waiting for the full tests and CI (ADR 0012 point 9). This box stays open until the checks pass.
  - *Done in code (2026-11-27):* [the M12 checklist](../checklists/M12.md); the switch `recruit` is on in `Core/Features.lua`; README and wiki describe M12 as part of the next release. The release preparation of the changelog and the tag are a separate step. Nothing of M12 has been checked in the real game.
