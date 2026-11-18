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

## Consequences

- Positive: members see only totals; a modified client cannot invent votes or vote twice.
- Negative: the notary officer sees the sender at the moment of delivery (documented honestly); a member who never logs in with the addon can receive likes but not give them; pure-Lua SHA-256 is needed because `C_EncodingUtil` has no hash.
