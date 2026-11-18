# 0018. Reuse the foundations of Azeroth Guild Finder

- Status: Accepted
- Date: 2026-11-18

## Context

Azeroth Guild Finder, by the same owner and under the same licence (GPL-3.0), already has working, tested foundations for WoW Forever: Compat layer, Config with schema versions, event Bus, Codec on `C_EncodingUtil`, Transport with queue and lockdown handling, Diagnostics, UI widgets and skin, the lupa test harness, the mock client and the network simulator, and the repository tooling (docs checks, ship script, wiki sync, packaging).

## Decision

1. Accord starts from **copies** of those modules, renamed to its own namespace, and adapts them: the Transport uses `GUILD`, `OFFICER` and `WHISPER` instead of a public channel.
2. The copies are independent: no shared library and no runtime dependency between the two addons, so both can be installed together and evolve separately.
3. Each copied file says in its header where it comes from; a fix found in one project is ported to the other by hand when it applies.

## Alternatives considered

- **A shared library addon.** One more thing to install and version for players.
- **Writing everything again.** Slower and loses tested behaviour.

## Consequences

- Positive: M1 is mostly adaptation; the test harness exists from day one.
- Negative: two copies of similar code to keep in mind.
