# M1 — Foundations

**Goal:** a loadable addon with tests, the data store, guild transport and sync, and the Accord tab with an empty panel. Starts from copies of Azeroth Guild Finder's foundations ([ADR 0018](../adr/0018-reuse-azeroth-guild-finder-foundations.md)).

**Exit criterion:** two simulated clients exchange and converge on records over `GUILD`; in game the Accord tab opens an empty panel (owner's check).

### M1.1 — Addon skeleton and packaging
- Branch: `step/m1-1-skeleton`
- Spec: SPEC-01 §1, §3; ADR 0011
- Scope: `AzerothAccord/` (TOC 16001, SavedVariables, AddOn Compartment), `embeds.xml`, `Bindings.xml`, `Locale/enUS.lua` and `itIT.lua`, `Core/Init.lua` with the Forever check and `/accord help`; `.pkgmeta`, `.luarc.json`, `tools/fetch_libs.py`, `tools/install_addon.py`, `tools/check_addon.py`, `tools/check_package.py`; release workflow.
- Done when:
  - [x] `check_docs.py` checks the TOC and the package; the addon folder installs with the script.
- Tests: TOC and embeds checks.
- Real client: loads without errors.

### M1.2 — Offline test harness
- Branch: `step/m1-2-test-harness`
- Spec: SPEC-09 §2; ADR 0016
- Scope: `Tests/run_tests.py`, `Tests/lib/`, `Tests/mock/` (copied and renamed), `Tests/test_addon.lua`; CI runs the tests.
- Done when:
  - [x] Boot, slash command and `/reload` round trip are tested.

### M1.3 — Compat and capabilities
- Branch: `step/m1-3-compat`
- Spec: SPEC-01 §5
- Scope: `Core/Compat.lua` with guild, club, group, trade skill and bank helpers; `Compat:Probe()`; `Core/Diagnostics.lua` and `/accord debug`.
- Done when:
  - [x] Every [verify] API degrades without errors in the mock.

### M1.4 — Config, guild key and roles
- Branch: `step/m1-4-config`
- Spec: SPEC-01 §4; SPEC-00 §5
- Scope: `Core/Config.lua` (AceDB, schema, migrations), `Data/GuildKey.lua`, `Core/Role.lua`, `Core/Bus.lua`.
- Done when:
  - [x] Data is kept per guild; changing guild never mixes data; role changes fire on the Bus.

### M1.5 — Codec, hash and transport
- Branch: `step/m1-5-transport`
- Spec: SPEC-02 §1, §2, §5; ADR 0004
- Scope: `Net/Codec.lua`, `Core/Hash.lua` (SHA-256, HMAC, test vectors), `Net/Transport.lua` (`GUILD`, `OFFICER`, `WHISPER`, queue, lockdown, saved queue).
- Done when:
  - [x] Messages survive lockdown and `/reload`; hash matches the standard test vectors.

### M1.6 — Record store and trust rules
- Branch: `step/m1-6-store`
- Spec: SPEC-02 §3, §6; ADR 0005
- Scope: `Net/Store.lua`: data sets, `rev`, first-hand, relay and authority rules, retention.
- Done when:
  - [x] Forged authors and non-officer relays are refused in tests.

### M1.7 — Sync
- Branch: `step/m1-7-sync`
- Spec: SPEC-02 §4
- Scope: `Net/Sync.lua` (`HELLO`, `DIGEST`, `REQ`, `REC`), the network simulator `Tests/sim/`.
- Done when:
  - [x] 50 simulated clients converge with random logins, logouts and lockdown, within the traffic budget.

### M1.8 — The Accord tab and the panel shell
- Branch: `step/m1-8-guild-tab`
- Spec: SPEC-04; ADR 0003
- Scope: `UI/GuildTab.lua`, `UI/Shell.lua` (navigation, top bar, pop out), standalone window, AddOn Compartment entry, key binding; widgets and skin copied from Azeroth Guild Finder and restyled like Blizzard's guild window.
- Done when:
  - [ ] Tab, panel and window open and close in the mock; no Blizzard function is replaced.
- Real client: look, anchoring, taint (S1 again with the real code).

### M1.9 — M1 in-game check and v0.1.0
- Branch: `step/m1-9-check`
- Scope: `docs/checklists/M1.md`, CHANGELOG section, tag `v0.1.0` for the owner's guild.
- Done when:
  - [ ] The owner confirms load, tab and `/accord debug` in game.
