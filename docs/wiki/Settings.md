# Settings

Open it with `/accord settings`, or from **Settings** in the panel's navigation. The same page is also in the game's own settings window, under *Options → AddOns → Azeroth Accord*. A change made in one place shows in the other at once, and every change is saved as you make it.

The page scrolls with the mouse wheel.

![The Settings page: contacts, main character, notifications and Roster columns](../specs/mockups/previews/settings.webp)

![The lower part of the page: the saved data sizes and Clear guild data](../specs/mockups/previews/settings-saved-data.webp)

*Design previews, not screenshots: drawn from the addon's own layout and texts with invented characters and items, because the addon has not been run in the game yet ([all previews](https://github.com/Finland6738/azeroth-accord/blob/main/docs/specs/mockups/previews/README.md)).*

## Contacts shared with your guild

- Your **BattleTag** is read from the game and shown here.
- Type your **Discord name** (user name only, 2 to 32 characters, no spaces, no links) and press *Save*. It is used only when the game does not already show your Discord name to your guildmates.

Both are **always shared with your guild**, so guildmates can reach you: there is no switch. Nothing leaves the guild. See [[Privacy and Data|Privacy-and-Data]].

## Main character

Pick which of your characters is your **main**. It leads your characters in the grouped Roster and on the member card ([[Guild Roster|Guild-Roster]]). Until you pick one, the highest-level character leads. The menu lists the characters of your account on this realm.

## Notifications

| Option | Who sees it | Default |
|---|---|---|
| Tell me in chat about new bank requests | officers only | on |
| Tell me in chat when my bank requests are decided | everyone | on |

These are single chat lines (never a flood at login). Switching them off does not hide anything: the counter on the Accord tab and the Bank view always show what is waiting ([[Guild Bank|Guild-Bank]]).

## Roster columns

Tick the columns the Roster table shows; the name column is always there. *Default columns* puts them back. The choice is saved **per character**.

## Saved data

Shows how big the addon's saved data is on your computer (estimates of the saved file): the account, this character and the current guild, with one line per kind of data of the guild and its number of records. It contains no names.

**Clear guild data** forgets everything the addon holds about the current guild and asks your guildmates to send it again. Click it once to see how much will be freed, then click again within 8 seconds to clear (otherwise it is cancelled).

It **keeps** what only your computer knows and the guild cannot send back: your likes (so you cannot give the same like twice), the guild's likes key if you are an officer, the bank's money history and which bank notices you have already seen. It never touches your account data (your characters, your main, your Discord name), your settings or the data of another guild. It is safe to use when the data looks wrong or too big; the guild refills it within a few minutes of guildmates being online.
