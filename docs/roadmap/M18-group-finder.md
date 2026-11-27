# M18 — Guild group finder, like the game's

**Goal:** the guild group finder of M9 becomes as simple and familiar as the game's own Group Finder, for guild members only.
- On the **left half**, the active groups. Each row shows where the group goes, its role slots filled or empty, the leader, its age and **Join**.
- On the **right half**, the selected group slot by slot, or the three-step **Create group** form.
- Every role has a count, a required level range and recommended classes.

The owner asked for it on 2026-11-27 and answered the design questions the same day (below). It builds on M9: the `groups` set, applications (GAPP) and the late ask (GASK) of `Data/Groups.lua`, the instances of `Data/GroupActivities.lua`, and the private listing in the game's finder of M9.8. After M18 comes the release of `v1.0.0` ([ADR 0020](../adr/0020-one-version-per-milestone.md), update of 2026-11-27).

**Switched off until complete.** The new finder ships behind a new switch `groupfinder` in `AzerothAccord/Core/Features.lua`; the M9 finder stays as it is until the last step turns the new one on.

**Exit criterion:** in game:
- a leader creates a dungeon group needing a tank of level 20–25 (warrior or druid recommended) and a healer;
- a level-22 druid sees it under "Suits me", joins as tank and is accepted and invited on the leader's click;
- a level-15 player sees Join switched off;
- a member still on an older Accord sees the group as a simple listing.

## Owner's decisions (2026-11-27)

1. **Layout.**
   - The active groups list is on the **left half**.
   - The **right half** shows the selected group, or the three-step create form.
2. **Categories.**
   - The filter chips on top are **Dungeon**, **Raid**, **Other** and **Suits me**.
   - Step 1 of the form keeps the detailed kinds (quest, elite, PvP, farm, professions, help, other) in its menu, grouped under Other.
3. **Per-role requirements:** a count, a **level range** and **recommended classes**. No specializations: a spec ("feral druid") goes in the leader's note.
4. **The level is required:** outside the role's range, Join is switched off. **Classes are only recommended:** anyone may apply, marked "not recommended".
5. **Join** stays as in M9: the member applies with a role, the leader accepts, and the invite goes out on the leader's click. No auto-accept.
6. **Sizes:** dungeons of 5, and raids of free size (10, 20, 40) with several tanks and healers. The right column groups the slots by role, so a raid stays readable.
7. **Notices:** on by default in M18, only when a **new** group fits the player's level and role, not on each change, with a quick way to mute them.
8. **Compatibility:** clients on an older Accord get and show a **simplified listing**, without the per-role requirements, so nobody is cut out.

The look follows the Material 3 rules of [ui-style §9](../specs/ui-style.md#9-le-regole-di-material-3-adr-0027): filter chips, a dense list, role slots as icons, the detail as a side sheet, the form as a stepped panel.

## M18.1 — Specification
- Branch: `step/m18-1-spec`
- Scope: write a new SPEC-22 ("Cercagruppi di gilda"), in Italian. It covers:
  - the listing record extended with role slots: count, min and max level, recommended classes;
  - how an older client still gets a valid M9 listing (the per-role data beside the old fields, or a parallel record), and the size limit;
  - the trust rules (only the leader writes; an application checked against the role's range by the leader too);
  - the views: list, detail, form, Join with a role choice, and the leader's applicants;
  - the notices and their mute;
  - what the game allows on Forever (the invite on the leader's click; the private listing of M9.8);
  - the traffic in the budget of SPEC-09 §7;
  - new SPEC-10 questions for what is still open, each with a proposed answer.
- Done when:
  - [ ] SPEC-22 is linked from the spec index; `tools/check_docs.py` passes.

## M18.2 — Role slots in the data
- Branch: `step/m18-2-slots`
- Spec: SPEC-22
- Scope:
  - the listing's role slots (count, level range, recommended classes) and the members in each slot, from the group the leader's client sees;
  - the simplified M9 listing for older clients;
  - the checks on an application: the role's level range, a free slot, "not recommended" for another class.
- Done when:
  - [ ] An application outside the role's range is refused on the leader's client too; an older client's tests still see the listing.

## M18.3 — Group list
- Branch: `step/m18-3-list`
- Spec: SPEC-22; ui-style §9
- Scope:
  - the left half: one dense row per active group, with the instance and band, role slots as filled or empty icons, the leader, the age and Join;
  - the filter chips Dungeon, Raid, Other and Suits me;
  - Join is switched off outside the role's level range.
- Done when:
  - [ ] "Suits me" shows only groups with a free slot for the player's role and level.

## M18.4 — Group detail
- Branch: `step/m18-4-detail`
- Spec: SPEC-22; ui-style §9
- Scope:
  - the right half for the selected group:
    - slots grouped by role, each with its member (class, level) or what is wanted (level range, recommended classes);
    - the note and the meeting point;
    - Join with a role choice;
  - for the leader: the applicants, with Accept and Decline (the invite on the leader's click, M9) and the "not recommended" mark;
  - raids of 10, 20 or 40 stay readable.
- Done when:
  - [ ] An accepted member appears in their slot; the leader's Accept invites only on the leader's click.

## M18.5 — Create group
- Branch: `step/m18-5-create`
- Spec: SPEC-22; ui-style §9
- Scope: the three-step form in the right half:
  1. **what**: the category and the instance from a menu, with its level band filled in; Other opens the detailed kinds;
  2. **who**: for each role, the count, the level range and the recommended classes as class chips;
  3. **details**: the note ("what you look for"), the meeting point, the duration, and "also list in the game's finder (private)" (M9.8).
- Done when:
  - [ ] A dungeon group and a 20-player raid can be created; the form refuses a level range outside the instance's band without saying why.

## M18.6 — Notices
- Branch: `step/m18-6-notices`
- Spec: SPEC-22; SPEC-13
- Scope:
  - the "new group for you" notice is on by default;
  - it fires only when a new group fits the player's level and role;
  - it can be muted from the notice itself and from Settings.
- Done when:
  - [ ] A change to an existing group sends no notice; muting stops the next ones.

## M18.7 — In-game check, `v0.18.0` and `v1.0.0`
- Branch: `step/m18-7-release`
- Scope:
  - `docs/checklists/M18.md`, and the switch `groupfinder` turned on (the M9 view gives way to the new one);
  - the full release check of `docs/checklists/release.md`, run again over everything;
  - the full test suite and CI back on (ADR 0012 point 9);
  - the wiki and both READMEs complete.
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.18.0`.
  - [ ] The full release check passes and the owner tags `v1.0.0`.
