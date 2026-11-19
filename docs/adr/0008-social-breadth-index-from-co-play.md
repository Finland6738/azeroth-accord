# 0008. The social breadth index, computed from minutes played together

- Status: Accepted
- Date: 2026-11-18 ([SPEC-07 §3](../specs/SPEC-07-reputation-social.md#3-indice-sociale))

## Context

The owner wants an automatic rating, "a kind of MMR", that rewards members who **group with many different guildmates** and does not reward a closed group of five who always play together, to understand whether the guild forms cliques.

## Decision

1. **Recording.** Every minute in a party or raid with at least one other guild member, each client with the addon adds one minute to every pair of guild members in the group (all pairs, not only its own: one addon user per group is enough). Alts are merged into accounts (ADR 0006).
2. **Combining.** Observations are kept per day and per pair; when several observers report the same pair and day, the **maximum** counts, never the sum (ADR 0005).
3. **Index.** Over the last 30 days, for an account with total minutes `M` and minutes `m_b` with each partner `b`: `p_b = m_b / M`, effective partners `N = exp(-Σ p_b ln p_b)` (exponential of the Shannon entropy), and **index = 100 × N / (A − 1)**, capped at 100, where `A` is the number of active accounts in the window. Under 5 hours of guild group play the index shows "not enough data".
4. **Guild view.** A weighted graph of accounts, its communities (label propagation) and modularity as the "mixing" signal: high modularity means cliques.

## Alternatives considered

- **Counting distinct partners.** Ten minutes once with everyone would look like real mixing.
- **Elo-like rating.** There is no match result to rate; entropy measures exactly "how spread" the play time is.

## Implementation note (M2.6)

Recording starts in M2, before any view exists (owner decision D6). `Data/CoPlay.lua` counts every 60 seconds, per realm day, publishes hourly, at logout and at the change of day, splits a day into records of at most 100 pairs (a 40-man raid has 780 pairs), each with one pair of the observer, and never guesses who a member with a hidden GUID is: it is counted as unreadable and left out.

## Implementation note (M4.4)

`Data/Social.lua` computes the index exactly as decided, over the last 30 realm days (today included): the maximum over the observers per day and pair, characters merged into accounts by the proved characters of `Accounts` (note hints merge nothing, pairs inside one account are left out), `M` counted per partner (the pair records say with whom, not for how long the player was grouped, so an hour with four guildmates counts four), `A` = accounts with at least 60 minutes, and no index below 5 hours or with fewer than two active accounts. It runs locally in steps of a coroutine (one step per frame), at most once every ten minutes when the data changed. The three worked examples of SPEC-07 §3.2 (index 10, 22 and 75 with A = 41) are numeric tests.

## Consequences

- Positive: explainable (the member card shows the partners' share), resistant to one-off groups.
- Negative: groups with no addon user are invisible; the index depends on guild size, so it is shown with the number of active accounts.
