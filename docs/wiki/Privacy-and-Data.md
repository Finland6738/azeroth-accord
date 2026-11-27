# Privacy and data

*Italiano: [[Privacy e dati|Privacy-and-Data-it]]*

The addon has no server, sends nothing outside the game and collects no telemetry. Everything travels only to **your guild**, over the guild's hidden addon channels.

| Who sees it | What |
|---|---|
| Your guild | The names in the bank log with what they deposited or withdrew (as the game shows it), and the donations list built from it; the list of your characters on the realm and your main, your BattleTag, your Discord name, your recipes, the minutes you spent in groups with guildmates, the bank contents you saw, your bank requests |
| Your guild, only if you offer | From `v0.12.0`: your **mentor offer** (the character, the topics and a short note), off until you click it; leaving is sent too. The mentors suggested to officers for new members are computed on their computers, never saved or sent (see *Likes and social index*) |
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

Every piece of shared data names the character that wrote it, and the game itself tells each addon who sent a message. A guildmate's addon accepts your characters, contacts and recipes only from you (or from one of your own characters), and passes on another member's data only when it comes from an officer. Likes and bank decisions are accepted only from officers. A modified addon can therefore lie only about itself.

A broken or modified addon cannot jam yours either: a message that is too large, damaged or of the wrong shape is dropped, and a guildmate's addon that sends far too much, or keeps sending data it may not send, is ignored for 10 minutes. Your own messages keep going out meanwhile, and the guild's data repairs itself afterwards. `/accord debug` says how many addons are ignored right now, never who.

## Groups

> From `v0.9.0`.

A [[group|Groups]] you post (type, activity, levels, size, roles still needed, your note and meeting point, never a position) is sent to your guild only, and every member's computer drops it 10 minutes after it ends. An **application** (your role, level and optional comment) goes by whisper to that group's leader only, and so does the answer: nobody else knows. Both are kept on the two computers until the group closes, and neither enters backups or exports. Your saved filters stay on your computer.

## Craft orders

> Coming with milestone M13, hidden until M13 is complete.

A craft **order** you place (the recipe, how many, the crafter, who brings the materials, your price as text, your note, the needed-by day) and the steps you take as the crafter (with your note) are sent to your guild, and everybody in the guild sees them. Closed orders are deleted after 30 days. Your old craft requests are never published unless you press *Make it an order*. See [[Professions and Recipes|Professions-and-Recipes]].

## Wishlist

> Coming with milestone M13, hidden until M13 is complete.

Your **wishlist** (the items, how many, until which day, whether an entry came from the shopping list, and your note) is sent to your guild, and everybody in the guild sees it. Entries expire by themselves, and an empty list is deleted 30 days after your last change. The material demand and the recipe materials stay on your computer and are never sent.

## Buy and sell board

> Coming with milestone M13, hidden until M13 is complete.

Your **posts** (selling or buying, the item, how many, your price as text, your note, until when) and your **answers** to other people's posts (interested, confirmed or taken back, with your note) are sent to your guild, and everybody in the guild sees them. They are deleted 7 days after the post ends or the deal closes. Which authors you hid, and that you read the warning, stay on your computer. Accord never trades or moves gold or items.

## Shopping list and your counts

> Coming with milestone M13, hidden until M13 is complete.

Your **shopping list** and the **counts** of your bags, bank and mail (and those of your alts, read when each of them plays on this computer) stay **on this computer only**: they are never sent, never in a backup or an export, and *Clear guild data* leaves them. Only **Ask the guild** (the missing materials, into your wishlist) and **Ask the bank** (one bank request with a missing material) let anything out, and only what is missing. Auction prices are read from Auctionator, if you use it, when the page is drawn, and never saved or sent.

## Your addon list

> From `v0.9.0`.

