# Privacy and data

*Italiano: [[Privacy e dati|Privacy-and-Data-it]]*

The addon has no server, sends nothing outside the game and collects no telemetry. Everything travels only to **your guild**, over the guild's hidden addon channels.

| Who sees it | What |
|---|---|
| Your guild | The names in the bank log with what they deposited or withdrew (as the game shows it), and the donations list built from it; the list of your characters on the realm and your main, your BattleTag, your Discord name, your recipes, the minutes you spent in groups with guildmates, the bank contents you saw, your bank requests |
| Your guild, as totals only | The likes you receive |
| You, officers and the Guild Master | Your social index and the guildmates you played with most (computed by each addon from the shared minutes) |
| The officer who records your like | That the like came from you, at the moment it is delivered; it is then stored under a code that members cannot read |
| Officers only | Bank tabs read by an officer (shared on the officer channel only, never held by members' addons), and the guild's secret code that turns a voter into the anonymous code of the likes (kept only by officers' addons, removed when an officer is demoted) |
| Officers only | The roster history officers observed (joins, leaves, rank and level changes, public notes), kept forever: on the officer channel only, and only on the observing officer's computer until that channel is proven (see *Guild roster*) |
| Officers only | Declared absences: a return date, with no reason. A member's addon whispers its own to officers who are online; officers set others and share them among themselves. The inactivity tiers the officers chose travel the same way. The inactivity of each player is computed by each officer's addon and never saved |
| Officers only | Officer notes: a longer note about a character written by officers, kept forever (also after the player leaves the guild). On the officer channel only, and only on the writing officer's computer until that channel is proven; never exported, never in your backup; removed when the officer is demoted |
| Officers only | Exports: a text an officer copies out of the game (names, ranks, levels, last online, tiers, absences, public notes and the timeline; never officer notes, account codes or internal identifiers). Once copied, Accord cannot take it back; the addon neither saves nor sends it |
| Officers only | The cleanup queue and the accounts marked as reviewed: kept on that officer's computer only, never sent, removed when the officer is demoted |

The character list, BattleTag and Discord name are **always shared** with your guild: that is how alts are grouped and contacts are shown without asking. There is no switch to turn this off. Contacts received from other players are checked (a BattleTag must look like one, a Discord name must be a plain user name) and shown as plain text, never as links.

The character list holds, for each of your characters on the realm (inside the guild or not): name, class, level, whether it is in the guild, and which one is your main. For a character outside the guild it also holds the **name of its guild** (or that it has none) and the **day** of its last login with the addon, so that your guild can see where your alts are; the hour is not shared. A character you delete or rename is cleaned up by itself after 30 days, once the game confirms it no longer knows it. **Settings → Clear guild data** forgets what the addon holds about a guild on your computer at any time ([[Settings|Settings]]).

The minutes you spend in groups with guildmates are recorded from the roster version on (see *Likes and social index*), per day and per pair of characters, and kept for 90 days.

## Nobody can write your data

Every piece of shared data names the character that wrote it, and the game itself tells each addon who sent a message. A guildmate's addon accepts your characters, contacts and recipes only from you (or from one of your own characters), and passes on another member's data only when it comes from an officer. Likes, bank decisions and the guild's choice of its raid and loot addons are accepted only from officers. A modified addon can therefore lie only about itself.

A broken or modified addon cannot jam yours either: a message that is too large, damaged or of the wrong shape is dropped, and a guildmate's addon that sends far too much, or keeps sending data it may not send, is ignored for 10 minutes. Your own messages keep going out meanwhile, and the guild's data repairs itself afterwards. `/accord debug` says how many addons are ignored right now, never who.

## Other addons

Accord looks for the raid and loot addons it knows (Finland Dragon Credit Points and the loot addons that run on WoW Forever) **only on your own computer**: whether each one is loaded and its version. It never sends that list, never changes, loads or switches on another addon, and never reads another addon's saved data. The only thing shared with the guild is the **officers' choice** of which addon is the source of the season roster and of the loot data (one choice for the whole guild, written only by officers). See *[[Raid and loot addons|Raid-and-Loot-Addons]]*.

## What stays on your computer

The addon keeps its data in the game's own saved-variables files (`AzerothAccord.lua` in your WTF folder): an **account code** (random, created once, used so that guildmates can tell your characters belong together and so that an officer can record your likes anonymously), the list of players **you** liked and the likes still waiting (only on your computer, never shared), your characters, and one separate section for **each guild** you have been in, so the data of two guilds is never mixed. If you leave a guild, its section stays untouched until you come back. `/accord debug` shows how much space the data takes, never the data itself.
