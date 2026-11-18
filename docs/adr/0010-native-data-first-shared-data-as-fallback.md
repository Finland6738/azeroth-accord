# 0010. Native game data first, data shared by the addon as fallback

- Status: Accepted
- Date: 2026-11-18 ([SPEC-06](../specs/SPEC-06-professions-recipes.md), [SPEC-05](../specs/SPEC-05-roster-alts-contacts.md))

## Context

The Forever client contains APIs that may give data for **every** member, also those without the addon: `ClubMemberInfo.profession1Name/Rank`, `profession2Name/Rank` and `discordInfo`, and the guild recipe directory (`C_TradeSkillUI.IsGuildTradeSkillsEnabled`, `C_GuildInfo.QueryGuildMemberRecipes`, `GetGuildMemberRecipes`). Whether the Forever servers fill them is unknown until M0.

## Decision

1. Each data source sits behind an **adapter** with two implementations: *native* (game API) and *shared* (what members' addons publish).
2. The adapter uses the native source when M0 and the runtime capability probe say it works, and the shared one otherwise; when both exist the native wins and the shared fills the gaps.
3. The interface always says where a value comes from and how old it is (for example "recipes shared by the member, 3 days ago").

## Alternatives considered

- **Shared data only.** Simpler, but members without the addon would always be empty.
- **Native data only.** The whole feature would depend on server support.

## Consequences

- Positive: the best coverage the game allows, with no code change when Blizzard enables a native feature.
- Negative: two code paths to test (both are covered by the mock client).
