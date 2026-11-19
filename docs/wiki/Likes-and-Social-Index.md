# Likes and social index

> Planned for milestone M4. **Recording starts earlier, in milestone M2** (see below), so that the index has weeks of history when it appears.

## Likes

- You can give **one like to each other player**: the like goes from your account to theirs, and the total shows on all their characters.
- You cannot like yourself or your own alts, and a like **cannot be taken back**.
- Likes are **anonymous**: everyone sees only the totals.
- Your like is delivered to an online officer's addon, which records it for the guild. If no officer is online it waits and shows as *pending*.

## Social index

The social index shows **how many different guildmates someone really plays with**, from 0 to 100. It counts the minutes spent in a party or raid with guildmates over the last 30 days and turns them into **effective partners**: playing always with the same four people counts as about 4, spreading your time over thirty people counts as about 30. The index divides that by the number of active players.

The member card shows the effective partners, the number of different partners and the five guildmates played with most. The **group map** shows the guild's groups and how mixed the guild is. *Play with someone new* suggests online guildmates you have rarely played with.

## What is recorded already (from the roster version)

Every minute you are in a party or raid with at least one guildmate, the addon adds one minute to each pair of guildmates in the group, also inside instances. The minutes are kept per day, shared with your guild once an hour (and when you log out) and discarded after 90 days. When several players with the addon were in the same group, the largest count is used, never the sum. Nothing is shown yet: only `/accord debug` prints the counts (never names). Members the game hides from addons inside an instance are left out rather than guessed.
