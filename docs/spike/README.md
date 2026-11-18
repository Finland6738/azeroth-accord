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
| `/aacp btag [self\|friend]` | S8: `self` prints the shape of your own BattleTag (never the value); `friend` sends a **real** BattleTag friend request to the guild member you are targeting (a volunteer) |
| `/aacp recipes guild [n]` | S3: asks the native guild recipe directory about up to `n` (default 3) online guildmates' professions, waits 6 seconds and reads it back (`<player n>` placeholders only) |
| `/aacp recipes own` | S4: scans your own recipes now (ids, learned count, milliseconds) and stores it |
| `/aacp recipes open <skillLineID>` | S4: tries `C_TradeSkillUI.OpenTradeSkill` from the addon (may be blocked: that is an answer) |
| `/aacp recipes auto on\|off` | S4: scan automatically when a profession window opens (on after `/aacp run S4`) |
| `/aacp ping guild\|officer` | S5: sends one small test message on that distribution with the test prefix `AzAcP` and records the result code |
| `/aacp pong [on\|off]` | S5/S6: with it ON, this client answers every single ping it receives from another client, so the sender sees the round trip |
| `/aacp burst guild\|officer <n> <gapSeconds> [bytes]` | S5: sends `n` (max 200) messages of about `bytes` (default 200, max 255) with a fixed gap, records result codes and own echoes; `/aacp burst stop` aborts |
| `/aacp msgsize guild\|officer` | S5: sends messages of 100 to 300 bytes and records which sizes are accepted |
| `/aacp snapshot <label>` | S5: stores the lockdown state (chat messaging lockdown, addon restrictions, combat, instance, encounter, battleground) and the result of one test GUILD send, tagged with your label |
| `/aacp msgs` | S5/S6: prints the sent, result-code and received counters |
| `/aacp whisper <name>` | S6: sends one addon WHISPER to a character; the name is used once and never stored |
| `/aacp group [<label>]` | S7: scans the current party or raid (counts only: readable and secret GUIDs, `UnitIsInMyGuild`, `GetRaidRosterInfo` fields, milliseconds) and stores it under your label |
| `/aacp group watch on\|off` | S7: scans automatically 0, 1 and 3 seconds after every group roster change and at boss start and end (on after `/aacp run S7`) |
| `/aacp bank [presence]` | S9: with the guild vault open, reads every viewable tab (permissions, filled slots, item logs) and the money and money log, one tab every 2.5 seconds, tab names replaced by `<tab n>`; `presence` only lists which vault functions exist |
| `/aacp perf [sizes...]` | S11: times the roster operations and the social index and group map on generated data, for example `/aacp perf 500 1000 2000` (default 500 and 1000, at most 3000) |
| `/aacp reset` | Clears the stored results and logs |

Results are saved in `AzAc_ProbeDB.results[id]` as `{id, result, details, build, time}` where `result` is `pass`, `fail`, `info` or `todo`. A check that is not implemented yet records "not implemented yet". Later steps add more commands; the usage line printed by `/aacp help` always lists the ones your version has.

## What each step adds

| Step | Checks | File |
|---|---|---|
| M0.1 | skeleton, registry, export | `AzAc_Probe.lua` |
| M0.2 | S1 | `Checks_GuildTab.lua` |
| M0.3 | S2, S8, S10 | `Checks_Roster.lua` |
| M0.4 | S3, S4 | `Checks_Recipes.lua` |
| M0.5 | S5, S6 | `Checks_Messaging.lua` |
| M0.6 | S7 | `Checks_Group.lua` |
| M0.7 | S9, S11 | `Checks_BankPerf.lua` |

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

## M0.3: what to do in game (S2, S8, S10)

Nothing printed or stored contains a name: only counts of filled values, types and field names. Characters are told apart by a short hash of their GUID, realms by a hash of their name. **Do not run `/aacp reset` between the S10 characters**: it clears the stamps.

**S2, the guild roster.** With a guilded character (the bigger the guild the better, with some offline members), run `/aacp run S2`. The probe asks the server for the roster, reads every member through `C_Club.GetClubMembers` / `GetMemberInfo`, waits about 5 seconds, reads again and prints one summary line. The full table (every field, how many members have it filled, split by online and offline, plus the shape of `discordInfo`, how many members share a `bnetAccountId`, and how many names carry a realm part) goes to the `S2 fields` log. If the line says "no guild club id", open the guild window once and retry. Repeat as an officer and as a plain member if you can (notes and some fields may differ).

