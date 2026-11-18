# Spike: the probe addon

`AzAc_Probe` is a **throwaway** addon used in milestone M0 to answer, in the real WoW Forever client, the questions the design cannot answer offline ([SPEC-09 §1](../specs/SPEC-09-quality-release.md#1-spike-tecnico-m0), in Italian). It lives in `tools/probe/AzAc_Probe/` and is **never distributed**: it is not part of any release.

Safety rules of the probe: every game API call is wrapped in `pcall`; no player, guild, BattleTag or Discord name is ever printed or stored (placeholders such as `<player 1>`, counts, types and field names only); it uses the test addon-message prefix `AzAcP` and never the real prefix `AzAccord`.

## Install

1. Copy `tools/local.example.ini` to `tools/local.ini` (git-ignored) and set `addons` to the `_forever_/Interface/AddOns` folder of your WoW installation.
2. Run:

```bash
python -I -X utf8 tools/install_probe.py
```

3. In game, `/reload` (or restart the client). The chat shows "AzAc Probe: loaded".

Run the installer again after every update of the probe, then `/reload`. The results in `AzAc_ProbeDB` survive the update.

## Commands

| Command | What it does |
|---|---|
| `/aacp` or `/aacp list` | Lists the checks S1–S11 with a short description and the last result |
| `/aacp run <id>` | Runs one check, for example `/aacp run S2` |
| `/aacp export` | Opens a movable frame with all results (and the logs) as plain text, already selected: press Ctrl+C, then paste it back |
| `/aacp reset` | Clears the stored results and logs |

Results are saved in `AzAc_ProbeDB.results[id]` as `{id, result, details, build, time}` where `result` is `pass`, `fail`, `info` or `todo`. A check that is not implemented yet records "not implemented yet". Later steps add more commands; the usage line printed by `/aacp help` always lists the ones your version has.

## What each step adds

| Step | Checks | File |
|---|---|---|
| M0.1 | skeleton, registry, export | `AzAc_Probe.lua` |

## M0.1: what to do in game

1. Install the probe (above) and `/reload`.
2. Run `/aacp`: you must see the eleven checks S1–S11, all "no result".
3. Run `/aacp run S1`, then `/aacp export`: the frame must show `S1 | todo | not implemented yet`. Close it with Escape.
4. Tell what you see in the report. If the addon does not load, enable "Load out of date AddOns" and send the exact error from the chat or from the Lua error frame.
