# 0015. Interface in English and Italian; documentation languages

- Status: Accepted
- Date: 2026-11-18

## Context

The first guild using the addon is Italian, and the owner speaks Italian; the addon is published for every WoW Forever player.

## Decision

1. Every visible string is an AceLocale key: `enUS` is the base, `itIT` ships with `v1.0.0` (milestone M6). Other languages are one file each, with no code change.
2. **Public documentation in English**: README, wiki, ADRs, CONTRIBUTING, CHANGELOG, issues and pull requests. `README.it.md` is the Italian front page.
3. The internal specification in `docs/specs/` is written in **Italian**, with code names, APIs and interface texts in English.
4. Texts written by players (notes, requests, Discord handles) are never translated.

## Consequences

- Positive: usable in Italian from the first release, reachable by every player.
- Negative: two README files and two locale files to keep in step (a test checks that every key exists in both).

## Implementation note (M6.2)

`Locale/enUS.lua` is the base and `Locale/itIT.lua` has the same keys, translated; the client's locale picks one (`GetLocale()`), other locales fall back to English, and a key missing in Italian would show the English text. `Tests/test_locales.lua` reads both tables and fails when: a key exists in one table only; a string is empty or ends with a space; the placeholders (`%s`, `%d`, `%.1f`...) differ in kind or order, which would raise at run time; the colour, texture or link codes differ; a string is identical in both languages without being on the short list of intended ones (names, loanwords, `%s: %s`); a key read in the code (`L["KEY"]`) is not in the English table; or a family of keys built from a value (`BANKREQ_STATUS_*`, `BANKNOTE_*`, `MAP_MIXING_*`, the Roster column labels) lacks a member. It also runs an Italian client through every view and the Settings page. `tools/check_addon.py` makes the same key check at the package step. Not translated, on purpose: the `/accord debug` report (it is pasted into English bug reports, [ADR 0015](0015-interface-and-documentation-languages.md) rule 2), the texts players type, and the names the game gives (items, recipes, zones, ranks).
