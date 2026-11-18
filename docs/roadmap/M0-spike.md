# M0 — Spike in the real client

**Goal:** answer, in the real WoW Forever client, the questions the design cannot answer offline ([SPEC-09 §1](../specs/SPEC-09-quality-release.md#1-spike-tecnico-m0)).

**Who:** the owner in game, with a guild character (ideally an officer and a plain member, two accounts or a second player); the session prepares the probe and reads the results.

**Exit criterion:** `docs/spike/M0-results.md` answers S1–S11, the affected specs and ADRs are updated, and each area has a **go / revise** decision.

The probe addon `AzAc_Probe` lives in `tools/probe/`, is **never distributed**, wraps every call in `pcall`, uses the test prefix `AzAcP`, and never prints or stores player or guild names.

### M0.1 — Probe addon skeleton
- Branch: `step/m0-1-probe-skeleton`
- Depends on: —
- Spec: SPEC-09 §1
- Scope: `tools/probe/AzAc_Probe/` (TOC 16001), `/aacp list|run <id>|export|reset`, results `{id, result, details, build, time}` in `AzAc_ProbeDB`, an export frame with all results as text; `tools/install_probe.py` and `tools/local.example.ini`; `docs/spike/README.md`.
- Done when:
  - [ ] The probe loads on Forever and `/aacp` lists the checks. *(in game)*
  - [x] Offline: files, commands, check registry and install script exist; `check_docs.py` passes.
- Real client: everything.

### M0.2 — The Accord tab in the guild window (S1)
- Branch: `step/m0-2-guild-tab`
- Depends on: M0.1
- Scope: `/aacp tab` adds a test tab to `CommunitiesFrame` (structure dump: tab names, anchors, display modes, `CommunitiesFrame.GuildMemberDetailFrame`), shows a test panel, hides it on Blizzard tab clicks via hooks; records `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN` while the owner promotes, invites, edits notes and enters combat with the tab used.
- Done when:
  - [ ] S1 answered: tab position and look, no taint (or which action is blocked), minimized mode, `/reload`. *(in game)*
  - [x] Offline: `/aacp tab`, the structure dump, the hooks and the blocked-action log exist; `check_docs.py` passes.
- Real client: everything.

### M0.3 — Roster, professions and contacts (S2, S8, S10)
- Branch: `step/m0-3-roster-contacts`
- Depends on: M0.1
- Scope: every `ClubMemberInfo` field for the guild (counts of filled values, never names: professions, `discordInfo` shape, `bnetAccountId`, online and offline members); `BNet_GetBattleTagSelf` presence and format; `C_Club.SendBattleTagFriendRequest` on a volunteer; account-wide SavedVariables across characters and realms.
- Done when:
  - [ ] S2, S8 and S10 answered. *(in game)*
  - [x] Offline: the three checks, `/aacp btag` and the SavedVariables stamps exist; `check_docs.py` passes.
- Real client: everything.

### M0.4 — Recipes (S3, S4)
- Branch: `step/m0-4-recipes`
- Depends on: M0.1
- Scope: native guild recipe directory (`IsGuildTradeSkillsEnabled`, `QueryGuildMemberRecipes`, `GUILD_RECIPE_KNOWN_BY_MEMBERS`, `GetGuildMemberRecipes`, `QueryGuildMembersForRecipe`, `GetNumGuildTradeSkill`); own recipe scan with the profession window open and closed, recipe counts and timing.
- Done when:
  - [ ] S3 and S4 answered; the source per profession is decided.
- Real client: everything.

### M0.5 — Guild messaging (S5, S6)
- Branch: `step/m0-5-messaging`
- Depends on: M0.1
- Scope: `/aacp ping guild|officer`, pong replies, bursts to measure a safe rate, result codes; `/aacp whisper <name>` between guildmates; lockdown snapshots in the open world, in combat, in a dungeon, during a boss and in a battleground.
- Done when:
  - [ ] S5 and S6 answered; send gaps per distribution decided.
- Real client: everything (two clients).

### M0.6 — Group roster (S7)
- Branch: `step/m0-6-group`
- Depends on: M0.1
- Scope: in a party, a raid and an instance: `UnitGUID` of each unit, `UnitIsInMyGuild`, `GetRaidRosterInfo`, `issecretvalue` on the results, `GROUP_ROSTER_UPDATE` timing.
- Done when:
  - [ ] S7 answered.
- Real client: everything.

### M0.7 — Guild bank and performance (S9, S11)
- Branch: `step/m0-7-bank-performance`
- Depends on: M0.1
- Scope: at the vault, as a member and as an officer: tabs and their view permissions, items per tab, money, item and money logs (count, time format), events and timing; `/aacp perf` runs the social index and a 500-member roster on generated data and reports milliseconds.
- Done when:
  - [ ] S9 and S11 answered.
- Real client: everything.

### M0.8 — Results and decisions
- Branch: `step/m0-8-results`
- Depends on: M0.2–M0.7
- Scope: `docs/spike/M0-results.md` (one row per check, evidence, consequence); updates to specs and ADRs (new ADRs for changed decisions); ROADMAP and README status.
- Done when:
  - [ ] Every check S1–S11 has a result and a consequence; go / revise per area written.
