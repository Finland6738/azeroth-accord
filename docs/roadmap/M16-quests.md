# M16 — Guild quests

**Goal:** a **Quest** tab. It lists the quests active in the quest logs of every guild character, online and offline, with one row per quest. Each row shows the quest's ideal level range and who has it. The owner asked for it on 2026-11-26 and answered the design questions the same day (below). After M16 comes [M17](M17-professions.md), the professions assistant, and then `v1.0.0` ([ADR 0020](../adr/0020-one-version-per-milestone.md), update of 2026-11-27).

**Switched off until complete.** Everything of M16 ships behind a new switch `quests` in `AzerothAccord/Core/Features.lua`. The last step turns it on.

**Exit criterion:** in game, a quest accepted by a member appears in another member's **Quest** tab, with that character in its panel. When the member completes or abandons it, it disappears from the tab. A character who logs out stays listed with the quests in their log.

## Owner's decisions (2026-11-26)

- **The list.**
  - One row per quest ID, with the quest's name and level, and its **ideal range**: the quest level ±2, shown as "Lv 24, ideal 22–26".
  - Icons for **elite** quests and for the **group size** the game suggests.
  - The count column counts **characters**, and the list is sorted by it by default.
- **Colours.** Accord uses its own table, not the game's, with d = the player's level minus the quest's level:

  | d | Colour |
  |---|---|
  | above +6 | gray |
  | +3 to +6 | green |
  | 0 to +2 | green |
  | −1, −2 | yellow |
  | −3, −4 | orange |
  | −5 and below | red (the character is too low) |

  The owner did not name +3 to +6; it is read as green. The table is one constant.
- **Which quests.**
  - In: daily quests and quests ready to turn in, which are marked.
  - Out: the log's headers and hidden or internal quests.
  - An optional filter hides the quests that are gray for the player.
- **The panel on the right**, like the member card. It has one row per character that has the quest:
  - name, level, class, online or offline, and the zone if online;
  - "ready to turn in", and the age of the data;
  - **Whisper** and **Invite** buttons.

  Objective progress (5/8) comes later, not in M16.
- **Filters:**
  - search by name;
  - grouping by zone, as in the game's quest log;
  - only online, only quests I have too, elite or group, and suited to my level.
- **Privacy.**
  - Sharing is **on by default** for everybody. It has an off switch in Settings and in *What I share*, and switching it off withdraws what was shared.
  - **Everybody sees every name.**
- **Always in sync.**
  - Accepting, completing or abandoning a quest is sent at once, and completed quests disappear.
  - Every client relays the records, so offline characters stay visible. A log cannot change while its character is offline, so the record stays accurate.
  - A character who leaves the guild disappears.
- **Titles.**
  - English by default, with a switch to Italian.
  - The titles come from an English and Italian table included in Accord, built from an open database whose licence is compatible with GPL-3. Its source and licence are proposed to the owner in M16.1, before use.
  - A quest missing from the table shows the title the client knows, or else the sender's.
- Only characters whose players have Accord are known. A member without it is never shown as missing.

## M16.1 — Specification
- Branch: `step/m16-1-spec`
- Scope: write a new SPEC-20 ("Missioni della gilda"), in Italian. It covers:
  - the data set: one record per character with its quests (id, level, suggested group, elite, daily, ready to turn in, zone header), its size limit, when it goes out, and the relay that keeps offline characters;
  - the traffic in the shared budget of SPEC-09 §7, measured in the simulator;
  - the `C_QuestLog` calls checked against the Forever API dump, with what the client cannot give: a quest's minimum level is not in the dump;
  - the colour table and the ideal range;
  - the view, the panel and the filters;
  - the share switch and *What I share*;
  - the title table: its source, its licence and its size. The source and licence go to the owner as a SPEC-10 question before M16.3.
  - New SPEC-10 questions for what is still open.
- Done when:
  - [ ] SPEC-20 is linked from the spec index; the title source is an open SPEC-10 question or answered; `tools/check_docs.py` passes.

## M16.2 — Quest log data
- Branch: `step/m16-2-quest-data`
- Spec: SPEC-20
- Scope:
  - read the character's own quest log (headers, hidden and internal quests left out);
  - publish its record when the log changes and after login;
  - relay the records of others, and remove the character when it leaves the guild;
  - honour the share switch, with a `del` record when it is switched off.
- Done when:
  - [ ] A completed or abandoned quest leaves the record at the next publication, and a forged record for another account's character is refused.

## M16.3 — Title table
- Branch: `step/m16-3-titles`
- Spec: SPEC-20; the owner's answer on the source
- Scope:
  - a tool in `tools/` that builds the English and Italian title table from the approved source, with its licence noted in the credits;
  - the switch between English and Italian titles;
  - the fallback to the client's title, then the sender's.
- Done when:
  - [ ] The table is rebuilt by the tool, not edited by hand; a quest missing from it still shows a title.

## M16.4 — Quest view
- Branch: `step/m16-4-quest-view`
- Spec: SPEC-20; SPEC-04
- Scope:
  - the **Quest** tab and `/accord quests`;
  - one row per quest, with the name, the level, the ideal range, the colour, the elite and group icons, the count of characters, and the "ready to turn in" mark;
  - the filters, the search and the grouping by zone.
- Done when:
  - [ ] Two characters with the same quest make one row counting 2; the colour follows the table for the player's level.

## M16.5 — Holders panel
- Branch: `step/m16-5-holders`
- Spec: SPEC-20
- Scope:
  - the panel on the right with one row per character, as in the owner's decisions;
  - **Whisper** and **Invite**;
  - **Find a group for this quest**, which opens the guild group finder of M9 with the kind *quest* and the quest's name filled in.
- Done when:
  - [ ] Offline characters show the age of their data; Invite is offered only for online characters.

## M16.6 — In-game check and `v0.16.0`
- Branch: `step/m16-6-release`
- Scope:
  - `docs/checklists/M16.md`, and the switch `quests` turned on;
  - the wiki and both READMEs up to date.

  The full release check, the full tests and `v1.0.0` moved to M17.7, then to M18.7 (2026-11-27).
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.16.0`.
