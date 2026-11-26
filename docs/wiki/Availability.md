# Availability

*Italiano: [[Disponibilità|Availability-it]]*

> **From `v0.10.0`**, the next release: it is complete in the code and not published yet; no earlier version has it. Nothing on this page has been checked in the real game. What follows describes how it should work.

The availability map answers one question: **when do the guild's members usually play?** It helps to choose the day and hour of a raid or an event.

## What is measured

**Only the time you are online.** While one of your characters is logged in, Accord counts the minutes, per hour of the week on the realm's clock, over the last **8 weeks**. Characters of your account in other guilds, or in none, count too: they tell when you play.

Nothing else is looked at: not where you are, not what you do, not your group, and **nothing about raids**. Accord keeps no attendance: that belongs to the guild's raid or loot addon.

For each of the 168 hours of the week the result is one of four **levels**, over the weeks measured so far (up to 8). A week counts for an hour when you were online at least 10 minutes of it.

| Level | Meaning |
|---|---|
| never | no week |
| less than one week in four | rarely |
| up to half of the weeks | sometimes |
| more than half of the weeks | usually |

The count starts when the version with this view is installed: in the first weeks the map says little.

## The view

Open it with its tab or `/accord availability`.

- **Guild**: one row per day (Monday first), one column per hour. Each cell holds how many members are **usually online** then (up to half of the weeks, or more), out of those who share; the darker, the more. Members are counted per account, so alts are one person.
- **Mine**: your own map, with its four levels as four shades (the lightest is "never").
- **Click a cell** to see it under the grid: the day and hour, your own level, the count and how often.

## Who sees what

- **Everybody** sees how many members are online in each hour.
- **Who** they are, Accord shows only to **officers and the Guild Master**, and to you your own entry. This is a rule of the interface: the maps themselves reach the whole guild.

## Sharing

**Share when I usually play** is **on by default**. The switch is on the *What I share* page and in the Contacts card of [[Settings|Settings]].

- On: your 168 levels and the number of weeks measured are sent to the guild when they change: at most once a day in the first week, then **at most once a week**. A map is kept for 30 days.
- Off: the map you shared is **withdrawn** (an empty record replaces it) and nothing more is sent. Your own map keeps counting on your computer, so you still see it under *Mine*.

The minute counts never leave your computer: only the levels do. They are not part of the [[backup|Settings]].

## With Finland Dragon Credit Points

When FDCP is the guild's source of the season roster, officers also see, under the chosen cell, the members who **declared** that day in FDCP. It is labelled as a declaration of whole days, not a measurement, and it is never added to the counts. See [[Raid and loot addons|Raid-and-Loot-Addons]].
