# 0002. Target WoW Forever (Interface 16001) and use the API dump as a reference

- Status: Accepted
- Date: 2026-11-18 (same decision as Azeroth Guild Finder, ADR 0002 there)

## Context

The addon is for **World of Warcraft: Forever**, an official Blizzard product: build `1.60.1`, `## Interface: 16001`, `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT`. It runs on a modern client (12.0 engine: Communities guild window, `Settings`, `C_EncodingUtil`, addon restrictions, chat lockdown) with level-60 content. Public documentation mostly covers retail.

## Decision

1. The TOC declares `## Interface: 16001`; at load the addon checks `WOW_PROJECT_CAMELOT` (or an Interface between 16001 and 19999).
2. The public API dump extracted from the Forever client (`Atraeau/WoW-Addons`, cloned next to the project) is the reference for what can be called. It declares no licence, so none of its files enter this repository.
3. Functions missing from the dump, or whose behaviour on the Forever servers is unknown (the guild recipe directory, `discordInfo`, guild bank logs), are marked **[verify]** in the specs, guarded by the Compat layer and confirmed in spike M0.

## Alternatives considered

- **Relying on the retail documentation.** Useful for meaning, unreliable for availability on Forever.
- **Copying the dump into the repository.** Not allowed without a licence.

## Consequences

- Positive: fewer calls to functions that do not exist; known risks are visible early.
- Negative: the dump is from build 70170; every client update needs a new check.
