# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Design

- Specification of the first version in `docs/specs/` (SPEC-00 to SPEC-10, in Italian): scope, roles and the owner's decisions; platform and architecture; guild-only network protocol and trust rules; data model; the Accord tab in the guild window; extended roster, alts and contacts; professions and recipes; likes and the social index; guild bank; quality, spike and release; risks and open questions.
- Architecture decisions 0001–0018 in `docs/adr/`.
- Decisions confirmed by the owner: likes from account to account, irreversible and anonymous (only totals); alt list, BattleTag and Discord always shared with the guild; milestone order roster → professions → reputation → bank; name Azeroth Accord, GPL-3.0.

### Planning

- Development roadmap in `docs/roadmap/`: M0 spike to M6 release (50 steps) with branch, dependencies, scope, acceptance criteria, tests, docs and real-client checks, plus the V2 backlog.

### Spike

- M0.1: the probe addon skeleton `tools/probe/AzAc_Probe/` (TOC 16001, check registry S1–S11 as stubs, `/aacp list|run|export|reset`, export frame, `AzAc_ProbeDB`), `tools/install_probe.py` with `tools/local.example.ini`, and `docs/spike/README.md`.
- M0.2: probe check S1 (`Checks_GuildTab.lua`): `/aacp tab` adds a test tab and panel to the guild window using only hooks, dumps the window structure and the taint state, and logs `ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN`; `/aacp note` stores owner observations.
- M0.3: probe checks S2, S8 and S10 (`Checks_Roster.lua`): field statistics of `C_Club.GetMemberInfo` for the whole guild (counts only, online and offline, `discordInfo` shape, `bnetAccountId` sharing, realm parts of names), own BattleTag shape and `/aacp btag friend` on a volunteer, account-wide SavedVariables stamps across characters and realms.

### Repository

- Licence, code of conduct, contributing guide, issue and pull request templates, CI (documentation checks), the docs rule, the wiki sync and the advisory DCO check; `tools/check_docs.py`, `tools/check_pr_docs.py`, `tools/ship_step.py` and `tools/sync_wiki.py` adapted from Azeroth Guild Finder ([ADR 0018](docs/adr/0018-reuse-azeroth-guild-finder-foundations.md)).
- User manual skeleton in `docs/wiki/` (design phase).
- `tools/ship_step.py` no longer uses GitHub's squash merge, which authors the commit with the account's personal email and refuses the noreply address: it squashes the step locally into one noreply commit, lets CI check it in the pull request and fast-forwards `main` to it ([ADR 0012](docs/adr/0012-git-flow-and-automated-shipping.md)).
