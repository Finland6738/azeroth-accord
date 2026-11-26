# Raid-Helper events

*Italiano: [[Eventi di Raid-Helper|Raid-Helper-it]]*

> **From `v0.10.0`**: no earlier version has it. Nothing on this page has been checked in the real game, and Raid-Helper's export has not been tried with a real event yet. What follows describes how it should work.

Many guilds collect raid sign-ups with the **Raid-Helper** bot on Discord. Accord can bring such an event into the game: an officer copies the event's export and pastes it. Accord **never contacts Discord or Raid-Helper**: an addon has no internet access, and nothing leaves your computer for them.

## 1. Copy the export

- **JSON** (recommended): open `https://raid-helper.xyz/api/v4/events/<event id>` in your browser, select all the text and copy it. The event id is the id of the event's message on Discord.
- **CSV**: copy the CSV export of the event from Raid-Helper. Its first line must name the columns: a name (`Name`, `Discord name` or `User`) and at least one of class, role or status.

## 2. Paste it into Accord

Officers and the Guild Master only. In the **Events** view (`/accord events`, see [[Events|Events]]) press **Import from Raid-Helper**, paste with `Ctrl+V` and press **Check**.

Accord says what it read: the title, the date and time, how many members matched and which names matched nobody. Then press **Import**.

- A CSV has no title and no date: write them in the two fields of the box (date as `YYYY-MM-DD HH:MM`, in the realm's time). The same fields replace those of a JSON export, if you need to correct them.
- The time of a JSON export is turned into the **realm's time**. Check it, above all around a change to or from summer time.
- Text that is not a Raid-Helper export, that is cut, or that is too big (over 200 KB or 200 sign-ups) is refused with a message. Accord only reads the text: it never runs anything from it.
- Importing the same event again replaces the previous import.

| In Raid-Helper | In Accord |
|---|---|
| Signed up with a class | Signed up |
| Late | Late (counts as signed up) |
| Bench, or waiting in the queue | Bench (counts as signed up) |
| Tentative | Tentative |
| Absence | Absence |

## 3. Matching names to members

Each sign-up is matched to a guild member, in this order:

1. a match you made by hand before;
2. the **Discord name** in the member's contacts (the one the game shows, or the one they typed in the settings);
3. a character name of the guild equal to the Discord name.

Capital letters, a leading `@` and a trailing `#0000` do not matter. All the characters of a player count as one: the sign-up goes to the character of the class they signed up with, else to the one of their season declaration, else to their main. A name that fits two players is matched to nobody.

Raid-Helper shows the **nickname on the Discord server**, which may differ from the name in Accord. Under **Not matched to a member**, choose the name, write the member's character name and press **Match**. Accord remembers it for later events. If you reloaded the game since the import, paste the export again to add the sign-up.

## 4. What the guild sees

- **Every member** sees their own state on Discord (signed up, late, bench, tentative or absence).
- **Officers** also see all the matched sign-ups, the roles next to the [[season roster|Season-Roster]] and the target composition, who signed up on Discord but not in the game calendar, who signed up in the game calendar but not on Discord, and who answered differently. Choose the event to read the game calendar's answers.

## 5. Put it into the game calendar

Importing writes **nothing** into the calendar. To do that, press **Put into the game calendar**, read what will happen and press **Confirm**. Then Accord:

- uses your guild event at that date and time, or creates a guild sign-up event;
- invites the matched members and writes their state (signed up, late and bench as confirmed; tentative; absence as declined);
- **never changes an answer a member already gave in the game**: the game's answer counts, and the view shows the difference;
- writes one thing at a time, at most **40 members per confirmation** (confirm again for the others), and stops at the first error, saying who was left out.

The game may not let an addon or your rank write other members' states, or send invites, or create the event: this has not been checked on WoW Forever yet. Where Accord cannot write a state, the member finds a line in the [[Action Center|Action-Center]], *Answer in the game calendar*, and answers there. If Accord cannot create the event, create it in the game calendar at the same date and time and confirm again.

Keep the game's calendar window closed while Accord writes. If the day already has another raid event, the confirmation tells you: Finland Dragon Credit Points links the first raid event of the day.

## 6. Back to Discord

**Export** gives the officers the event's sign-ups (name, class, role, answer in the game, state on Discord, and *Raid* or *Bench* once the event has a line-up: see [[Events|Events]]) as text for Discord or as CSV, to copy and paste.

## What is shared

- The guild receives the title, the date and the **matched members only** (their character, state, role, class and spec). Officers send it; it is removed 2 days after the event.
- The **names that matched nobody** and your **hand matches** stay on your computer and are never sent. The unmatched names are removed 2 days after the event; a hand match is removed when that character leaves the guild.
- The pasted text itself is not saved.
- Nothing here records who was at a raid.
