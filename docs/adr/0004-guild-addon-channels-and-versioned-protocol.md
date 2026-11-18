# 0004. Guild and officer addon channels, a versioned protocol

- Status: Accepted
- Date: 2026-11-18 ([SPEC-02](../specs/SPEC-02-network-protocol.md))

## Context

All data is guild-internal (ADR 0001). The server delivers `GUILD` addon messages only to online guild members and `OFFICER` messages only to ranks that can read officer chat. Since the 12.0 engine, addon messages can be refused during chat lockdown (instances, encounters).

## Decision

1. One registered prefix, `AzAccord`; distributions `GUILD` (members), `OFFICER` (officer-only data) and `WHISPER` (votes to an officer, point-to-point requests).
2. Every message starts with a protocol version and a type; an unknown version or type is ignored, never an error.
3. Messages are serialized with `C_EncodingUtil` (CBOR, compression, Base64) when available, through Compat, and split into parts by AceComm with ChatThrottleLib.
4. A send queue respects the throttle and **waits** while `C_ChatInfo.InChatMessagingLockdown()` or the addon restrictions are active; nothing is lost, it goes out later.
5. Sync is digest based: at login and periodically a client announces a short hash per data set, and only the differences are requested ([SPEC-02](../specs/SPEC-02-network-protocol.md)).

## Implementation note (M1.7)

The digest of point 5 is kept **per author**, not per data set: the trust rules (ADR 0005) let only the author's account or an officer pass a record on, so the sync must know whose data is missing to know who may send it. A client that is ahead of a HELLO's sender pushes what it may deliver; a client that is behind asks the sender, and the answer goes to the whole guild once. The protocol and its traffic budget, proved by the network simulator with 50 clients, are in [SPEC-02 §4](../specs/SPEC-02-network-protocol.md#4-sincronizzazione).

## Alternatives considered

- **A custom channel.** Needed only for cross-guild data, which this addon does not have.
- **Full broadcasts at every login.** Too much traffic in a large guild.

## Consequences

- Positive: closed audience given by the server; traffic proportional to changes.
- Negative: if `OFFICER` turns out not to work as an addon distribution (M0, S5), officer data must travel encrypted or not at all; the spike decides.
