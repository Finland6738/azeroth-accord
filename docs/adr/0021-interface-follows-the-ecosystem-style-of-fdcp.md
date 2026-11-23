# 0021. The interface follows the ecosystem style of FDCP

- Status: Accepted
- Date: 2026-11-23 ([ui-style](../specs/ui-style.md))

## Context

The owner also makes Finland Dragon Credit Points (FDCP), an addon for the same guild whose look comes from the community site (ADR 0004 of that project): dark "nebula" surfaces, tabs with an indicator, rounded 9-slice shapes, Outfit, JetBrains Mono and Orbitron fonts. Accord was drawn so that its panel feels native to Blizzard's guild window ([SPEC-04 §5](../specs/SPEC-04-ui-guild-tab-shell.md), `UI/Skin.lua`, the client's templates and fonts). On 2026-11-23 the owner asked that the two addons read as one family and approved doing it inside M6, so that `v0.6.0` ships with the new look (steps M6.8 to M6.17).

## Decision

1. **Accord follows FDCP's interface style.** FDCP's `docs/specs/ui-style.md` is the base; Accord's [`docs/specs/ui-style.md`](../specs/ui-style.md) (in Italian, [ADR 0015](0015-interface-and-documentation-languages.md)) records only the differences: names and prefixes (`AzerothAccord`, `AzerothAccordDB`, `AzerothAccordFont<Id>`), where the look settings are saved, the views as tabs, the panel inside the guild window and in the standalone window, and the themes.
2. **Copy and adapt, no shared library.** FDCP is only read, never modified. Its `Theme`, `Assets`, `Motion`, widgets, media tools and test mocks are copied into Accord and renamed (as the foundations of Azeroth Guild Finder were, [ADR 0018](0018-reuse-azeroth-guild-finder-foundations.md)). The two addons stay independent: no load order, no version coupling, one can be installed without the other.
3. **Three themes** with FDCP's token names: **Nebula** (default, dark) and **Aurora** (light) with FDCP's values unchanged, and **Accord** (dark), made from the addon logo's palette (dark teal-green, gold, mint), which takes the place FDCP gives to its own logo theme. A theme is a table of colours; textures are white and tinted at run time, so a theme changes without `/reload`.
4. **Personal look settings are per account** (`account.settings.theme`, `effects`, `animations`, `font`), with a Config schema migration (M6.10), not per character as in FDCP.
5. **Blizzard's frame is still only observed** ([ADR 0003](0003-accord-tab-in-the-guild-window.md)): the Accord panel inside the guild window is drawn with the addon's own frames and colours; no Blizzard frame is reskinned. The game's own look of `UI/Skin.lua` and `UI/Widgets/Base.lua` is replaced and the two files are removed (M6.14).
6. **Rules that do not change:** no Blizzard art in the repository, every string a locale key (enUS and itIT), no colour written outside `UI/Theme.lua`, only the public name "Finland", fonts under SIL OFL 1.1 with their licence texts, every media file listed in `docs/third-party.md`.

## Alternatives considered

- **Keep the game's own look.** Native to the guild window, but the two addons would look unrelated and the owner asked for one family.
- **A shared UI library used by both addons.** Less duplication, but it couples releases and installs, and FDCP must not be touched.
- **Only Nebula and Aurora.** Simpler, but Accord would have no colours of its own; FDCP has a theme from its logo and Accord's logo has a distinct palette.

## Consequences

- Positive: one visual family; a tested theme and widget system (registry, motion, fallback fonts) instead of new code; an About page and credits drawn once.
- Negative: duplicated code to keep in step by hand (fixes in one addon are not seen by the other); more media in the package (textures, three font families); a large change to every view, spread over M6.9 to M6.17; nothing is verified in the real client until the owner's checks, in particular the panel inside `CommunitiesFrame`.
