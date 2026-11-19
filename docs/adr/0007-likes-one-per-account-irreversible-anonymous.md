# 0007. Likes: one per account to account, irreversible, anonymous totals

- Status: Accepted
- Date: 2026-11-18 ([SPEC-07 §2](../specs/SPEC-07-reputation-social.md#2-like))

## Context

The owner wants a guild "appreciation" signal: every player can give **one like** to every other player, **never to themselves**, and **cannot take it back**. Decisions D1 and D2: the like goes **from account to account** (all the characters of an account count as one voter and as one target, and the total shows on every character of the target) and likes are **anonymous** (only the total is shown).

## Decision

1. A vote is sent by **addon whisper to one online officer** (the notary), never on `GUILD`, so that plain members never see who voted.
2. The notary maps the sender to its account (ADR 0006), refuses votes for the voter's own account, and computes a **voter pseudonym** `HMAC-SHA256(guildSalt, voterAccountToken)`. The `guildSalt` is a random secret created by the first officer and kept only by officers (`OFFICER` channel).
3. The ledger entry `{pseudonym, targetCharacterGUID, day}` is appended and broadcast on `GUILD`. Members' clients accept ledger entries only from officers (ADR 0005). The total of an account is the number of **distinct pseudonyms** among the entries that target any of its characters, so likes merge when alts are linked later.
4. The ledger is **append-only**: there is no "unlike" message. If a voter already liked any character of the target account, the notary refuses the vote and the voter's client hides the button.
5. If no officer is online, the vote waits in a local queue and is delivered later.

## Alternatives considered

- **Votes broadcast on `GUILD`.** Every member would see who voted.
- **Per-character likes.** A player with five alts would give five likes (rejected by the owner).

## Implementation note (M4.1)

`Data/Notary.lua` keeps the salt only on officers' clients, per guild, and drops it when the character is demoted. Officers ask for it on `OFFICER` after login and share what another officer lacks; while the client has not shown that `OFFICER` carries addon messages (S5, the `officerAddonChannel` capability), the same `SALT` messages also go by whisper to the officers with the addon heard recently. The salt is drawn by `Hash.RandomBytes`, an SHA-256 entropy pool fed with fine clock readings, memory and table addresses and the arrival times of addon messages, because the client has no secure random source. Two officers may create a salt at the same moment: every salt is kept in a ring of at most eight, all officers use the oldest one for new pseudonyms, and the notary checks a vote against all of them, so two salts never allow two votes. The voter's client picks the notary: itself when it is an officer holding a salt, else the officers heard recently ranked by a hash of the two GUIDs, skipping those already tried.

## Consequences

- Positive: members see only totals; a modified client cannot invent votes or vote twice.
- Negative: the notary officer sees the sender at the moment of delivery (documented honestly); a member who never logs in with the addon can receive likes but not give them; pure-Lua SHA-256 is needed because `C_EncodingUtil` has no hash.