**S8, BattleTag.** Run `/aacp run S8` (or `/aacp btag self`): it tells which of `BNet_GetBattleTagSelf`, `BNGetInfo` and `C_BattleNet.GetAccountInfoByGUID` gives your own BattleTag and in which format. Then, with a **volunteer** guildmate (who agrees to receive a real friend request): target their character and run `/aacp btag friend`. Ask them whether the request arrived and whether it shows a BattleTag, and write it with `/aacp note S8 <text>` (for example "request arrived, shows BattleTag, accepted/declined"). Cancel the friendship afterwards if you do not want it.

**S10, account-wide SavedVariables and realms.**

1. On your first character run `/aacp run S2` (to get the realm parts of the member names) and then `/aacp run S10`. Log out.
2. On a **second character of the same account on the same realm**, run `/aacp run S10`: it must report "seen from earlier characters: 1". That is the account-wide SavedVariables answer.
3. If you have a character on **another realm** (or a connected realm) on the same account, run it there too: it must see the others and report the other realm.
4. Run `/aacp export` on the last character and send the text back. Say whether your realm is connected to others.

## M0.4: what to do in game (S3, S4)

The probe tries the functions the specification names (`GetGuildMemberRecipes`, `GetGuildTradeSkillInfo`, `GetNumGuildTradeSkill`, `QueryGuildMembersForRecipe`, `GetAllRecipeIDs`, ...) in the global table and in `C_GuildInfo`, `C_TradeSkillUI` and `C_Club`, and says where each one lives or that it is missing: the Forever API dump documents only `C_GuildInfo.QueryGuildMemberRecipes`, `QueryGuildMembersForRecipe`, `C_TradeSkillUI.IsGuildTradeSkillsEnabled` and the event `GUILD_RECIPE_KNOWN_BY_MEMBERS`, so a "missing" is itself an answer.

**S3, the guild recipe directory.** With a guilded character and at least one **online guildmate with a profession who has opened their profession window this session** (ask them to open each profession once):

1. `/aacp run S3` prints the API presence and `IsGuildTradeSkillsEnabled()`.
2. `/aacp recipes guild 3` queries up to three online guildmates, counts `GUILD_RECIPE_KNOWN_BY_MEMBERS` events (and the delay), and after 6 seconds tries every getter with a few argument shapes, describing what it returns (types and counts, no names). Run it again after the guildmates open their profession windows, and once with the guild window closed and once open.
3. `/aacp export` and send it back: the `S3 guild recipes` log has everything.

**S4, own recipes.** With a character that has professions:

1. With **no profession window open**, run `/aacp run S4`: it logs the API presence and a scan with the window closed.
2. Open each of your profession windows (and the other tabs of the window, and then close it): every opening is scanned automatically (up to 6 scans per opening) and logged with the number of recipe ids, how many are learned, and the milliseconds the scan took. Close the window and run `/aacp recipes own` again: do you still get recipes?
3. Optionally try `/aacp recipes open <skillLineID>` (a profession id printed in the logs) to see whether an addon may open the window.
4. `/aacp export`: the `S4 own recipes` log has the results.

Tell, per profession, which of the two sources worked (native directory for others, own scan for yourself) and whether the window had to be open.

## M0.5: what to do in game (S5, S6), two clients

The probe registers and sends **only** the test prefix `AzAcP`, never `AzAccord`. Senders are only compared with your own name ("self" or "other"); nothing with a name is stored. You need two clients, ideally an **officer** and a **plain member** (two accounts or a second player running the probe), both with the new probe installed and `/aacp pong on` on the receiving one.

**S5, GUILD and OFFICER.**

1. On both clients `/aacp run S5` (registers the prefix and prints the starting state), and on the receiver `/aacp pong on`.
2. Officer: `/aacp ping guild`, then `/aacp ping officer`. Read the result code in chat. On the plain member run `/aacp msgs`: did it receive on `GUILD`? On `OFFICER` (it should not, if it cannot read officer chat)? Did the officer get PONG replies?
3. `/aacp msgsize guild` and `/aacp msgsize officer`: which payload sizes are accepted (the codes 255 and 256 matter).
4. Rate: `/aacp burst guild 30 1`, then gaps 0.5, 0.25, 0.1 and 0 (wait for the end line each time: "burst ... sent N, codes {...}; own echoes received M"). Stop increasing as soon as codes other than `Success` appear or echoes are missing. Repeat on `officer`. On the receiver, `/aacp export` lists each received run with its missing message count.
5. **Lockdown.** Take a snapshot in each situation with `/aacp snapshot <label>`: `outside` (open world, out of combat), `combat` (in combat, a dummy is fine), `dungeon` (inside a dungeon instance, before the boss), `boss` (during a boss encounter), `battleground` (during a match), `raid` and `mythic` if you do them. The probe also logs the lockdown state automatically on every `ADDON_RESTRICTION_STATE_CHANGED`, encounter start and end, combat start and end and loading screen. Stop doing bursts while locked down.
6. `/aacp run S5`, then `/aacp export` on both clients and send the texts back.

