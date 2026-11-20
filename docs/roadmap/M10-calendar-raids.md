# M10 — Calendar, raids and the season roster

**Goal:**
- the guild's own season raid roster: every raider declares once per season what they play;
- event sign-ups, bench and composition;
- an availability map;
- PvP and world rallies.
Attendance tracking is optional and off by default. Release: `v0.10.0`.

**Exit criterion:** in game:
- three members declare MS1, MS2 and OS for the season, and an officer sees the role counts and the gaps;
- a member signs up to an event as tentative, and the officer sees it in the composition.

**Owner's model (2026-11-19):** the season roster is not a sign-up and not an attendance register. It says what each raider plays for the whole season:
- **MS1**, required: the main spec, with its role (tank, healer, melee dps or ranged dps);
- **MS2**, optional: a second spec accepted for the whole season, if the raid needs it;
- **OS**, optional: a spec the player would like to play, which the raid will not ask for;
- **a free note**, for example availability; "not sure yet" is a valid answer.

The declaration holds for the season and changes only when a new season opens, because loot follows the declared spec. Each member edits only their own entry. Declaring is optional.

### M10.1 — Specification
- Branch: `step/m10-1-spec`
- Scope: write a new SPEC-14 ("Calendario, raid e roster della season"), in Italian, from the owner's model above. It covers the `season` data set and its trust rules, events and sign-up states, bench and composition, the availability map, rallies, and optional attendance. It checks `C_Calendar` against the Forever dump and adds a capability for it.
- Done when:
  - [ ] SPEC-14 is linked from the spec index; open points go to SPEC-10; `tools/check_docs.py` passes.

### M10.2 — Seasons and declarations
- Branch: `step/m10-2-season`
- Spec: SPEC-14
- Scope:
  - officers open a season (name, start date);
  - each raider writes their own entry: MS1 with its role, MS2, OS and a note, or "not sure yet";
  - the entry is locked until the next season;
  - the data set is synced on `GUILD`, and only the author can write their entry.
- Done when:
  - [ ] An entry cannot change inside a season; a new season starts with empty entries and keeps the old season readable; a forged entry from another author is refused.

### M10.3 — Season roster for officers
- Branch: `step/m10-3-season-view`
- Spec: SPEC-14
- Scope:
  - officers see the tank, healer, melee and ranged counts by MS1, the cover MS2 would add, and the gaps against a target composition they set;
  - every member sees the declarations;
  - export as Discord-ready text.
- Done when:
  - [ ] The counts match the declarations; members without an entry are listed separately, not as a gap.

### M10.4 — Events and sign-ups
- Branch: `step/m10-4-events`
- Spec: SPEC-14
- Scope:
  - guild events, read from the game calendar when the client allows it, otherwise created in the addon;
  - sign-up states: accepted, tentative, declined and no response;
  - the role is preselected from MS1 or MS2.
- Done when:
  - [ ] Sign-ups converge on every client; a member without a season entry can still sign up.

### M10.5 — Bench and composition
- Branch: `step/m10-5-composition`
- Spec: SPEC-14
- Scope: officers place signed-up players in the raid or on the bench, and see the composition against the target. MS2 is offered when a role is short.
- Done when:
  - [ ] Only officers can change the composition; the members see where they are placed.

### M10.6 — Availability map and optional attendance
- Branch: `step/m10-6-availability`
- Spec: SPEC-14
- Scope:
  - when members usually play, from presence over time, shown by day and hour;
  - attendance counting is a guild setting, off by default, that officers can turn on.
- Done when:
  - [ ] With the setting off, nothing about attendance is recorded or sent.

### M10.7 — PvP and world rallies
- Branch: `step/m10-7-rallies`
- Spec: SPEC-14
- Scope: a quick call with a meeting point in text and a start time, answered with "coming" or "not coming". Exact positions are never shared.
- Done when:
  - [ ] A rally expires by itself; no coordinates are sent.

### M10.8 — In-game check and release
- Branch: `step/m10-8-check`
- Scope: `docs/checklists/M10.md` and the README status. The owner releases `v0.10.0`.
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.10.0`.
