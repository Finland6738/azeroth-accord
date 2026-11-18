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
