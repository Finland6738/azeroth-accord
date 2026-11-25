# 0024. Guild group finder: short-lived listings outside the sync summary; the game's finder only private and on the leader's click

- Status: Accepted
- Date: 2026-11-25 ([M9.1](../roadmap/M9-action-center.md), [SPEC-13](../specs/SPEC-13-action-center-notices.md))

## Context

M9 adds a group finder for the guild only: a leader posts a listing (a dungeon, a raid, a quest, help with an elite…), members apply with a role, the leader accepts and invites. A listing lives for minutes or hours. Every data set so far is long-lived and travels through the per-author sync (SPEC-02 §4): each record changes its author's digest in `HELLO`, and a client that is behind asks for it or has it pushed. Short-lived records would keep changing digests, and clients that prune an expired listing at slightly different times would disagree on a digest and repair each other with records the receiver then refuses as expired, which also counts towards the quarantine of SPEC-11 §6.3.

The game has its own Group Finder (`C_LFGList`). The WoW Forever dump has `CreateListing` with an `isPrivateGroup` field (visible to friends and guild members), but it does not say which calls are protected, the creation data has no name or comment, and whether the server honours the private flag is unknown. A public listing would show guild plans to strangers.

## Decision

1. **A volatile data set.** Listings are the set `groups`, with two new definition fields: `volatile` (never in `HELLO`, `BHELLO` or `OHELLO` summaries, never pushed or answered to `REQ`, never in backups or exports) and `firstHandOnly` (accepted only from the leader's own account; not even an officer may relay one). A listing goes out on `GUILD` as any local change; a client that was offline asks for the open ones with a new `GASK` when it opens the Groups view, and each leader answers with its own listing by whisper.
2. **Closing is derived, not sent.** Every client decides with the same data whether a listing is open: not expired, the leader online in the roster, roles still needed, the leader's newest listing. The leader's client also writes `full` or `closed` so late readers see it, but nothing depends on that message arriving.
3. **Applications are whispers to the leader only** (`GAPP`), never stored in the shared store. Accepting invites through `C_PartyInfo.InviteUnit` inside the leader's click; Accord never accepts, invites or converts a party on its own.
4. **The game's finder only privately, only from the leader's click.** Accord calls `CreateListing` only with `isPrivateGroup = true`, only inside the `OnClick` of its own button pressed by the leader, never in combat, and never writes text into the game listing. It treats the `C_LFGList` writes as protected, touches no Blizzard Group Finder frame and hooks nothing. If the active entry turns out not to be private, the capability is switched off for that client build and the leader is asked to remove it with one click. Without the capability nothing is offered.

## Alternatives considered

- **Listings as an ordinary synced set.** Simplest, but the digest churn and the refused expired records described above; also every login would pay for listings the player may never look at.
- **Periodic re-announcement of every open listing on `GUILD`.** No new message type, but steady traffic on every client for every listing, and late joiners still wait for the next round.
- **Officers relay listings to late joiners.** It would answer a `GASK` with one message, but it puts a relay between the leader and the guild for data only the leader may write, and nothing is answered when no officer is online.
- **Opening and pre-filling the game's Group Finder window.** Writing into Blizzard's frames from addon code is the classic source of taint, and the comment box is not an addon field.
- **Creating the game listing automatically when a guild listing is posted.** The calls are likely protected, and a listing that might become public must be the leader's explicit choice.

## Consequences

- A login costs nothing more: no listing is sent at login, and the traffic budget of SPEC-02 §4 stays as it is, checked by the simulator with 50 open listings.
- A client that never opens the Groups view (and has the match notice off) never asks for listings; it still hears the ones posted while it is online.
- A listing posted by an alt of the same account counts as first hand; one posted for someone else cannot exist.
- What the game's finder allows on Forever (private listings, who sees them, whether a hardware event is needed) is checked in game in M9.8; until then the guild finder is the only one.