Accord shares with your guild the **list of the addons this character has loaded** (folder name, version and title; never Blizzard's own addons, their settings or any file), so that the [[Guild addons|Guild-Addons]] tab can count them. Everybody sees the counts and the versions; **who** uses an addon Accord shows only to officers and the Guild Master, and to you your own entry. That is a rule of the interface: the lists reach the whole guild. A list is kept for 60 days. **Share my addon list** is on by default; switch it off (on *What I share* or in the Contacts card of Settings) and your lists are withdrawn and no new one is sent.

## Season roster

> From `v0.10.0`.

When you declare for a raid season (MS1, MS2, OS, a note, or *Not sure yet*), the declaration reaches the whole guild, and it is listed in *What I share*. Only your own account can write it. The current season and the 3 before it are kept; older ones are removed. See [[Season roster|Season-Roster]].

## Events

> From `v0.10.0`.

When you sign up to a guild event from Accord, your answer goes into the **game calendar**, as if you had answered in the game. The **role** you choose for the event, which the game calendar cannot hold, reaches the whole guild and is listed in *What I share*; so are your answers to events kept only in Accord (when a client has no game calendar). Only your own account can write them, and they are removed 2 days after the event. Accord records no attendance. See [[Events|Events]].

When an officer imports a **Raid-Helper** event from Discord, the guild receives its title, its date and the **matched members only** (character, state, role, class and spec), until 2 days after the event. The names that matched nobody and the officer's hand matches stay on that officer's computer and are never sent; the unmatched names are removed 2 days after the event. Accord never contacts Discord or Raid-Helper. See [[Raid-Helper events|Raid-Helper]].

A raid **line-up** written by an officer (who is in the raid, who is on the bench, who plays their MS2) reaches the guild until 2 days after the event. It is a plan, not a record of who came. See [[Events|Events]].

## When you usually play

> From `v0.10.0`.

Accord counts, on your computer, the minutes your account is online per hour of the week over the last 8 weeks, and nothing else: no place, no activity, no raid and no attendance. The guild receives, per hour, one of four levels and the number of weeks measured, kept for 30 days. Everybody sees how many members are online in each hour; **who** they are Accord shows only to officers and the Guild Master, and to you your own entry (a rule of the interface: the maps reach the whole guild). **Share when I usually play** is on by default; off, your map is withdrawn and nothing more is sent, while your own keeps counting on your computer. See [[Availability|Availability]].

## PvP and world rallies

> From `v0.10.0`.

A [[rally|Events]] holds its kind, the meeting point **as the text you write**, the times and, from whoever answers, *coming* or *not coming*. The whole guild with Accord sees it, and it is removed 10 minutes after it ends. Accord **never reads your position** and sends no coordinates or map.

## Guild handbook and loot choice

> From `v0.11.0`.

The pages of the [[guild handbook|Guild-Handbook]], written by officers and the ranks they choose, reach the whole guild with Accord, with the character who wrote them and when; so do the chosen writer ranks, the loot system and the loot addon. Earlier revisions of a page, your read marks and an unsaved draft stay on your computer and are never sent.

## Other addons

Apart from that list (new in `v0.9.0`), from `v0.10.0` Accord looks for the raid and loot addons it knows **only on your own computer**, reads Finland Dragon Credit Points through its public interface when the officers chose it as the source of the season roster or (from `v0.11.0`) as the loot addon, and shares with the guild only those choices: see *[[Raid and loot addons|Raid-and-Loot-Addons]]*. It never writes another addon's data or reads its saved files.

## What stays on your computer

The addon keeps its data in the game's own saved-variables files (`AzerothAccord.lua` in your WTF folder): an **account code** (random, created once, used so that guildmates can tell your characters belong together and so that an officer can record your likes anonymously), the list of players **you** liked and the likes still waiting (only on your computer, never shared), your characters, from `v0.9.0` the reminders of the craft requests you wrote in the [[Action Center|Action-Center]] (the member, the recipe and the time; never sent, never in your backup), the state of the [[welcome checklist|Action-Center]] of a new member *(from `v0.12.0`; never sent, officers do not see it)*, and one separate section for **each guild** you have been in, so the data of two guilds is never mixed. If you leave a guild, its section stays untouched until you come back. `/accord debug` shows how much space the data takes, never the data itself.
