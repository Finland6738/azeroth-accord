# Contributing to Azeroth Accord

Thank you for your interest! This guide explains how to report problems, propose ideas and change the project.

## Language

Issues, pull requests, commit messages and public documentation are in **English**. The internal specification in `docs/specs/` is in Italian ([ADR 0015](docs/adr/0015-interface-and-documentation-languages.md)).

## Contents

1. [Before you start](#1-before-you-start)
2. [Reporting a problem or proposing an idea](#2-reporting-a-problem-or-proposing-an-idea)
3. [Changing the code](#3-changing-the-code)
4. [Checks and tests](#4-checks-and-tests)
5. [Git, issues and pull requests](#5-git-issues-and-pull-requests)
6. [What is not accepted](#6-what-is-not-accepted)
7. [Licensing of contributions](#licensing-of-contributions)

## 1. Before you start

- Read the [specification](docs/specs/README.md) and the [ADRs](docs/adr/README.md): they explain what the addon does and why.
- The addon targets **WoW Forever, Interface 16001**. Check every API in the Forever API dump ([ADR 0002](docs/adr/0002-wow-forever-target-and-api-dump.md)) and guard it with the Compat layer.

## 2. Reporting a problem or proposing an idea

- **Bugs**: open an issue with the *Bug report* form.
- **Ideas and questions**: start a topic in the [Feedback discussions](https://github.com/Finland6738/azeroth-accord/discussions/categories/feedback); a concrete request can become a *Feature request* issue.
- **Checks in the real client**: use the *In-game test report* form.
- **Privacy**: never paste other players' names, whispers, account names, BattleTags, Discord names or folder paths from your PC.

## 3. Changing the code

- Modules are isolated and talk through the internal event bus ([SPEC-01 §3](docs/specs/SPEC-01-platform-architecture.md#3-moduli)).
- Every game API call goes through `Core/Compat.lua`.
- Every visible string goes through AceLocale (`L["KEY"]`) and exists in `enUS` and `itIT`.
- Saved data changes need a schema migration ([ADR 0011](docs/adr/0011-embedded-ace3-savedvariables-and-schema-versions.md)).
- Network records follow the trust rules ([ADR 0005](docs/adr/0005-trust-first-hand-records-and-officer-relays.md)): never accept another author's record without the relay or authority check.
- The addon lives in `AzerothAccord/` (Lua 5.1 only, from M1.1). Libraries are never committed: they are pinned in `.pkgmeta`.

## 4. Checks and tests

```
python -I -X utf8 tools/check_docs.py
python -m pip install lupa==2.8            # once, from M1.2
python -X utf8 Tests/run_tests.py          # all offline tests, from M1.2
```

`check_docs.py` checks relative links, the wiki sidebar and links, the ADR index, personal data (emails and personal paths) and LF line endings; from M1.1 also the addon TOC and the package contents. The offline tests run Lua 5.1 through lupa on a mock client ([ADR 0016](docs/adr/0016-offline-tests-with-lupa-and-a-mock-client.md)): `Tests/run_tests.py` loads the real libraries (it runs `tools/fetch_libs.py` when they are missing) and the addon in TOC order, then every `Tests/test_*.lua`, each test on a freshly booted client. `python -X utf8 Tests/run_tests.py <text>` runs only the tests whose name contains the text, `-v` adds tracebacks. The mock client is in `Tests/mock/` (one area per file, each citing the API dump entries it imitates); `Mock.Reload()` simulates `/reload` by writing out and reading back the SavedVariables.

## 5. Git, issues and pull requests

- One branch per step or fix from an up-to-date `main`: `step/m<N>-<k>-<name>`, `fix/<name>`, `docs/<name>`, `chore/<name>`.
- Small commits with clear messages in English.
- Every pull request updates **in the same PR**: `CHANGELOG.md` ("Unreleased"), the affected docs (specs, ADRs and the ADR index, both READMEs) and **the wiki pages in `docs/wiki/` for any user-visible change**. The *Docs rule* check enforces it for changes to the addon ([ADR 0014](docs/adr/0014-automatic-rules-ci-docs-rule-wiki-sync.md)).
- The wiki is **never edited on GitHub**: it is published from `docs/wiki/` after every merge ([ADR 0013](docs/adr/0013-github-wiki-generated-from-docs-wiki.md)).
- A pull request reaches `main` as one squashed commit when `Tests` and `Docs rule` are green; the maintainer squashes external contributions the same way, keeping the contributor as co-author.
- The maintainer's steps are shipped with `tools/ship_step.py` ([ADR 0012](docs/adr/0012-git-flow-and-automated-shipping.md)).
- A pull request that fixes an issue says `Closes #N`.

## 6. What is not accepted

- Code that sends anything outside the game or outside the guild, telemetry or external services.
- Files copied from the game client or from other games.
- Showing who gave a like ([ADR 0007](docs/adr/0007-likes-one-per-account-irreversible-anonymous.md)).
- Personal data in the repository.

## Licensing of contributions

By submitting a contribution you agree that it is released under the project's licence, the [GNU GPL v3.0](LICENSE), and you certify that you have the right to submit it (Developer Certificate of Origin: sign off your commits with `git commit -s`).
