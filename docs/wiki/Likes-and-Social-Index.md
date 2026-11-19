# Likes and social index

> Likes are available from the reputation version (milestone M4); the social index, the group map and the suggestions follow within the same milestone. **Recording of group play started earlier, in milestone M2** (see below), so that the index has weeks of history when it appears.

## Likes

- You can give **one like to each other player**: the like goes from your account to theirs, and the total shows on all their characters.
- You cannot like yourself or your own alts, and a like **cannot be taken back**.
- Likes are **anonymous**: everyone sees only the totals.
- Your like is delivered to an online officer's addon, which records it for the guild. If no officer is online it waits and shows as *pending*.

### Giving a like

- On a guildmate's **member card** (click their row in the Roster): the *Likes* section shows the total of the player and **[Like this player]**. Click it, then click again within a few seconds to confirm: a like cannot be taken back.
- In the **Reputation** view (`/accord reputation`): every player of the guild, one row per player with all their characters together, sorted by likes. Click **Like** twice on a row. Click the headers to sort by name or likes; the search box finds a player by any of their characters; clicking a row opens their card.
- After that the row says *pending* (no officer with the addon online yet) or *liked*. Your own characters say *you*.
- The **Likes** column of the Roster shows each player's total: green when you liked them, grey while your like is pending.
- If an officer's addon refuses a like (it is one of your own characters, or the player left the guild), the chat says why.

### How likes stay anonymous

- Your addon whispers the like to **one** online officer with the addon (never to the guild channel). That officer's addon checks it and records it under an **anonymous code** computed with a secret that only officers' addons hold; the guild receives only that code and the character you liked. Members cannot turn the code back into a name.
- The officer who records your like can see that it came from you at the moment it arrives. As in the game itself, officers are trusted.
- The addon remembers on **your computer** which players you already liked (so the button disappears on all their characters) and the likes still waiting. Nobody else receives that list.
- A second like to the same player is refused, also from one of your alts, to one of their alts, or after you reinstalled the addon on another computer.
- If an officer leaves and nobody else holds the secret, a new one is made: the likes already given stay, but the check for a second like to the same player works only for likes given after that.
- Likes cannot be invented by members: the guild's addons accept the list of likes only from officers, and an entry can never be changed or removed.

## Social index

The social index shows **how many different guildmates someone really plays with**, from 0 to 100. It counts the minutes spent in a party or raid with guildmates over the last 30 days and turns them into **effective partners**: playing always with the same four people counts as about 4, spreading your time over thirty people counts as about 30. The index divides that by the number of active players.

The member card shows the effective partners, the number of different partners and the five guildmates played with most. The **group map** shows the guild's groups and how mixed the guild is. *Play with someone new* suggests online guildmates you have rarely played with.

## What is recorded already (from the roster version)

Every minute you are in a party or raid with at least one guildmate, the addon adds one minute to each pair of guildmates in the group, also inside instances. The minutes are kept per day, shared with your guild once an hour (and when you log out) and discarded after 90 days. When several players with the addon were in the same group, the largest count is used, never the sum. Nothing is shown yet: only `/accord debug` prints the counts (never names). Members the game hides from addons inside an instance are left out rather than guessed.
