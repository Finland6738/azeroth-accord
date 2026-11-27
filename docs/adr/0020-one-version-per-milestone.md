# 0020. One version per milestone; v1.0.0 after the last milestone

- Status: Accepted
- Date: 2026-11-20

## Context

The first plan had a test version per milestone up to M4 (`v0.1.0` to `v0.4.0`), a `v0.9.0` beta at the end of M5 and `v1.0.0` at the end of M6. After M6 the owner added milestones M7 to M15. They want every milestone to have its own version, and `v1.0.0` only when the whole plan is done.

## Decision

1. Every milestone N is released as **`v0.N.0`** after its in-game check: `v0.1.0` (M1) … `v0.6.0` (M6) … `v0.15.0` (M15). Minor numbers go past 9 (`v0.10.0`): versions are compared number by number, not as text.
2. Fixes to a released milestone raise only the last number, counting that milestone's fix releases: `v0.6.1`, `v0.6.2`.
3. **`v1.0.0`** is released when every planned milestone, up to M15, is done. Before it, [the release check](../checklists/release.md) is run again over everything.
4. Pre-release suffixes (`-alpha.N`, `-beta.N`, `-rc.N`) stay available for a first look at a version.
5. As before, development sessions create no tags; every tag waits for the owner's in-game check ([RELEASING](../RELEASING.md)).

## Consequences

- M5 is `v0.5.0` (no longer the `v0.9.0` beta), and M6 is `v0.6.0` (no longer `v1.0.0`).
- The checklists, `docs/RELEASING.md`, SPEC-09 §4, the roadmap and the READMEs use this scheme.
- The release workflow already accepts any `vMAJOR.MINOR.PATCH` tag; nothing in it changes.
- The "Unreleased" section of the changelog is promoted to `0.N.0` at each milestone release.

## Update (2026-11-25)

The owner changed points 1 and 5:

- The first release is **`v0.8.0`**, tagged before any in-game check; `v0.1.0` to `v0.7.0` are not tagged. The open checks stay open and what they find is fixed in `v0.8.<F>` releases.
- From M9 on, `v0.N.0` is released after each completed milestone; these milestone tags have the owner's standing approval. Any other tag is asked first, and development steps still create none.
- A release carries no half-finished feature: what a later milestone left in the code is switched off in `AzerothAccord/Core/Features.lua` until that milestone is complete.

## Update (2026-11-26)

The owner added milestone **M16** (guild quests, [M16](../roadmap/M16-quests.md)) after M15. Point 3 now reads "up to M16": M15 is released as `v0.15.0`, M16 as `v0.16.0`, and `v1.0.0` follows M16, whose last step runs the full release check.

## Update (2026-11-27)

The owner added milestone **M17** (professions assistant, [M17](../roadmap/M17-professions.md)) after M16. Point 3 now reads "up to M17": M16 is released as `v0.16.0`, M17 as `v0.17.0`, and `v1.0.0` follows M17, whose last step runs the full release check.
