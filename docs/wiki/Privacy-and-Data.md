# Privacy and data

The addon has no server, sends nothing outside the game and collects no telemetry. Everything travels only to **your guild**, over the guild's hidden addon channels.

| Who sees it | What |
|---|---|
| Your guild | The list of your characters on the realm and your main, your BattleTag, your Discord name, your recipes, the minutes you spent in groups with guildmates, the bank contents you saw, your bank requests |
| Your guild, as totals only | The likes you receive |
| The officer who records your like | That the like came from you, at the moment it is delivered; it is then stored under a code that members cannot read |
| Officers only | Bank tabs reserved to officers |

The character list, BattleTag and Discord name are **always shared** with your guild: that is how alts are grouped and contacts are shown without asking. There is no switch to turn this off.

The character list holds, for each of your characters on the realm (inside the guild or not): name, class, level, whether it is in the guild, and which one is your main. A character you delete or rename is cleaned up by itself after 30 days, once the game confirms it no longer knows it.

## Nobody can write your data

Every piece of shared data names the character that wrote it, and the game itself tells each addon who sent a message. A guildmate's addon accepts your characters, contacts and recipes only from you (or from one of your own characters), and passes on another member's data only when it comes from an officer. Likes and bank decisions are accepted only from officers. A modified addon can therefore lie only about itself.

## What stays on your computer

The addon keeps its data in the game's own saved-variables files (`AzerothAccord.lua` in your WTF folder): an **account code** (random, created once, used only so that guildmates can tell your characters belong together), your characters, and one separate section for **each guild** you have been in, so the data of two guilds is never mixed. If you leave a guild, its section stays untouched until you come back. `/accord debug` shows how much space the data takes, never the data itself.
