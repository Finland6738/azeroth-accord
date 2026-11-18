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
| `/aacp note <id> <text>` | Stores a free-text observation (for example `/aacp note S1 tab looks the same as the others`); never write player or guild names in it |
| `/aacp tab [on\|off\|dump\|taint]` | S1: creates the test tab in the guild window (`on` is the default), hides it (`off`), stores the window structure (`dump`) or the taint check (`taint`) |
| `/aacp reset` | Clears the stored results and logs |

Results are saved in `AzAc_ProbeDB.results[id]` as `{id, result, details, build, time}` where `result` is `pass`, `fail`, `info` or `todo`. A check that is not implemented yet records "not implemented yet". Later steps add more commands; the usage line printed by `/aacp help` always lists the ones your version has.

## What each step adds

| Step | Checks | File |
|---|---|---|
| M0.1 | skeleton, registry, export | `AzAc_Probe.lua` |
| M0.2 | S1 | `Checks_GuildTab.lua` |

## M0.1: what to do in game

1. Install the probe (above) and `/reload`.
2. Run `/aacp`: you must see the eleven checks S1–S11, all "no result".
3. Run `/aacp run S1`, then `/aacp export`: the frame must show `S1 | todo | not implemented yet`. Close it with Escape.
4. Tell what you see in the report. If the addon does not load, enable "Load out of date AddOns" and send the exact error from the chat or from the Lua error frame.

## M0.2: what to do in game (S1, the Accord tab)

The probe never calls `SetDisplayMode` and never replaces a Blizzard function: it only observes with hooks. It logs `ADDON_ACTION_BLOCKED` and `ADDON_ACTION_FORBIDDEN` from login on (also in chat, with the addon and function names).

Use a guilded character, ideally one that can promote and invite (an officer).

1. Install the new version, `/reload`, open the guild window once (default key `J`), then run `/aacp tab`. A test tab must appear **below the four Blizzard tabs**: note how it looks (size, icon, position) with `/aacp note S1 <text>`.
2. Run `/aacp tab dump` and `/aacp tab taint`: they store the frame structure (tab names, anchors, display modes, `GuildMemberDetailFrame`) and the `issecurevariable` results.
3. Click the Accord tab: a dark test panel must cover the content. Click each Blizzard tab (Chat, Roster, Guild Benefits, Guild Info): the panel must disappear and the Blizzard content must work. Click Accord again.
4. With the Accord tab used at least once in this session, do the **protected actions in the Blizzard UI**, one at a time: promote or demote a member, invite a player to the guild, edit a member note and an officer note, change a rank, (as an officer) kick or change settings only if you are happy to. After each, check that it worked and whether chat showed "action blocked" / "forbidden" or the Lua error frame appeared.
5. Enter combat (a training dummy is enough) with the guild window open and the tab visible, then leave combat. Open the window during combat too.
6. Switch the window to its minimized size (the button at the top) with the Accord tab selected and not selected: note whether the tab and the panel behave.
7. `/reload` with the window open: the tab is recreated automatically; check it appears and works. Also select another community (if you have one): the tab must disappear and come back with the guild.
8. Run `/aacp run S1`, then `/aacp export`, and send the text back. Add your notes with `/aacp note S1 ...` before exporting.

What the export contains for S1: the result line (tab created, template used, number of blocked and forbidden actions, number of tainted keys) and the logs `S1`, `S1 structure`, `S1 taint`, `S1 blocked` and `notes`.
