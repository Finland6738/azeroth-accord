# Roadmap

This page is the short version and the rules every step follows. **The development steps of each milestone are in [docs/roadmap/](docs/roadmap/README.md)**, one file per milestone; the checks behind the plan are in [SPEC-09](docs/specs/SPEC-09-quality-release.md) (Italian).

## Milestones

| Milestone | Branch prefix | Content | Exit criterion |
|---|---|---|---|
| **[M0 – Spike](docs/roadmap/M0-spike.md)** | `step/m0-…` | A probe addon (not distributed) answers S1–S11 in the real client: the tab in the guild window, `ClubMemberInfo` fields, guild recipes, guild and officer addon messages, group roster, BattleTag, guild bank, performance | results in `docs/spike/M0-results.md`, specs and ADRs updated |
| **[M1 – Foundations](docs/roadmap/M1-foundations.md)** | `step/m1-…` | Skeleton (TOC 16001, Ace3, `.pkgmeta`), tests with a mock client, Compat, Config, Codec, Hash, Transport, Store, Sync, the Accord tab and panel | 50 simulated clients converge; the tab opens in game |
| **[M2 – Roster](docs/roadmap/M2-roster.md)** | `step/m2-…` | Extended roster with professions, alts by account, member card, BattleTag and Discord, co-play recording | a member's alts and contacts show in game |
| **[M3 – Professions](docs/roadmap/M3-professions.md)** | `step/m3-…` | Recipes from the profession cell, "who can craft", craft requests | recipes of a guildmate open from the roster |
| **[M4 – Reputation](docs/roadmap/M4-reputation.md)** | `step/m4-…` | Likes (account to account, irreversible, anonymous), social index, group map, suggested teammates | the same like totals on every client |
| **[M5 – Guild bank](docs/roadmap/M5-guild-bank.md)** | `step/m5-…` | Bank snapshots, logs, donations, withdrawal and deposit requests approved by officers | a request goes from a member to an officer and is fulfilled; `v0.5.0` |
| **[M6 – Release](docs/roadmap/M6-release.md)** | `step/m6-…` | Settings, Italian interface, polish, diagnostics, packaging, images of the manual; then the look of Finland Dragon Credit Points (themes, widgets, tabs), the About page and credits, the Italian wiki | M6.1–M6.17 complete in code; `v0.6.0` waits for the in-game checks |
| **[M7 – Data trust](docs/roadmap/M7-data-trust.md)** | `step/m7-…` | Provenance labels, the guild of alts outside the guild, demo mode, personal backup, "what I share", hardening | an alt in another guild shows that guild; `v0.7.0` |
| **[M8 – Officer tools](docs/roadmap/M8-officer-tools.md)** | `step/m8-…` | Roster timeline, inactivity by account, cleanup wizard and manual-ops queue, extended notes, export | inactivity counts alts; nothing is changed automatically; `v0.8.0` |
| **[M9 – Action Center](docs/roadmap/M9-action-center.md)** | `step/m9-…` | One inbox for pending items, notification history, quiet hours, login digest; a group finder only for the guild (dungeons, raids, quests, help) with roles and invitations; a Guild addons table with counts | requests of two modules in one inbox; a guild group posted, filled and invited; `v0.9.0` |
| **[M10 – Calendar and raids](docs/roadmap/M10-calendar-raids.md)** | `step/m10-…` | The guild's season roster (MS1 / MS2 / OS) from Accord or from FDCP, one source per datum; sign-ups on the game calendar; Raid-Helper events from Discord pasted in game; bench and composition, availability, rallies; the raid and loot addons of the guild detected; no attendance | role counts and gaps from the season declarations; a sign-up in Accord is the same in the game calendar; `v0.10.0` |
| **[M11 – Loot and handbook](docs/roadmap/M11-loot-handbook.md)** | `step/m11-…` | Editable guild handbook pages (info, rules, FAQ, raids, roster, loot); the loot system and its addon documented, who has it, FDCP read through its public API | an officer's edit reaches every member; officers see who has the loot addon; `v0.11.0` |
| **[M12 – Recruitment](docs/roadmap/M12-recruitment.md)** | `step/m12-…` | Recruitment text from the season gaps, trials, onboarding, mentors | a trial ends in the Action Center; `v0.12.0` |
| **[M13 – Economy](docs/roadmap/M13-economy.md)** | `step/m13-…` | Craft orders with states, material demand, wishlist, buy and sell board, guild goals | an order goes from request to delivered; `v0.13.0` |
| **[M14 – Board and polls](docs/roadmap/M14-board-polls.md)** | `step/m14-…` | Board, MOTD history, polls with one vote per account, kudos with a reason | the same poll totals on every client; `v0.14.0` |
| **[M15 – Community](docs/roadmap/M15-community.md)** | `step/m15-…` | Opt-in rare sightings, guild legacy, bingo and bounties, quiz, Secret Santa | `v0.15.0`, then `v1.0.0` |

**Versions** ([ADR 0020](docs/adr/0020-one-version-per-milestone.md)): every milestone N is released as `v0.N.0` after its in-game check; fixes raise only the last number (`v0.6.1`, `v0.6.2`); `v1.0.0` comes when every milestone up to M15 is done. Ideas not planned and what stays out: [backlog](docs/roadmap/V2-backlog.md).

## Rules for every step

1. Take the next unticked step of the current milestone file and start its branch from an up-to-date `main` (`step/m<N>-<k>-<name>`).
2. Keep the step small; open an issue for anything outside it.
3. Update in the same branch: `CHANGELOG.md`, the affected specs and ADRs, `README.md` and `README.it.md` when features or status change, and **`docs/wiki/` for anything a user can see**.
4. Run `python -I -X utf8 tools/check_docs.py` (and the addon tests from M1).
5. Ship: `python -I -X utf8 tools/ship_step.py --title "M<N>: <summary>" --body-file <pr.md>` squashes the step into one commit, pushes, opens the pull request, waits for CI and fast-forwards `main` to it ([ADR 0012](docs/adr/0012-git-flow-and-automated-shipping.md)). The wiki is published automatically after the merge.
6. The pull request says honestly what was **not** verified in the real client, and ticks the step's checkboxes in its milestone file.
