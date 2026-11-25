# Requests to FDCP's public API (from Azeroth Accord M10)

A request document for the repository of **Finland Dragon Credit Points (FDCP)**, written by Azeroth Accord in its step M10.1 (2026-11-25) and answering [SPEC-10 Q10](../specs/SPEC-10-risks-open-questions.md). It is meant to be carried to the FDCP repository as an issue or a roadmap step by the owner. **Accord never changes the FDCP repository**; FDCP decides what to add, when, and how.

## Where things stand

FDCP published its read-only, versioned API on 2026-11-24 (FDCP step M8-1, FDCP ADR 0009): the global table `FinlandDragonCreditPointsAPI` with `API_VERSION` 1. Accord reads it in M10.2 and M11.7 ([ADR 0022](../adr/0022-integrations-with-raid-and-loot-addons.md)): `IsReady`, `GetVersion`, `GetSource`, `GetSeason`, `GetPool`, `GetMember`, `GetCredits`, `GetCreditList`, `GetNight`, `GetRules`, and the callbacks `READY`, `SEASON_CHANGED`, `POOL_CHANGED`, `CREDITS_CHANGED`, `NIGHT_CHANGED`, `RULES_CHANGED`. Accord reads level 1 only when `API_VERSION == 1`; any other version falls back to level 0 (detection and the `/fdcp` command).

M10 ([SPEC-14](../specs/SPEC-14-calendar-raids-season.md)) lets the guild's officers choose FDCP as the source of the season roster and of the night's lineup and bench. Then Accord shows FDCP's data and asks for nothing of its own. The requests below are what would let Accord show the same thing FDCP shows, on every client. **None of them blocks M10**: without them Accord says in one line what it cannot show (for example "FDCP shows MS2 and OS to officers only"), never an empty list.

## Ground rules Accord asks FDCP to keep

1. **Additive changes keep `API_VERSION` 1.** A new function or a new field in a returned table does not break Accord, which drops the fields it does not know. Please raise `API_VERSION` only when a field changes meaning or type, or a function is removed; and say this rule in FDCP's API page.
2. **Attendance stays unexposed.** Accord keeps no attendance and does not want any (M10 integration rule 7). Nothing below asks for attendance, absences, the roster note, the audit, the log or the council.
3. **Nothing is two-way.** Accord never writes into FDCP and does not ask for any setter.

## Requests

Ordered by how much they help M10. Each says what Accord would do with it.

| # | Request | Why Accord needs it | Today, without it |
|---|---|---|---|
| F1 | **The season roster on a member's client with `ms2` and `os`** (the declared specs of the playing mains in the credits snapshot) | M10.4: "every member sees the declarations" of the chosen source. A member's client today has the pool without `ms2`, `os`, `twin` and `avail` | members see MS1 and role only; the line says the rest is for officers |
| F2 | **The night's lineup on a member's client**: `GetNight()` with `raid` and `bench` (names only) of the current or next night | M10.7: "the members see where they are placed". Today `GetNight()` is nil on a member's client | members are pointed to FDCP |
| F3 | **The calendar event of a night**: `night.eventID` (the game calendar's `eventID` FDCP linked the night to), or nil | Accord shows events by their calendar `eventID` (SPEC-14 §5.2); with it the night's lineup appears on the right event in Accord's Events view | Accord matches the night to an event by date only, and shows a mismatch when the day has two raid events |
| F4 | **Whether a missing calendar sign-up costs credits**: a field in `GetRules()`, for example `signupPenalty = { amount }` or nil | Accord tells raiders to sign up in the game calendar, and warns on an event that lives only in Accord (SPEC-14 §5.4); with the actual rule it can say how much is at stake | a general warning that FDCP reads only the game calendar |
| F5 | **The guild's rules on a member's client** (`GetRules().source = "GUILD"` from the snapshot) | the rules summary beside the loot page (M11.6) should be the guild's, not the preset's defaults | the summary says it shows the Patto preset's defaults |
| F6 | **A function to open FDCP's window**: `Open()` (optionally `Open("pool")`, `Open("night")`) | Accord's *Open FDCP* button; today it runs the `/fdcp` slash command, which may change | the slash command |
| F7 | **The documented format of dates**: `night.date` and `season.updated` (and `season.start`, if added: the day the season opened) | Accord shows the season's dates and links a night to a calendar day | Accord shows them only when they look like a day number or a server time |
| F8 | **The season's lock state**: whether declarations are locked for the season (`season.locked`) | SPEC-14 §4: Accord tells members whether they can still change a declaration in FDCP | Accord says nothing about locking when FDCP is the source |

## What Accord will do when FDCP adds them

Each one is a small step in Accord, with tests against a fake FDCP table (`Tests/test_integrations.lua`): read the new field only if it is there and of the right type, otherwise keep today's behaviour. No Accord release waits for FDCP.

## Not requested

- Attendance, absences and anything officer-only by FDCP's own rules.
- A way to write declarations, sign-ups or lineups into FDCP.
- FDCP's SavedVariables layout: Accord never reads them.
- Anything about Raid-Helper or Discord: Accord brings those events into the game calendar itself, and FDCP reads the calendar as it does today.
