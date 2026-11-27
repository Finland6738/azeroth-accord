# M15 — Community and fun

**Goal:** opt-in community features:
- rare sightings;
- the guild's legacy;
- bingo and bounties;
- quizzes;
- Secret Santa.

Help requests, first planned here, are a listing type of the guild group finder in M9.6 (2026-11-24). No gambling and no gold stakes. Each feature can be switched off by the guild and by the player. After M15 comes [M16](M16-quests.md), the guild quests the owner added on 2026-11-26, and then `v1.0.0`.

**Exit criterion:** in game, a rare sighting reaches only members who opted in, and a weekly bingo card ticks itself from game events.

### M15.1 — Specification
- Branch: `step/m15-1-spec`
- Scope: write a new SPEC-19 ("Comunità"), in Italian. It says, for each feature, what it sends, who receives it, and its switch.
- Done when:
  - [ ] SPEC-19 is linked from the spec index; `tools/check_docs.py` passes.

### M15.2 — Rare sightings
- Branch: `step/m15-2-rares`
- Spec: SPEC-19
- Scope: share a rare or elite seen, with the zone name and the time. No coordinates.
- Done when:
  - [ ] No position beyond the zone name is ever sent.

### M15.3 — Guild legacy
- Branch: `step/m15-3-legacy`
- Spec: SPEC-19
- Scope: a timeline of the guild's firsts and achievements, from the game's events and from officers' entries.
- Done when:
  - [ ] The same achievement seen by many clients is one entry.

### M15.4 — Bingo and bounties
- Branch: `step/m15-4-bingo`
- Spec: SPEC-19
- Scope: weekly cards of goals that tick themselves from game events, and bounties set by officers. Rewards are only recognition.
- Done when:
  - [ ] No gold or item is ever staked or moved by the addon.

### M15.5 — Quiz and Secret Santa
- Branch: `step/m15-5-quiz-santa`
- Spec: SPEC-19
- Scope:
  - guild quizzes run by an officer, answered by whisper;
  - a Secret Santa draw among opted-in members.
- Done when:
  - [ ] Only the drawn giver learns their recipient; the draw cannot be repeated to fish for a name.

### M15.6 — In-game check and `v0.15.0`
- Branch: `step/m15-6-release`
- Scope:
  - `docs/checklists/M15.md`;
  - the wiki and both READMEs up to date.

  The full release check and `v1.0.0` moved to M16.6 (2026-11-26), then to M17.7 and M18.7 (2026-11-27).
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.15.0`.