**S6, addon WHISPER between guildmates.** With `/aacp pong on` on the receiving client: sender runs `/aacp whisper <character name>` of a guildmate (online, same faction). Check the result code, then `/aacp msgs` on the receiver ("received: WHISPER other"). Repeat with a **low-level** character as sender and as receiver (a fresh level 1 in the guild is ideal) and with a guildmate on a connected realm if you have one. Then `/aacp run S6` and `/aacp export`.

## M0.6: what to do in game (S7, group and raid)

No name and no GUID is stored: only counts (readable and secret GUIDs, guild flags) and the shape of the returned fields. Secret values are tested with `issecretvalue` and never compared or printed. Ideally do it with **guildmates in the group** (some of them in the guild, one not, if possible).

1. Solo, `/aacp run S7`: it scans yourself, lists missing functions (`GetRaidRosterInfo`, `IsInRaid`, ... are not in the Forever dump, so the probe checks them at run time) and turns the automatic watching ON.
2. **Party** (2–5 players, with guildmates): `/aacp group party`. Check the numbers: how many GUIDs are readable, how many `UnitIsInMyGuild` are true, how many group members match a guild-roster GUID. While players join and leave, the `S7 group` log records `GROUP_ROSTER_UPDATE` with the gap between events and the state 0, 1 and 3 seconds later (how long until the data is valid).
3. **Raid** (convert the party to a raid, or join one): `/aacp group raid`: same, plus `GetRaidRosterInfo` rows, field shape and cost in milliseconds for a big raid.
4. **Instance** (dungeon or raid, not Mythic+ unless you do it): `/aacp group dungeon` on entering, and again right after a boss pull and after the kill (watching also logs `ENCOUNTER_START` / `ENCOUNTER_END` by itself). Are the GUIDs or `UnitIsInMyGuild` secret there?
5. If you can, repeat inside a battleground and during a Mythic+ run (`/aacp group bg`, `/aacp group mplus`).
6. `/aacp export` and send it back (the `S7 group` log has every scan).

## M0.7: what to do in game (S9, S11)

**S9, the guild bank.** The Forever API dump documents only `C_GuildBank.IsGuildBankEnabled` and the vault events; the classic functions (`GetNumGuildBankTabs`, `GetGuildBankTabInfo`, `GetGuildBankItemInfo`, `QueryGuildBankLog`, ...) are looked up at run time. Tab names, log names and item links are never stored (tabs become `<tab n>`, logs keep only the entry shape and the time fields as returned). Do it twice: as a **plain member** and as an **officer** (two characters, or the same one with different ranks).

1. `/aacp run S9` anywhere: role, API presence and which functions are missing.
2. Go to the guild vault and open it (the probe logs `GUILDBANKFRAME_OPENED` and every later vault event with its delay in milliseconds).
3. Run `/aacp bank` and wait for the final line (about 3 seconds per viewable tab). The `S9 bank` log has, for each tab: viewable, can deposit, withdrawals allowed and remaining; the filled slots; the log size, first and last entry shape and the time fields (are they "years, months, days, hours ago"?); the money and money log. The `S9 bank events` log has the event timing.
4. Click a few tabs yourself while the window is open, then run `/aacp bank` again: do the numbers change? Do the events fire again?
5. `/aacp export` on each character and send the texts back, saying which one was the member and which the officer.

**S11, performance.** Anywhere, out of combat: `/aacp run S11` (500 members), then `/aacp perf 500 1000 2000`. The game may freeze for a moment on the larger sizes; that is the measurement. It runs only on generated data. The `S11 perf` log has, per size: building, sorting by three columns, filtering, formatting 30 visible rows, grouping alts by account, the social index for all accounts (and per account), the label propagation with its modularity, the serialization of the pair-day data and the memory used. Send `/aacp export`.
