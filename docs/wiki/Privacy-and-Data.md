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

Every piece of shared data names the character that wrote it, and the game itself tells each addon who sent a message. A guildmate's addon accepts your characters, contacts and recipes only from you (or from one of your own characters), and passes on another member's data only when it comes from an officer. Likes and bank decisions are accepted only from officers. A modified addon can therefore lie only about itself.

A broken or modified addon cannot jam yours either: a message that is too large, damaged or of the wrong shape is dropped, and a guildmate's addon that sends far too much, or keeps sending data it may not send, is ignored for 10 minutes. Your own messages keep going out meanwhile, and the guild's data repairs itself afterwards. `/accord debug` says how many addons are ignored right now, never who.

## Groups

> From `v0.9.0`.

A [[group|Groups]] you post (type, activity, levels, size, roles still needed, your note and meeting point, never a position) is sent to your guild only, and every member's computer drops it 10 minutes after it ends. An **application** (your role, level and optional comment) goes by whisper to that group's leader only, and so does the answer: nobody else knows. Both are kept on the two computers until the group closes, and neither enters backups or exports. Your saved filters stay on your computer.

## Your addon list

> From `v0.9.0`.

Accord shares with your guild the **list of the addons this character has loaded** (folder name, version and title; never Blizzard's own addons, their settings or any file), so that the [[Guild addons|Guild-Addons]] tab can count them. Everybody sees the counts and the versions; **who** uses an addon Accord shows only to officers and the Guild Master, and to you your own entry. That is a rule of the interface: the lists reach the whole guild. A list is kept for 60 days. **Share my addon list** is on by default; switch it off (on *What I share* or in the Contacts card of Settings) and your lists are withdrawn and no new one is sent.

## Season roster

> Arrives with `v0.10.0`.

When you declare for a raid season (MS1, MS2, OS, a note, or *Not sure yet*), the declaration reaches the whole guild, and it is listed in *What I share*. Only your own account can write it. The current season and the 3 before it are kept; older ones are removed. See [[Season roster|Season-Roster]].

## Events

> Arrives with `v0.10.0`.

When you sign up to a guild event from Accord, your answer goes into the **game calendar**, as if you had answered in the game. The **role** you choose for the event, which the game calendar cannot hold, reaches the whole guild and is listed in *What I share*; so are your answers to events kept only in Accord (when a client has no game calendar). Only your own account can write them, and they are removed 2 days after the event. Accord records no attendance. See [[Events|Events]].

When an officer imports a **Raid-Helper** event from Discord, the guild receives its title, its date and the **matched members only** (character, state, role, class and spec), until 2 days after the event. The names that matched nobody and the officer's hand matches stay on that officer's computer and are never sent; the unmatched names are removed 2 days after the event. Accord never contacts Discord or Raid-Helper. See [[Raid-Helper events|Raid-Helper]].

## Other addons

Apart from that list (new in `v0.9.0`), the released addon does not look for other addons and reads nothing from them. A later release (milestones M10 and M11) will look for the raid and loot addons it knows **only on your own computer** and share with the guild only the officers' choice of which one is the source: see *[[Raid and loot addons|Raid-and-Loot-Addons]]*.

## What stays on your computer

The addon keeps its data in the game's own saved-variables files (`AzerothAccord.lua` in your WTF folder): an **account code** (random, created once, used so that guildmates can tell your characters belong together and so that an officer can record your likes anonymously), the list of players **you** liked and the likes still waiting (only on your computer, never shared), your characters, from `v0.9.0` the reminders of the craft requests you wrote in the [[Action Center|Action-Center]] (the member, the recipe and the time; never sent, never in your backup), and one separate section for **each guild** you have been in, so the data of two guilds is never mixed. If you leave a guild, its section stays untouched until you come back. `/accord debug` shows how much space the data takes, never the data itself.
