# 0001. A client-only addon; data stays inside the guild

- Status: Accepted
- Date: 2026-11-18 ([SPEC-01](../specs/SPEC-01-platform-architecture.md))

## Context

The owner wants a richer guild panel for WoW Forever: an extended roster with professions and recipes, contacts, alts, likes, a social index and the guild bank. There is no server we control, and addons cannot reach the internet.

## Decision

1. Azeroth Accord is **only an addon**. Every piece of data comes from the game API on the player's client or from other members' clients through hidden addon messages.
2. Data travels **only inside the guild**: the `GUILD` and `OFFICER` addon distributions and addon whispers between guildmates. No public channel is used.
3. Every client keeps its own copy in SavedVariables and converges with the others through a sync ([SPEC-02](../specs/SPEC-02-network-protocol.md)).

## Alternatives considered

- **An external service (website, Discord bot).** Not reachable from the game, and it would need hosting and accounts.
- **A public custom channel.** Not needed: everything is guild-internal, and the guild distribution is closed by the server.

## Consequences

- Positive: no infrastructure, no data outside the game, privacy by construction.
- Negative: data written by members who never log in with the addon is missing; what is shared converges only while members are online.
