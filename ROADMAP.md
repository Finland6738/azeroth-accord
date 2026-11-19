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
| **[M5 – Guild bank](docs/roadmap/M5-guild-bank.md)** | `step/m5-…` | Bank snapshots, logs, donations, withdrawal and deposit requests approved by officers | a request goes from a member to an officer and is fulfilled; `v0.9` beta |
| **[M6 – Release](docs/roadmap/M6-release.md)** | `step/m6-…` | Settings, Italian interface, polish, diagnostics, packaging, images of the manual | `v1.0.0` |

Later ([V2 backlog](docs/roadmap/V2-backlog.md)): raid sign-ups and attendance, the guild's loot system, guild board and notes, craft orders, goals, polls, officer tools.

## Rules for every step

1. Take the next unticked step of the current milestone file and start its branch from an up-to-date `main` (`step/m<N>-<k>-<name>`).
2. Keep the step small; open an issue for anything outside it.
3. Update in the same branch: `CHANGELOG.md`, the affected specs and ADRs, `README.md` and `README.it.md` when features or status change, and **`docs/wiki/` for anything a user can see**.
4. Run `python -I -X utf8 tools/check_docs.py` (and the addon tests from M1).
5. Ship: `python -I -X utf8 tools/ship_step.py --title "M<N>: <summary>" --body-file <pr.md>` squashes the step into one commit, pushes, opens the pull request, waits for CI and fast-forwards `main` to it ([ADR 0012](docs/adr/0012-git-flow-and-automated-shipping.md)). The wiki is published automatically after the merge.
6. The pull request says honestly what was **not** verified in the real client, and ticks the step's checkboxes in its milestone file.
