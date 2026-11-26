# Season roster

*Italiano: [[Roster della season|Season-Roster-it]]*

> **From `v0.10.0`**, the next release: it is complete in the code and not published yet; no earlier version has it. Nothing on this page has been checked in the real game. What follows describes how it should work.

The season roster is **not a sign-up and not an attendance register**. It says what each raider plays for the whole season, because loot follows the declared spec:

- **MS1**, required: your main spec, with its role (tank, healer, melee dps or ranged dps);
- **MS2**, optional: a second spec you accept to play for the whole season, if the raid needs it;
- **OS**, optional: a spec you would like to play, which the raid will not ask for;
- **a note**, for example when you can play; or **Not sure yet**.

Declaring is optional.

## The Season view

Open it with its tab or `/accord season`.

- **At the top**: the **source** of the season roster (*Accord* or *FDCP*), the season picker and **Open FDCP** while Finland Dragon Credit Points is loaded on your computer. The source is one choice for the whole guild: officers and the Guild Master change it with a click, everybody else sees it locked (see [[Raid and loot addons|Raid-and-Loot-Addons]]).
- **Officers and the Guild Master** write a name and press **Open season**: the season starts today, and the season open until then is closed. **Close season** closes the current one without opening another. Nobody else opens or closes a season.
- **Your declaration**: choose MS1 and its role, MS2 and OS (or *none*), write a note if you want, and press **Declare**; or press **Not sure yet**. A second click confirms, because the declaration holds for the season.
- **The list**: every declaration of the chosen season, with class, MS1, MS2, OS and the note.

## Roles, gaps and who is missing

For the current season, everybody sees above the list:

- **Roles by MS1**: how many raiders are tanks, healers, melee and ranged dps, and beside each how many **MS2 would add** (raiders whose MS2 is in that role and whose MS1 is in another one). OS never counts.
- **Gaps**: when the officers have set a target composition, how many of each role are **missing** and how many of those MS2 would cover. Each role is counted on its own: a raider who moves to MS2 leaves their MS1 role.
- **Not sure yet** answers are listed apart and count in no role.
- **Without a declaration**: below the list, the members who have not declared, one name per account (an account that declared with one character is not listed for its alts). They are never counted as a gap, with or without Accord.

An older season in the picker shows its declarations only, without counts.

## The target composition

Officers and the Guild Master choose the raid size (10, 20, 25 or 40), write how many tanks, healers, melee and ranged dps they want (an empty field means 0; the sum cannot be over the size) and press **Set target**. The target is one for the whole guild, reaches every member and stays until an officer changes it, also with FDCP as the source.

## Export

Officers and the Guild Master press **Export** to get the declarations of the shown season as **CSV** (for a spreadsheet) or as text for **Discord** (long ones are split into messages). The text is selected: press Ctrl+C. It leaves the game, as the warning above it says. Members without a declaration are not in the export.

## The rules

- **Only your own entry.** Each raider writes only their own declaration. Nobody writes or changes someone else's, officers included; a declaration forged for another player is refused by every Accord.
- **Locked for the season.** For **30 minutes** after your first declaration you can correct a mistake. Then MS1, MS2 and OS stay locked until the next season. The **note** can always change (*Save note*). *Not sure yet* can become a real declaration **once**.
- **One character per account.** Your account declares one character per season. If two of your characters' declarations reach the guild, everybody sees the older one.
- **A new season starts empty.** Nothing is copied from the previous season. **Older seasons stay readable** in the season picker: the current season and the 3 before it are kept.
- **Shared with the guild.** Seasons and declarations reach every member with Accord, like the other guild data, and your declaration is listed in *What I share* (see [[Privacy and Data|Privacy-and-Data]]).

## With FDCP as the source

When the officers choose **FDCP** for the season roster, Accord asks for no declaration and accepts none from you: you declare in FDCP. The view shows FDCP's season and pool, read from FDCP's public interface, or why there is nothing and the **Open FDCP** button. The counts, the gaps, the list of who is missing and the export then come from FDCP's pool: its **inactive** mains are not counted, a main covers its alts, and because FDCP shows MS2 and OS to officers only, a member sees the counts by MS1 without the MS2 cover. Declarations already kept in Accord are hidden, not deleted: if the officers go back to Accord they show again.

At the bottom, **Raid and loot addons in the guild** shows which of these addons the members have, as described in [[Raid and loot addons|Raid-and-Loot-Addons]].
