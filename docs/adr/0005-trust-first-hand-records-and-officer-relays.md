# 0005. Trust: first-hand records, relays only from officers

- Status: Accepted
- Date: 2026-11-18 ([SPEC-02 §6](../specs/SPEC-02-network-protocol.md#6-fiducia-e-integrità))

## Context

The sender name of an addon message is set by the server and cannot be faked. The content can: a modified addon could send any record "on behalf of" someone else, or replay old data. Some data is personal (my professions, my contacts, my characters), some must not be forgeable at all (likes, approved bank requests).

## Decision

1. Every record has an **author**. A record is accepted **first hand** only when the sender is the author (or one of the author's characters, ADR 0006).
2. A record received **through a relay** (from a client that is not its author) is accepted only if the relaying sender is an **officer** according to the receiving client's own roster.
3. Records that need an authority (the likes ledger, the status of bank requests, the bank snapshots of restricted tabs) are written **only by officers**; members' clients accept them only from officers.
4. Observations that cannot be first hand (co-play: "A and B were grouped together") are accepted only from an observer who was **in the observed group**, and are combined with a maximum, not a sum (ADR 0008).

## Alternatives considered

- **Digital signatures.** Heavy in pure Lua and with no key distribution; kept as a later option if abuse appears.
- **Trusting everyone.** One modified client could rewrite the guild's data.

## Consequences

- Positive: a member can only lie about themselves; authority follows the guild's own ranks.
- Negative: data of a member who is offline reaches others only through officers; a rogue officer is trusted (as in the game itself).
