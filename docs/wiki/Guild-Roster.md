# Guild roster

*Italiano: [[Roster di gilda|Guild-Roster-it]]*

> Available from the roster version (milestone M2). The Likes and Social columns arrive with milestone M4 (Likes: the player's total, green when you liked them, grey while your like is pending; Social: the social index, a dash under 5 hours of group play, shown only to officers and the Guild Master). The profession cells open the member's recipes from the professions version (milestone M3): see [[Professions and Recipes|Professions-and-Recipes]].

The **Roster** view is a table of every member: name, level, class, rank, zone, last online, **profession 1** and **profession 2**, likes, the **BattleTag** (shared by the member's own Accord; empty for members without it) and whether the member uses Accord; the social index is on the [[Reputation|Likes-and-Social-Index]] view and the member card. Click a column header to sort (a second click reverses; the sorted column's title is in the accent colour with an arrow, and members with nothing in that column always go last); use the search box at the top right of the tabs (name or profession) and the filters: the buttons *Online*, *Mains only* and *By account* (lit while they are on) and the *Class*, *Rank* and *Profession* lists (the first entry of each shows everything again); *Columns* opens a list of checks to choose which columns to show, and your choices are remembered for each character. When the panel is narrow the filters continue on a second line. The table stays fast with a guild of 1000 members.

## The table

![The Roster table: sortable columns, filters for online, mains only, class, rank and profession, and the column chooser](../specs/mockups/previews/roster-table.webp)

Click a title to sort, click it again to reverse. Before every name there is a **mark in the colour of the class**: a **role icon** when the role is known (a shield for a **tank**, crossed swords for **damage**, a medical bag for a **healer**), else a small square. The name is written in the class colour too (in the light theme the name stays dark and only the mark carries the colour).

**Where the role comes from.** Accord reads the member's **public note** from the left and takes the **first role word** it finds, as a whole word in any case: *tank*; *heal*, *healer*, *healing*, *cura*, *curatore*, *guaritore*; *dps*, *dd*, *melee*, *ranged*, *caster*, *damage*. So *Tank / alt of Mario* is a tank and *dps, sometimes heal* is damage. Without a role word in the note, it uses the role of MS1 in the member's declaration for the current season (see [[Season roster|Season-Roster]]), when the guild's season roster is Accord's. Hover a row, or open the member card, to read the role and where it comes from. **By account** groups the table by player: the main leads, a click on + shows the alts.

![The Roster grouped by account: Brynn's main with two alts shown under it](../specs/mockups/previews/roster-grouped.webp)

## Where a value comes from

Next to a value that does not come straight from the game, Accord shows a small grey **label** with its source: `game` (read from the game now), an age such as `3 d ago` (shared by another player's addon, last changed 3 days ago), `you` (read from your own character) or `note` (declared in the member's public note: Accord cannot check it). Hover it to see who reported the value. The label appears on the member card (professions, contacts, characters of the account, addon version), on the profession cells of the table (in their tooltip), above a recipe list, on the likes total and on every tab of the guild bank. A shared value that has not changed for a long time is **dimmed** and the tooltip says so: 7 days for a bank tab, 60 for professions and recipes, 30 for the addon version, 180 for BattleTag and Discord. The age is "how long the value has not changed", not "how long ago somebody checked it".

## The member card

Click a row to open the **member card**. In the Accord window it opens as a **detail window of its own** beside the window, on the right, or on the left when the screen has no room, so the table keeps its whole width. In the guild window's panel it sits beside the table in a wide panel, or over it (with a *Back* button) in a narrow one. The cross closes it. The card has the member's name in the colour of the class, a few **badges** under it (*online* or *not in guild*, *main* or *alt* when the player has other characters, and the addon version) and one box per section. It shows zone, last online, rank, the public note (and the officers' note only if the game lets you read it), the addon version and the professions with where each piece of information comes from (the game, shared by the member and how old, or read from your own character); the boxes of the professions and of the other characters carry their count. Lines that do something (a link to another character, **[Make this my main]**, **[Like this player]**) are in the accent colour: click another character in the card to open its card, or a profession line to see that member's recipes. If the card is longer than the window, scroll it with the mouse wheel.


![The member card beside the table: details, professions with their source, the characters of the same account, contacts, likes and the social index](../specs/mockups/previews/member-card.webp)

![The member card with numbered notes](../specs/mockups/img/02-member-card.webp)

*Design previews, not screenshots: drawn from the addon's own layout and texts with invented characters and items, because the addon has not been run in the game yet ([all previews](https://github.com/Finland6738/azeroth-accord/blob/main/docs/specs/mockups/previews/README.md)).*

## Characters of the same account

On your own characters the card offers **[Make this my main]**. The card lists **all the characters of the same Battle.net account on the realm**, also those outside the guild, for every member who uses the addon. Turn on *By account* in the table to see one row per player with the alts underneath (click **+** to show them).

A character that is not in the guild appears too. The main is the one the player chose, otherwise the highest-level character.

**Alts in another guild.** For a character outside the guild the card and the grouped rows say where it is: *Other guild: <name> · seen 3 d ago*, or *No guild · seen today* when the character has no guild. The line is read from the characters of that player who are in your guild, so:

- it is **as old as the last login of that alt** with the addon (shown by day: *today*, *3 d ago*); if the alt joins or leaves a guild, you see it only after that alt has logged in and the player has logged in with a character of your guild. A line older than a month is dimmed, and its label says who shared it;
- a character known only from a public note shows no guild, and neither does one the addon has not seen since this feature was added: it shows *not in guild* as before;
- **the other guild does not see anything of Accord's data in your guild.** Only the guild's name and the day of the last login of that alt travel in the account list your guild already receives.

For members without the addon, a public guild note written as `main: <name>` (my main is that character) or `alt: <name>` (that character is my alt) is shown as a hint, labelled *declared in the note*. A member who has the addon is never moved by a note.

The grouping cannot be faked: two characters count as one player only if **both** list each other, so listing someone else's character changes nothing.

## Contacts

The card shows the **BattleTag** and the **Discord** name of members who use the addon (the Discord name also for everybody when the game provides it, marked *from the game*). **Click a contact** to open a small window with the text already selected: press Ctrl+C to copy it, then Esc (or *Close*). **[Add BattleTag friend]** sends the game's own friend request; it works even if the other player does not use the addon. The table has a *Contacts* column (BT and DC) that you can show or hide.

Your own BattleTag is read from the game. Type your **Discord name** (user name only, up to 32 characters, no links) in [[Settings|Settings]] (`/accord settings`); it is used when the game does not show it already. Both are always shared with your guild.

## Timeline (officers only)

Officers and the Guild Master see a **Timeline** box on the member card: what the officers' addons observed change in the roster for that player's characters, newest first. It lists the **ten latest** changes of **every character of the player in the guild**, with a **Show all (n)** link that opens the **Timeline** page of the **Officers** tab on that player, and the line *Member since <date>* from the oldest join Accord saw (*Member since: unknown* when it did not see any: the first time an officer's addon reads the roster it only takes a picture, so the people already in the guild do not "join").

A line is the time and what happened: *joined the guild*, *left the guild* (the game does not say whether the member left or was removed), *rank Member → Veteran*, *level 20 → 27* and *public note: "old" → "new"*. Times are **UTC**. Hover a line to see who observed it (you, a guildmate's name, or *a former officer*; never a technical ID) and the exact interval: an addon only sees a change when it reads the roster, so the line says *between <date> and <date>* when more than a day passed since the previous read. The levels a character gained in one day are one line.

- **Two officers who see the same change make one line.** The same change seen by two officers, even at different times, is shown once, with the narrowest interval and every observer in the tooltip.
- **Kept forever.** Nothing is deleted because it is old: the timeline, with the old and new text of public notes, stays as long as the officers' addons hold it. If you stop being an officer, your addon deletes it from your computer (see below).
- **Only officers.** Members never see the box, never receive these records and their addon does not observe anything. This is the owner's decision ([SPEC-10 Q13](https://github.com/Finland6738/azeroth-accord/blob/main/docs/specs/SPEC-10-risks-open-questions.md)).
- **Where it is kept.** On the computer of the officer who observed it. It is shared with the other officers on the **officer channel only** (never with the guild, never by whisper to a member) and **only after the addon has seen that channel carry an addon message in the session**; until then the box says *Only on this computer until the officer channel works* and the box shows *Officer channel: working* or *not proven yet*. If you stop being an officer, with all your characters, Accord removes this data from your computer.
- Accord never changes the roster: it only watches it. Nothing is promoted, demoted or removed by the addon.

## Officer notes (officers only)

Officers and the Guild Master see an **Officer notes** box on the member card: a longer note about that character, for the officers only. It is not the game's own officer note (31 characters), which Accord shows apart, as before, and never changes.

- **Write a note…** (or **Edit the note…**) opens a box of up to **500 characters** and **20 lines** (and 1000 bytes: letters with accents take two). The count under the box says how much is left; a note over the limit is not saved and the box says why. **Delete the note** removes it for every officer.
- The box shows who wrote the latest version and when (*Written by you, 3 d ago*), and below, read-only, the notes of the player's other characters, each with its name. Two officers who edit the same note at once: the later save wins.
- The **Inactive** page marks with a book icon the players who have a note on one of their characters, and the second step of the cleanup review shows the player's note on one line.
- **Kept forever.** The note of a player who left the guild stays (the box says *Left the guild on <date>*), so it is there if they come back. Only **Delete the note** removes it.
- **Only officers.** Members never see the box and never receive the notes. They travel like the timeline: on the **officer channel only**, never with the guild, never by whisper to a member, and only after the addon has seen that channel work in the session; until then a note stays on the computer where it was written (*Only on this computer until the officer channel works*). They are never in an export, nor in your personal backup; *What I share* only counts the notes you wrote.
- If you stop being an officer, with all your characters, Accord deletes the notes from your computer; promoted again, you receive them back from the other officers.

## Trials (officers only)

> **New in `v0.12.0`**. Nothing of it has been checked in the real game.

Officers and the Guild Master can follow a new member **on trial**. The member sees nothing of it in Accord; if the guild has a rank for trials, the game already shows it.

- **Start a trial**: from the **Trials** page of the Officers tab (a fourth page, after *Timeline*) or from the member card. Choose the member, the length (**14 days** by default, from 1 to 60) and the first day (today by default; at most 30 days back or 14 ahead).
- **The page** lists the open trials (name, rank, start, end, days left, number of notes; *2 open trials* when two officers started one each) and, with **Closed (90 days)**, the ones closed recently. Older ones stay on the member card.
- **Click a trial** to see it: **Extend** by some days (the end can move up to 120 days after the start), or close it with **Passed**, **Not passed** or **Cancel trial**. Each closing asks a second click (**Confirm**). A closed trial is never reopened: start a new one from another day.
- **Passed** can add a **promotion to your queue** (the switch under the buttons, off at first): the nearest rank above theirs that you may give. Accord never promotes anybody: you do it in the game, and the queue ticks it.
- **Notes**: every officer writes **one note** per trial (*Write my note*), in the same box and with the same limits as the [officer notes](#officer-notes-officers-only); the others' notes are read-only, with their author and age.
- **The end day**: the [[Action Center|Action-Center]] shows *Trial of … ended on …: decide* until an officer closes or extends the trial, and a notice comes **once**, on the end day (also after a `/reload` or another login); an extension gives a new one on the new end day. A member who left the guild during the trial shows as *… left the guild during the trial* until an officer cancels it.
- **Suggested mentors**: a third tab of the page lists the new members (on trial, or joined in the last 30 days), the oldest first, each with up to three [[mentors|Likes-and-Social-Index]] who offered, why (*2.0 h together*, *plays with the same people*, *same group*, *usually online at the same hours*, or *No play together yet*) and **Whisper** for both. A mentor is the first choice of at most three new members. The new member's card shows the same, for officers only. **Sort by** at the top orders the new members as suggested, by name or by the day they joined.
- **Kept for ever**, like the notes and the timeline. They travel like them: **officer channel only**, never with the guild, never by whisper to a member, and only once the channel works (until then *Only on this computer until the officer channel works*). They are not in your personal backup; *What I share* only counts them. If you stop being an officer, Accord deletes them from your computer.

## The Officers pages (officers only)

Officers and the Guild Master have one more icon on the rail, **Officers**, with the pages **Inactive**, **Queue** and **Timeline** (and **Trials**). Members do not see the icon. The line at the top right says whether the **officer channel** works; the search box of the panel filters by name.

### Inactive accounts

The **Inactive** page lists the **players**, not the characters, who have not been seen for a while: a player who only plays an alt is **not** inactive.

- **Last seen** is the most recent among all the characters of the player: online now or the game's own *last online* for the characters in the guild, the day of the last login with the addon for an alt outside the guild (shared by that player's addon), and your own logins for your characters. Characters are put together as on the member card; if a public note (`main:` / `alt:`) is what joins them, the row says *grouped by a note*, because nobody verifies it.
- **Tiers**: 14, 30, 60 and 90 days by default. **Tiers…** changes them: four increasing numbers from 1 to 365, **the same for all officers** (any officer can change them), with *Reset to defaults*.
- **Columns**: the main, how many characters are in the guild, the highest rank, the days, the tier, when and on which character the player was last seen, and the absence. Hover a row for the source of the date. Rows are sorted by days, the longest first; players with an officer character are marked *officer*, players with an [officer note](#officer-notes-officers-only) a book icon.
- **Filters**: the lowest tier shown, **Show away** (players with a declared absence, hidden otherwise) and **Show unknown** (players of whom no date is known, listed last; the game may not tell the *last online* of every member).
- **Click a row** to set or clear an absence, or to open the member card.

The addon only lists them. It never removes, demotes or messages anyone.

### Cleanup review and queue

**Review…** on the Inactive page helps you decide what to do with the players who stayed away. **Accord never changes the roster**: it does not promote, demote, remove or write notes. It only prepares a list of things for you to do by hand.

1. **Which accounts.** Choose the lowest tier (90 days or more at first). Two switches add the accounts you reviewed in the last 30 days and the ones of which no date is known. Accounts with a declared absence or with an officer character are never proposed.
2. **One choice per account**, grouped by tier. Click an account to see its characters in the guild (rank, level, last seen) its officer note, if it has one, and its last three timeline changes, then choose **Keep** (the default), **Remove**, **Demote**, **Promote** or **Edit note**. The choice counts for every character of the account; click a character to give it a different one. For a rank change Accord proposes the next rank and lets you pick any rank below your own. For a note you choose the public or the officer one and write the new text (at most 31 characters). Actions your rank may not do are left out.
3. **Summary.** **Add N actions to the queue** fills the queue and does nothing else. The accounts left on *Keep* are not proposed again for 30 days. Choices that could not be added are listed with the reason.

The **Queue** page lists what is left to do, the oldest first; the tab shows how many. Click an entry to see the name (selected, copy it with Ctrl+C) and either the game's command to type in the chat (`/gremove`, `/gpromote`, `/gdemote`) or the text to paste in the note, with a button that opens the guild window. You type or click it yourself.

- **Ticked by the roster.** When Accord reads the roster and sees the rank changed, the character gone or the note changed, the entry becomes **done**, also when another officer did it. If the character left while a rank or note change was waiting, it becomes **left**.
- If your rank cannot read officer notes, an officer note entry has a **Mark done** button instead.
- An entry still open after **14 days** is **expired**. Closed entries stay, dimmed, for 7 days. **Cancel entry** closes one by hand. A new entry for the same character and action replaces the open one; at most 200 can be open.
- The queue is **yours**: it stays on your computer and is not shared with the other officers. It is deleted if you stop being an officer.

The commands, the permissions and the 31-character limit have not been checked in the game yet.

### Timeline

All the observed changes of the guild, with filters by kind (joined, left, rank, level, public note) and by period (7, 30, 90 or 365 days; 30 at first). Opened from **Show all** of a member card it shows that player only; click **Only <name>** to show everybody again.

## Export (officers only)

Officers and the Guild Master can copy what a page shows out of the game, to a spreadsheet or to Discord. The **Export** button is on the **Roster** view and on the **Inactive** and **Timeline** pages of the *Officers* tab. Members do not have it.

- The export holds **what the page shows**, with its filters and the search. In the Roster view grouped *By account*, the alts of a closed account are included; a character outside the guild is not.
- A box opens with the text **already selected**: press **Ctrl+C**, then paste. Above it: *This text leaves the game: share it only with your officers.* Choose **CSV** or **Discord** at the top right; the box remembers the choice until you log out.
- **CSV**: one line of column names in English, then one row per line, separated by commas. Dates are UTC. Paste it into a file ending in `.csv` (UTF-8) or into a spreadsheet and split it by commas. A text that a spreadsheet could run as a formula (starting with `=`, `+`, `-` or `@`) gets an apostrophe `'` in front.
- **Discord**: a code block with aligned columns, so mentions such as `@everyone` stay plain text. A long export is cut into parts of at most 1900 characters, numbered *(1/3)* and separated by an empty line: send one part per message. Long names (24 characters) and notes (30) are shortened with `…`.
- A very long export (over 256 KB) keeps the first rows only, and the box says how many rows were left out: narrow the filters.

| Export | CSV columns |
|---|---|
| Roster (one row per character in the guild) | `name`, `realm`, `main`, `class`, `level`, `rank`, `last_seen_date`, `days_inactive`, `account_days_inactive`, `tier`, `away_until`, `public_note`, `has_addon` |
| Inactive accounts (one row per player) | `main`, `realm`, `characters`, `highest_rank`, `days_inactive`, `tier`, `last_seen_date`, `last_seen_character`, `last_seen_source`, `grouped_by_note`, `away_until` |
| Timeline (one row per change) | `date_utc`, `since_utc`, `event`, `name`, `realm`, `from`, `to`, `observers` |

`class` is the game's English class code (such as `MAGE`); `main` is empty for a main or a player with one character; `tier` goes from 0 (active) to 4 and is empty when unknown; `last_seen_source` is `game`, `shared` or `you`; `event` is `join`, `leave`, `rank`, `level` or `note`; `realm` is empty for your own realm.

**Never exported:** the game's officer notes, Accord's [officer notes](#officer-notes-officers-only), account codes and the game's internal identifiers. The **public** note is in the Roster and Timeline exports.

How long a text the box can hold, and pasting it into Discord or a spreadsheet, have not been checked in the game yet.

## Declared absences

A **return date** tells the officers that a player is away on purpose: until that day, included, the player does not count as inactive. There is no reason and no free text.

- **You** declare your own in [[Settings|Settings]], in the **Absence** card, or with `/accord away 2026-12-31` and `/accord away off`. The date is at most 180 days ahead. You see only what you declared, and never your own inactivity tier.
- **Officers** set or clear the absence of any player from the member card (**Absence** box) or from the Inactive page. The most recently saved one counts, whoever saved it, for all the characters of the player.
- **How it travels.** Your addon whispers your declaration to up to two officers who are online with Accord, when you save it and once after you log in while it is valid; if none is online it tries again at your next login. Officers share it among themselves on the officer channel. Nobody else receives it.
- The day after the return date the player counts again, and the list says *away until <date>* for two weeks. The record is deleted 30 days after the return date.
