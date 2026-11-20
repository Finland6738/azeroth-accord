# M15 — Community and fun

**Goal:** opt-in community features:
- help requests;
- rare sightings;
- the guild's legacy;
- bingo and bounties;
- quizzes;
- Secret Santa.

No gambling and no gold stakes. Each feature can be switched off by the guild and by the player. After M15 comes the release of `v1.0.0`.

**Exit criterion:** in game, a help request reaches only members who opted in, and a weekly bingo card ticks itself from game events.

### M15.1 — Specification
- Branch: `step/m15-1-spec`
- Scope: write a new SPEC-19 ("Comunità"), in Italian. It says, for each feature, what it sends, who receives it, and its switch.
- Done when:
  - [ ] SPEC-19 is linked from the spec index; `tools/check_docs.py` passes.

### M15.2 — Help requests
- Branch: `step/m15-2-help`
- Spec: SPEC-19
- Scope: "need a hand" for a quest, a dungeon or an elite. It goes to online members who opted in, with the zone name only.
- Done when:
  - [ ] Members who did not opt in receive nothing; a request expires after a set time.

### M15.3 — Rare sightings
- Branch: `step/m15-3-rares`
- Spec: SPEC-19
- Scope: share a rare or elite seen, with the zone name and the time. No coordinates.
- Done when:
  - [ ] No position beyond the zone name is ever sent.

### M15.4 — Guild legacy
- Branch: `step/m15-4-legacy`
- Spec: SPEC-19
- Scope: a timeline of the guild's firsts and achievements, from the game's events and from officers' entries.
- Done when:
  - [ ] The same achievement seen by many clients is one entry.

### M15.5 — Bingo and bounties
- Branch: `step/m15-5-bingo`
- Spec: SPEC-19
- Scope: weekly cards of goals that tick themselves from game events, and bounties set by officers. Rewards are only recognition.
- Done when:
  - [ ] No gold or item is ever staked or moved by the addon.

### M15.6 — Quiz and Secret Santa
- Branch: `step/m15-6-quiz-santa`
- Spec: SPEC-19
- Scope:
  - guild quizzes run by an officer, answered by whisper;
  - a Secret Santa draw among opted-in members.
- Done when:
  - [ ] Only the drawn giver learns their recipient; the draw cannot be repeated to fish for a name.

### M15.7 — In-game check, `v0.15.0` and `v1.0.0`
- Branch: `step/m15-7-release`
- Scope:
  - `docs/checklists/M15.md`;
  - the full release check of `docs/checklists/release.md`, rerun over everything;
  - the wiki and both READMEs complete.
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.15.0`.
  - [ ] The full release check passes and the owner tags `v1.0.0`.
