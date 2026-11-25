# M10 — Calendar, raids and the season roster

**Goal:**
- the guild's own season raid roster: every raider declares once per season what they play;
- event sign-ups on the game calendar, bench and composition;
- the sign-ups of the guild's Discord events (Raid-Helper) brought into the game by pasting the event's export;
- an availability map;
- PvP and world rallies;
- all of it working **with** the raid and loot addons the guild already uses, never against them.

Release: `v0.10.0`.

**Switched off until complete (2026-11-25).** M10 has its own switch, `season`, in `AzerothAccord/Core/Features.lua` (split from `raid` in M10.3, so that M10 can ship as `v0.10.0` before M11 is done). It covers M10.2 (detection, the choice of the season roster's source, the data set `guildcfg`), M10.3 (the data set `season`, the **Season** view, `/accord season`) and the steps that follow. Off, nothing of it is detected, shown, written, accepted or sent, as in `v0.9.0`. M10.10 turns it on. The M11 features read from FDCP (the **Raid** view, `/accord raid`, the *Loot* source, *Loot (FDCP)* on the member card) stay behind `raid` until M11 is complete; `raid` on turns `season` on too.

**Exit criterion:** in game:
- three members declare MS1, MS2 and OS for the season, and an officer sees the role counts and the gaps;
- a member signs up to an event as tentative from Accord, and the same answer shows in the game's calendar;
- an officer pastes a Raid-Helper event; the sign-ups are matched to members by their Discord name and copied into the game's calendar;
- with Finland Dragon Credit Points (FDCP) loaded and chosen as the source, the season roster shows FDCP's declarations and Accord asks for none.

**Owner's model (2026-11-19):** the season roster is not a sign-up and not an attendance register. It says what each raider plays for the whole season:
- **MS1**, required: the main spec, with its role (tank, healer, melee dps or ranged dps);
- **MS2**, optional: a second spec accepted for the whole season, if the raid needs it;
- **OS**, optional: a spec the player would like to play, which the raid will not ask for;
- **a free note**, for example availability; "not sure yet" is a valid answer.

The declaration holds for the season and changes only when a new season opens, because loot follows the declared spec. Each member edits only their own entry. Declaring is optional.

## Integration rules (owner, 2026-11-24)

A review of M10 and M11 against FDCP and the other loot addons that run on WoW Forever found that the first plan overlapped them:
- FDCP already keeps the season pool (MS1, MS2, OS, role, availability, locked for the season), the bench rotation and the attendance per boss;
- FDCP reads the sign-ups of the game's calendar and gives +1 credit to a raider who did not sign up, so a sign-up kept only inside Accord would cost that raider a credit;
- other loot addons on Forever keep their own raid rosters, reserves or attendance (the survey is in [M11](M11-loot-handbook.md#addons-on-wow-forever)).

So M10 and M11 follow these rules:
1. **One source for every datum.** The season roster, the lineup and bench, and the attendance belong to one addon per guild. The **source is a guild setting** chosen by an officer and synced to everyone, not a guess of each client, so that every member sees the same truth.
2. **The game calendar is the shared ground.** Events and sign-ups are read from and written to the game's calendar. Every addon (FDCP, the game's own interface) then sees the same answers. An event that lives only in Accord is a fallback for a client without the calendar, and is marked so.
3. **Integrations are read-only.** Accord never writes another addon's data and never reads another addon's saved variables directly: their layout changes without notice. It reads only a **documented, versioned public API**. Without one, Accord only detects the addon and points to it.
4. **Three levels.**
   - Level 0, detection: the addon is loaded, its version, who in the guild has it, a button or command to open it.
   - Level 1, reading: through the addon's public API, when one exists and its version is known.
   - Level 2, two-way exchange: never.
5. **If nothing is there, Accord offers it, except loot.** Without a raid addon chosen as source, Accord's own season roster, sign-ups, composition and availability work by themselves. A loot engine is never built (owner's decision of 2026-11-19, SPEC-10 Q6). The loot page names the addon to use instead.
6. **Only loot and raid-roster addons.** Integrations are considered only with addons whose job is loot or the raid roster. Other guild-management addons are out of scope: Accord plans no integration with them, does not detect them and does not read their data (owner, 2026-11-24).
7. **No attendance in Accord.** Attendance belongs to the raid or loot addon. FDCP keeps it per boss, for officers only. Accord keeps only the availability map, which counts no presence at raids.
8. **Discord only by pasting.** An addon has no internet access, so Accord never talks to Discord or to a bot. The guild's Raid-Helper events come in as the export an officer copies from the event and pastes in game, and go back as text to paste in Discord. No companion app or bot ([ADR 0001](../adr/0001-client-only-addon-guild-only-data.md)).
9. **Traffic is shared.** Accord and the other addons send on the same channels under the same server limits. The traffic budget of SPEC-09 counts the guild's other addons, and Accord stays quiet during boss fights as FDCP does.

### M10.1 — Specification
- Branch: `step/m10-1-spec`
- Scope:
  - write a new SPEC-14 ("Calendario, raid e roster della season"), in Italian, from the owner's model and the integration rules above. It covers:
    - the `season` data set and its trust rules;
    - the source setting and the providers;
    - events and sign-ups on the game calendar (`C_Calendar.EventSignUp` and the invite answers, checked against the Forever dump) with the fallback;
    - the Raid-Helper import: the export formats (JSON and CSV), the matching by Discord name, and copying into the game calendar;
    - bench and composition, the availability map and rallies.
  - ADR 0022 "Integrations with raid and loot addons: one source per datum, read-only, the game calendar shared".
  - A note in SPEC-09 on the shared traffic budget.
  - The FDCP API Accord needs, written as a request for the FDCP repository (SPEC-10 Q10).
  - *Done (2026-11-25):* [SPEC-14](../specs/SPEC-14-calendar-raids-season.md) (the data sets `season`, `raidev`, `avail` and `rally`, the trust rules SEA-01…SEA-06, the providers, the calendar calls checked against the Forever dump, which lacks the values of `Enum.CalendarStatus`, the Raid-Helper JSON of its API v4, silence during boss fights); ADR 0022 amended with points 11–15; SPEC-09 §7 on the shared traffic budget; the [FDCP API requests](../integrations/FDCP-API-requests.md) (F1–F8, none blocking); SPEC-10 Q20–Q25 and risks R15–R16, applied as proposed and accepted by the owner on 2026-11-25.
- Done when:
  - [x] SPEC-14 and ADR 0022 are linked from their indexes; open points go to SPEC-10; `tools/check_docs.py` passes.

### M10.2 — Detection of raid and loot addons
- Branch: `step/m10-2-detection`
- Spec: SPEC-14; ADR 0022
- Scope:
  - `Data/Integrations.lua`: a table of known addons with their folder name, kind (loot or raid roster) and level. The folder names are confirmed in game before they are trusted.
  - Each one is checked with `C_AddOns.IsAddOnLoaded` and its version is read with `C_AddOns.GetAddOnMetadata`, both through Compat.
  - Which known addons each member has loaded comes from the addon census of [M9.9](M9-action-center.md#m99--guild-addons); M10.2 adds no field of its own. *M9.9 added the read API `Integrations:Holders(id)` (the accounts with their version as far as the player may see them, the count and how many members share); it is behind both switches (`census`, and `raid` for whoever calls it).*
  - Officers see, per addon, who has it in the guild. *Done (2026-11-25): the Raid view ends with "Raid and loot addons in the guild": per known addon its detection on this client and, from the census, how many members have it with the versions; the names for officers and the Guild Master, the own entry for everybody (SPEC-14 §3.4).*
  - A provider interface (season roster, lineup, loot) with Accord's own provider and the FDCP provider. The FDCP provider stays at level 0 until FDCP publishes its API.
  - *Done (2026-11-24):* FDCP published its API the same day (FDCP M8-1, `API_VERSION` 1), so the FDCP provider reaches level 1 when that version is found. The **source setting** moved here from M10.3, because a provider is chosen by it: the record `sources` of the new data set `guildcfg` (`raid` = Accord or FDCP, `loot` = none or FDCP), written only by officers and synced to everyone ([ADR 0022](../adr/0022-integrations-with-raid-and-loot-addons.md), SPEC-03 §8). The officers choose it in the Raid view (M11.7). Who in the guild has each addon waits for the census of M9.9. *Since M9.9 the census is there (`Integrations:Holders`): what is left for M10 is to show it to officers in a view, behind `raid`.*
- Done when:
  - [x] Detection works with each known addon loaded, missing or disabled; an unknown version of the FDCP API falls back to level 0; nothing of another addon is ever written (`Tests/test_integrations.lua`).
- Real client: the folder names and versions of the known addons on Forever.

### M10.3 — Seasons, source and declarations
- Branch: `step/m10-3-season`
- Spec: SPEC-14
- Scope:
  - officers open a season (name, start date); the **source** of the season roster (Accord, or FDCP when it is detected) is the guild setting of M10.2;
  - with Accord as source, each raider writes their own entry (MS1 with its role, MS2, OS and a note, or "not sure yet"). The entry is locked until the next season. The data set is synced on `GUILD`, and only the author can write their entry;
  - with FDCP as source, Accord asks for no declaration. It shows FDCP's (level 1) or a button to open FDCP (level 0). *Done ahead in M11.7: the Raid view shows FDCP's pool and has the Open FDCP button.*
  - *Done (2026-11-25):* `Data/Specs.lua` (the trees and allowed roles of each base class), `Data/Season.lua` (the data set `season`: seasons `S:<n>` written by `Raid.WRITERS` = officers and the Guild Master, declarations `E:<n>:<GUID>` written only by the character's account; SEA-01…SEA-06 each from one constant: `Season.LOCK` 30 minutes, note always editable, "not sure yet" turned into a declaration once, `Season.KEEP` 3 previous seasons, one character per account; an entry that arrives before its season waits 10 minutes; it fills `Integrations.OWN`), the **Season** view (`UI/Season.lua`, `/accord season`: the source of the season roster, the season picker, an officer's *Open season* and *Close season*, the own declaration with a confirming second click, the list; with FDCP as source FDCP's pool or *Open FDCP*, reusing M11.7's lines; the section *Raid and loot addons in the guild*), the own declarations in *What I share*. The switch `raid` was split: the new `season` covers M10 (see above). `Tests/test_season.lua`.
- Done when:
  - [x] An entry cannot change inside a season; a new season starts with empty entries and keeps the old season readable; a forged entry from another author is refused; with FDCP as source, no Accord entry can be written.

### M10.4 — Season roster for officers
- Branch: `step/m10-4-season-view`
- Spec: SPEC-14
- Scope:
  - officers see the tank, healer, melee and ranged counts by MS1, the cover MS2 would add, and the gaps against a target composition they set, from whichever source is chosen;
  - every member sees the declarations;
  - export as Discord-ready text.
  - *Done (2026-11-25):* `Data/Composition.lua` (the target composition, the record `target` of `guildcfg`, written by `Raid.WRITERS`; the rows of Accord's season or of FDCP's pool in one shape; counts by MS1, MS2 cover, gaps; the accounts without a declaration), in the **Season** view the counts and the list of who is missing for everybody, the target editor and **Export** for officers (CSV and Discord text in the M8.6 box, `Data/Export.lua` kind `season`). With FDCP, inactive mains are not counted and a member's client shows no MS2 cover. `Tests/test_season_view.lua`.
- Done when:
  - [x] The counts match the declarations of the chosen source; members without an entry are listed separately, not as a gap.

### M10.5 — Events and sign-ups on the game calendar
- Branch: `step/m10-5-events`
- Spec: SPEC-14
- Scope:
  - guild events are read from the game calendar, whoever created them;
  - signing up from Accord writes the answer into the game calendar (accepted, tentative, declined), so FDCP and the game's own interface see it;
  - the role is preselected from MS1 or MS2;
  - only when the client has no usable calendar, events and sign-ups are kept in the addon, marked "not in the game calendar".
  - *Done (2026-11-25):* `Compat.Calendar` (every `C_Calendar` call; the values of `Enum.CalendarStatus`, missing from the dump, in the one constant `Compat.CALENDAR_STATUS`; the feature capability `calendar`), `Data/Calendar.lua` (the guild events from 7 days ago to 14 ahead, whoever created them, with the own answer; the answers of one event read only when it is chosen; one open event at a time, never with the game's calendar window shown, an action pending, in combat or during a boss, always closed again; the answer from a click with `EventSignUp`, `EventAvailable`, `EventTentative` or `EventDecline`, and the game's calendar opened instead when the client refuses the call from an addon; the role in `R:` preselected from MS1, MS2 when MS1's role is covered for the target and MS2's is not, or the class; the data set `raidev` with `R:`, `F:` and `A:`; events of the addon only when the calendar is missing, from `Raid.WRITERS`), the **Events** view (`UI/Events.lua`, `/accord events`), the own roles and answers in *What I share*, and the silence during a boss in `Net/Transport.lua` (SPEC-14 §10). `Tests/test_calendar.lua` with a fake `C_Calendar` (`Tests/mock/62_calendar.lua`).
- Done when:
  - [x] A sign-up made in Accord is the same answer in the game calendar; a sign-up made in the game's calendar shows in Accord; addon-only events exist only when the calendar is missing; a member without a season entry can still sign up.
- Real client: signing up and answering an invite on Forever; the calendar's status codes.

### M10.6 — Raid-Helper events from Discord
- Branch: `step/m10-6-raid-helper`
- Spec: SPEC-14; ADR 0022
- Scope: the owner's guild runs its raid sign-ups with the Raid-Helper bot in a Discord forum channel (2026-11-24).
  - **Import:** an officer copies the event's export (JSON, or CSV) from Raid-Helper and pastes it into a box in Accord. The parser reads the title, date and time, and each sign-up: Discord name, class and spec, role, and state (signed, tentative, late, bench, absence). It refuses text it does not understand with a clear message, and never runs anything from it.
  - **Matching:** each sign-up is matched to a guild member by Discord name, from the contacts of M2.5 and the guild's own Discord field. Members are grouped by account, so a sign-up reaches the right character. Names that match nobody go to a list for the officer to match by hand; a hand match is remembered for later events.
  - **In game:** the imported event is synced on `GUILD` with its date of import. Every member sees their own Discord state. Officers see:
    - the composition by role next to the season roster;
    - who signed up on Discord but not in the game calendar;
    - who signed up in the game calendar but not on Discord.
  - **Into the game calendar:** with one confirmation, the officer creates or updates the guild event (`C_Calendar.CreateGuildSignUpEvent`, `EventInvite`, `EventSetInviteStatus`, through Compat and only where the client allows an officer to set others' state), so the calendar, FDCP and Accord agree.
  - **Back to Discord:** the composition decided in game is exported as text to paste in Discord (with M10.4's export).
  - Accord never contacts Discord or Raid-Helper, and the import holds no data of people outside the guild beyond the unmatched names, which are dropped when the event is over.
- Tests: `Tests/test_raid_helper.lua`: JSON and CSV samples with invented names; every state; unknown fields ignored; broken and oversized text refused; matching by Discord name across alts; the calendar calls with and without permission.
  - *Done (2026-11-25):* `Data/RaidHelperText.lua` (the JSON and CSV reader written for Accord: 200 KB, depth 8, 200 sign-ups, texts of 64 characters, nothing run), `Data/RaidHelper.lua` (matching by hand match, Discord name and character name, grouped by account; the record `H:` of `raidev`, officers only; the unmatched names and hand matches in `GuildKey:Data().raidHelper`; the comparison with the game calendar and the season roster; the write into the calendar after a confirmation, one call at a time, 40 members per confirmation, never over an answer given in the game; the Action Center row), `UI/RaidHelperBox.lua` (paste, check, import), the officer part of the **Events** view, the export kind `event` back to Discord, the writing calls in `Compat.Calendar` and in `Tests/mock/62_calendar.lua`, the wiki page [Raid-Helper events](../wiki/Raid-Helper.md). The export format was **not** tried with a real event: the sign-up fields come from third-party descriptions (SPEC-14 §6.1, §13).
- Done when:
  - [x] A pasted event shows the same sign-ups in Accord as on Discord; matched sign-ups reach the game calendar after the officer confirms; the wiki has a page on bringing Raid-Helper events into the game, in English and Italian.
- Real client: the current export format of Raid-Helper (checked again in M10.1), and whether an officer can set the invite state of other members in a guild event on Forever.

### M10.7 — Bench and composition
- Branch: `step/m10-7-composition`
- Spec: SPEC-14
- Scope:
  - with Accord as source: officers place signed-up players in the raid or on the bench, and see the composition against the target. MS2 is offered when a role is short;
  - with FDCP as source: the night's lineup and bench are FDCP's. Accord shows them read-only (level 1) or points to FDCP (level 0), and offers no bench of its own. *Done ahead in M11.7 (the Raid view).*
  - *Done (2026-11-25):* the record `C:<event>` of `raidev` (officers and the Guild Master only; `Data/Composition.lua`), in the **Events** view the own place, the raid and the bench for everybody and, for officers, who signed up and is not placed (game calendar and matched Raid-Helper sign-ups), the roles against the target, the MS2 offers and **To raid** / **To bench** / **Remove**; **Write to calendar** after a confirmation writes confirmed and standby with M10.6's write, so never over an answer given in the game (SPEC-10 Q25), at most 40 per confirmation; the line-up in the Discord export. With FDCP as the source nothing is written, accepted or shown, and the view shows FDCP's night where it gives one. `Tests/test_composition.lua`.
- Done when:
  - [x] Only officers can change the composition; the members see where they are placed; with FDCP as source, no composition can be written in Accord.

### M10.8 — Availability map
- Branch: `step/m10-8-availability`
- Spec: SPEC-14
- Scope:
  - when members usually play, from their presence online over time, shown by day and hour;
  - **no attendance**: Accord counts no presence at raids (integration rule 7).
  - *Done (2026-11-26):* `Data/Availability.lua` (only the minutes online of the account, per hour of the realm's week, 8 weeks, `AzerothAccordDB.avail`; 4 levels in 42 bytes; the data set `avail`, published at most once a week, once a day in the first week; the switch *Share when I usually play*, which withdraws the map while the count goes on; counts for everybody, names for officers and the own entry; FDCP's declared days apart, for officers), the **Availability** view (`UI/Availability.lua`, `/accord availability`), the wiki page [Availability](../wiki/Availability.md), `Tests/test_availability.lua`. Traffic (SPEC-14 §11): inside the budget in a guild in step; **over it in the first exchange** (530 B/min average against 450), left to the owner (SPEC-10 Q26, R17) before M10.10.
- Done when:
  - [x] The map is built from online presence only; nothing about raid attendance is recorded or sent.

### M10.9 — PvP and world rallies
- Branch: `step/m10-9-rallies`
- Spec: SPEC-14
- Scope: a quick call with a meeting point in text and a start time, answered with "coming" or "not coming". Exact positions are never shared.
- Done when:
  - [ ] A rally expires by itself; no coordinates are sent.

### M10.10 — In-game check and release
- Branch: `step/m10-10-check`
- Scope: `docs/checklists/M10.md` (with a guild that has FDCP and one without, and a Raid-Helper event imported) and the README status. Turn the switch `season` on (`raid` stays off until M11). The owner releases `v0.10.0`.
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.10.0`.
