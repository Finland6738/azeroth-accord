# 0011. Embedded Ace3, SavedVariables and schema versions

- Status: Accepted
- Date: 2026-11-18 (same as Azeroth Guild Finder, ADRs 0010 and 0011 there)

## Context

The addon needs events, comms, serialization, a database with defaults, localization and configuration, and its saved data will change shape over the milestones.

## Decision

1. Ace3 (AceAddon, AceEvent, AceComm with ChatThrottleLib, AceDB, AceLocale, AceConsole, AceConfig), LibDataBroker and LibDBIcon are **embedded**, pinned by tag in `.pkgmeta` and never committed: `tools/fetch_libs.py` downloads them for development and CI.
2. `AzerothAccordDB` (account-wide: account token, characters, guild data per guild) and `AzerothAccordCharDB` (per character: interface state).
3. Every saved table has a `schema` number; a migration function per version runs at `ADDON_LOADED`; unknown future versions are kept untouched and the addon runs read-only.
4. Data is stored per guild key (`<realm>/<guild name>`), so changing guild never mixes data.

## Implementation note (M1.4)

`Core/Config.lua` manages the two variables directly, as Azeroth Guild Finder does, instead of through AceDB profiles: Accord has no profiles, and the read-only rule for a newer schema needs the raw saved tables (AceDB would rewrite them with its own structure). AceDB stays embedded for a possible settings panel (M6). The account token is created by Config with a pure-Lua Base64, so it does not depend on `C_EncodingUtil`.

## Consequences

- Positive: proven libraries, safe upgrades.
- Negative: a few hundred KB of libraries in the package.
