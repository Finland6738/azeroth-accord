# Project decisions (ADRs)

The architecture and method decisions of Azeroth Accord, one per file, in the [MADR](https://adr.github.io/madr/) format in English: **context**, **decision**, **alternatives considered**, **consequences**.

They record *why* the project is built a certain way. A decision that changes is not rewritten: a new ADR supersedes it, and the old one moves to the "superseded" status. The detailed design is in the [specification](../specs/README.md) (Italian).

## Index

| No. | Decision | Status |
|---|---|---|
| [0001](0001-client-only-addon-guild-only-data.md) | A client-only addon; data stays inside the guild | accepted |
| [0002](0002-wow-forever-target-and-api-dump.md) | Target WoW Forever (Interface 16001) and use the API dump as a reference | accepted |
| [0003](0003-accord-tab-in-the-guild-window.md) | An Accord tab in Blizzard's guild window, with a standalone window as fallback | accepted (to verify in M0) |
| [0004](0004-guild-addon-channels-and-versioned-protocol.md) | Guild and officer addon channels, a versioned protocol | accepted |
| [0005](0005-trust-first-hand-records-and-officer-relays.md) | Trust: first-hand records, relays only from officers | accepted |
| [0006](0006-account-token-and-always-shared-character-list.md) | Account identity: an account token and an always-shared character list | accepted |
| [0007](0007-likes-one-per-account-irreversible-anonymous.md) | Likes: one per account to account, irreversible, anonymous totals | accepted |
| [0008](0008-social-breadth-index-from-co-play.md) | The social breadth index, computed from minutes played together | accepted |
| [0009](0009-guild-bank-snapshots-and-officer-approved-requests.md) | Guild bank: shared snapshots and requests approved by officers | accepted (to verify in M0) |
| [0010](0010-native-data-first-shared-data-as-fallback.md) | Native game data first, data shared by the addon as fallback | accepted |
| [0011](0011-embedded-ace3-savedvariables-and-schema-versions.md) | Embedded Ace3, SavedVariables and schema versions | accepted |
| [0012](0012-git-flow-and-automated-shipping.md) | Git flow and automated shipping of milestone steps | accepted |
| [0013](0013-github-wiki-generated-from-docs-wiki.md) | The GitHub wiki: a user manual generated from `docs/wiki/` | accepted |
| [0014](0014-automatic-rules-ci-docs-rule-wiki-sync.md) | Automatic rules: CI, a docs rule and the wiki sync | accepted |
| [0015](0015-interface-and-documentation-languages.md) | Interface in English and Italian; documentation languages | accepted |
| [0016](0016-offline-tests-with-lupa-and-a-mock-client.md) | Offline tests with lupa and a mock client | accepted |
| [0017](0017-license-gpl-3.md) | Licence: GNU GPL v3.0 | accepted |
| [0018](0018-reuse-azeroth-guild-finder-foundations.md) | Reuse the foundations of Azeroth Guild Finder | accepted |
| [0019](0019-design-previews-original-art-invented-data.md) | Design previews: original art, invented data, drawn from the addon's texts | accepted |
| [0020](0020-one-version-per-milestone.md) | One version per milestone; `v1.0.0` after the last milestone | accepted |
| [0021](0021-interface-follows-the-ecosystem-style-of-fdcp.md) | The interface follows the ecosystem style of FDCP | accepted |
