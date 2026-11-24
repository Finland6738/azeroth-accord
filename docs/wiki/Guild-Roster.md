# Guild roster

*Italiano: [[Roster di gilda|Guild-Roster-it]]*

> Available from the roster version (milestone M2). The Likes and Social columns arrive with milestone M4 (Likes: the player's total, green when you liked them, grey while your like is pending; Social: the social index, a dash under 5 hours of group play, shown only to officers and the Guild Master). The profession cells open the member's recipes from the professions version (milestone M3): see [[Professions and Recipes|Professions-and-Recipes]].

The **Roster** view is a table of every member: name, level, class, rank, zone, last online, **profession 1** and **profession 2**, likes, social index, Battle.net and Discord. Click a column header to sort (a second click reverses; the sorted column's title is in the accent colour with an arrow, and members with nothing in that column always go last); use the search box at the top right of the tabs (name or profession) and the filters: the buttons *Online*, *Mains only* and *By account* (lit while they are on) and the *Class*, *Rank* and *Profession* lists (the first entry of each shows everything again); *Columns* opens a list of checks to choose which columns to show, and your choices are remembered for each character. When the panel is narrow the filters continue on a second line. The table stays fast with a guild of 1000 members.

## The table

![The Roster table: sortable columns, filters for online, mains only, class, rank and profession, and the column chooser](../specs/mockups/previews/roster-table.webp)

Click a title to sort, click it again to reverse. Every name has a small square in the colour of the class, and the name is written in that colour (in the light theme the name stays dark and only the square carries the colour). **By account** groups the table by player: the main leads, a click on + shows the alts.

![The Roster grouped by account: Brynn's main with two alts shown under it](../specs/mockups/previews/roster-grouped.webp)

## Where a value comes from

Next to a value that does not come straight from the game, Accord shows a small grey **label** with its source: `game` (read from the game now), an age such as `3 d ago` (shared by another player's addon, last changed 3 days ago), `you` (read from your own character) or `note` (declared in the member's public note: Accord cannot check it). Hover it to see who reported the value. The label appears on the member card (professions, contacts, characters of the account, addon version), on the profession cells of the table (in their tooltip), above a recipe list, on the likes total and on every tab of the guild bank. A shared value that has not changed for a long time is **dimmed** and the tooltip says so: 7 days for a bank tab, 60 for professions and recipes, 30 for the addon version, 180 for BattleTag and Discord. The age is "how long the value has not changed", not "how long ago somebody checked it".

## The member card

Click a row to open the **member card**: beside the table in a wide panel, over it (with a *Back* button) in a narrow one; the cross closes it. The card has the member's name in the colour of the class, a few **badges** under it (*online* or *not in guild*, *main* or *alt* when the player has other characters, and the addon version) and one box per section. It shows zone, last online, rank, the public note (and the officers' note only if the game lets you read it), the addon version and the professions with where each piece of information comes from (the game, shared by the member and how old, or read from your own character); the boxes of the professions and of the other characters carry their count. Lines that do something (a link to another character, **[Make this my main]**, **[Like this player]**) are in the accent colour: click another character in the card to open its card, or a profession line to see that member's recipes. If the card is longer than the window, scroll it with the mouse wheel.


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

## The Officers tab (officers only)

Officers and the Guild Master have one more tab, **Officers**, with two pages: **Inactive** and **Timeline**. Members do not see the tab. The line at the top right says whether the **officer channel** works; the search box of the panel filters by name.

### Inactive accounts

The **Inactive** page lists the **players**, not the characters, who have not been seen for a while: a player who only plays an alt is **not** inactive.

- **Last seen** is the most recent among all the characters of the player: online now or the game's own *last online* for the characters in the guild, the day of the last login with the addon for an alt outside the guild (shared by that player's addon), and your own logins for your characters. Characters are put together as on the member card; if a public note (`main:` / `alt:`) is what joins them, the row says *grouped by a note*, because nobody verifies it.
- **Tiers**: 14, 30, 60 and 90 days by default. **Tiers…** changes them: four increasing numbers from 1 to 365, **the same for all officers** (any officer can change them), with *Reset to defaults*.
- **Columns**: the main, how many characters are in the guild, the highest rank, the days, the tier, when and on which character the player was last seen, and the absence. Hover a row for the source of the date. Rows are sorted by days, the longest first; players with an officer character are marked *officer*.
- **Filters**: the lowest tier shown, **Show away** (players with a declared absence, hidden otherwise) and **Show unknown** (players of whom no date is known, listed last; the game may not tell the *last online* of every member).
- **Click a row** to set or clear an absence, or to open the member card.

The addon only lists them. It never removes, demotes or messages anyone.

### Timeline

All the observed changes of the guild, with filters by kind (joined, left, rank, level, public note) and by period (7, 30, 90 or 365 days; 30 at first). Opened from **Show all** of a member card it shows that player only; click **Only <name>** to show everybody again.

## Declared absences

A **return date** tells the officers that a player is away on purpose: until that day, included, the player does not count as inactive. There is no reason and no free text.

- **You** declare your own in [[Settings|Settings]], in the **Absence** card, or with `/accord away 2026-12-31` and `/accord away off`. The date is at most 180 days ahead. You see only what you declared, and never your own inactivity tier.
- **Officers** set or clear the absence of any player from the member card (**Absence** box) or from the Inactive page. The most recently saved one counts, whoever saved it, for all the characters of the player.
- **How it travels.** Your addon whispers your declaration to up to two officers who are online with Accord, when you save it and once after you log in while it is valid; if none is online it tries again at your next login. Officers share it among themselves on the officer channel. Nobody else receives it.
- The day after the return date the player counts again, and the list says *away until <date>* for two weeks. The record is deleted 30 days after the return date.
