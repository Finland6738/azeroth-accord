# 0016. Offline tests with lupa and a mock client

- Status: Accepted
- Date: 2026-11-18 (the approach of Azeroth Guild Finder, ADR 0019 there)

## Context

The addon runs only inside WoW Forever, which cannot start in continuous integration, and the owner cannot test in the client for every step. Most of the logic (accounts, sync, likes ledger, social index, bank snapshots, request workflow) does not depend on graphics.

## Decision

1. **Runner** `Tests/run_tests.py` with `lupa.lua51` (pinned `lupa==2.8`, Lua 5.1 like the client): it loads the real embedded libraries and the addon files in TOC order, each with the addon name and a private namespace table, like the client.
2. **Mock client** in `Tests/mock/`, one area per file (frames and events, timers and a controllable clock, `C_ChatInfo` addon messages with lockdown, guild roster and `C_Club` members, group roster, trade skills, guild bank), each file citing the dump entries it imitates.
3. **`/reload` simulation** that serializes and restores the SavedVariables declared in the TOC.
4. **Network simulator** `Tests/sim/`: N complete clients in one Lua state, with latency, loss and restrictions, to prove that sync, the likes ledger and the request workflow converge.
5. Every step adds tests for what it builds. The harness starts as a copy of Azeroth Guild Finder's ([ADR 0018](0018-reuse-azeroth-guild-finder-foundations.md)).

## Consequences

- Positive: fast tests in CI; the protocol is proven with many clients.
- Negative: a green test shows that the code agrees with our assumptions about the client, not that the client agrees: the M0 results and the in-game check of each milestone stay necessary.
