# Action Center

*Italiano: [[Centro azioni|Action-Center-it]]*

> **New in `v0.9.0`**. Nothing on this page has been checked in the real game.

The **Action Center** is one list of the things that **wait for you**: you do not have to look through every view to find them. Open it with its tab, the first one of the Accord panel, or with `/accord inbox`.

It keeps nothing of its own and decides nothing for you. Every line is read from the view it belongs to: **click it** to open that view and act there. When the thing is done, the line is gone.

## What is listed

| Line | Who sees it | A click opens | It goes away when |
|---|---|---|---|
| *Bank request: …* and *Deliver: …* | officers and the Guild Master | the **Inbox** of the [[Guild Bank|Guild-Bank]], on that request | the request is decided, delivered, cancelled or expires |
| *Waiting for an officer: …* and *Approved: …* | you, for your own requests | your own requests in the Bank view | the request is closed |
| *You asked … to craft …* | you, after **Request craft** | that member's recipe list | you press **Done**, or after 7 days |
| *3 promotions to do in the game* (also demotions, removals and notes) | officers and the Guild Master | the **Queue** page of the [[Officers tab|Guild-Roster]] | nothing of that kind is left in the queue |
| *… is back (away until …)* | officers and the Guild Master, from the return day to three days after | the **Inactive** page | three days after the return |
| *Your absence ends on …* | you, within three days of the end | the **Absence** card of [[Settings|Settings]] | after the return |
| *… wants to join as …* | you, as the leader of a [[group|Groups]] | the **My group** page of Groups | you accept or decline, or the group closes |
| *PvP rally: …* and *World rally: …* *(from `v0.10.0`)* | everybody, while the [[rally|Events]] is open | the **Rallies** page of Events | the rally ends or is closed |
| *Trial of … ended on …: decide* and *… left the guild during the trial* *(hidden until M12 is complete)* | officers and the Guild Master, from the end day | the **Trials** page of the [[Officers tab|Guild-Roster]], on that trial | an officer closes or extends the trial |
| *Welcome checklist: 2 of 4 done* *(hidden until M12 is complete)* | you, as a new member | the [welcome checklist](#welcome-checklist), on top of the same page | every item is done, you press **Dismiss**, or 30 days after you joined |

An officer who asks the bank for something sees the request twice: to decide it, and as their own reminder.

A craft request is only a whisper that you send yourself (see [[Professions and Recipes|Professions-and-Recipes]]): the crafter is not told by the addon. The line is **your own reminder**, kept on your computer and never sent to anybody, at most 20 of them. It is also kept if you decide not to send the whisper: press **Done** to remove it. Orders that the crafter sees come with a later milestone (M13).

## Welcome checklist

> *Hidden until M12 is complete.* Nothing of it has been checked in the real game.

If you have just joined the guild, a **Welcome** card appears on top of the Action Center and a chat line tells you about it. It lists up to four things to do; each one **ticks itself** when done, and stays ticked. Click an item to go where you can do it.

| Item | Done when | Not listed when | A click opens |
|---|---|---|---|
| *Read the guild info and rules* | you have read both pages of the [[handbook|Guild-Handbook]] (or the one that exists) | the guild has written neither | the first page you have not read |
| *Choose your main* | you picked your main, or your account has one character | | the **Main character** card of [[Settings|Settings]] |
| *Add your Discord name* | your Discord name is saved (or the game gives it) | | the **Contacts** card of Settings |
| *Declare for the season* | your account is in the [[season roster|Season-Roster]], also as *Not sure yet* (with FDCP: one of your characters is in its pool) | no season is open, or FDCP is the source and is not loaded | the Season view, or FDCP |

- **Who gets it**: a character that joined **after** Accord already saw the guild. The addon knows this when it saw your character change guild, or when the game's guild log shows you joined in the last 14 days (not yet checked that the game offers that log to addons). Whoever was already in the guild when it started using Accord does not get it, and neither does an alt of an account already in the guild. The card can take a few minutes to appear, until your computer has received the guild's data.
- **Dismiss** closes it for good on that character. It also goes away by itself 30 days after you joined, and from the next login once everything is done.
- `/accord welcome` opens the list at any time, for anyone.
- It stays **on your computer**: nothing is sent, and officers do not see what you have ticked.

## Order and colours

Each line has a coloured dot for its urgency:

- **Now** (red): somebody is waiting for you right now, or it expires within a day, such as an applicant to your [[group|Groups]];
- **To do** (accent colour): it is your turn;
- **Reminder** (grey): you are waiting for others, or it is just worth remembering.

The most urgent come first; among equals, what has been waiting longest. The number on the tab counts the lines that are **Now** or **To do**, and the tooltip of the addon in the AddOn Compartment says *Action Center: N to do*.

The chips on top show **All** lines or those of one kind: *Groups*, *Bank*, *Crafting*, *Officers and absences* (and *Rallies*, from `v0.10.0`). When one kind has more than 50 lines, a last line says *and N more*; the list holds at most 200. With nothing to show it says *Nothing waits for you.*

## Notices

> **New in `v0.9.0`**. Nothing of the notices has been checked in the real game; in particular, which sounds the game offers.

The second page of the Action Center, **Notices**, is the history of what the addon told you, the newest first. The name of the page shows how many you have **not read**: *Notices (3)*.

- A notice is read when you **click** it (it also opens the view it is about) or with **Mark all read**. Nothing is marked read by itself.
- The chips show **All** notices or only the **Unread** ones. **Clear** empties the history: click it, then click again within 8 seconds.
- The history keeps at most 200 notices and 30 days, on your computer, one history per guild. It shows the notices of this character and those for your whole account.
- *muted* marks a notice you switched off: it was not shown in chat or on screen, but it is kept here.

| Notice | Who gets it | Shown by default |
|---|---|---|
| *New bank request from …* | officers and the Guild Master | a chat line |
| *Your bank request (…) was approved / rejected / fulfilled* | you, for your own requests | a chat line |
| *… is back (away until …)* | officers and the Guild Master | here only |
| *You received … likes* (the number, never who) | you | here only |
| *… wants to join as …* | the leader of a [[group|Groups]] | a chat line and an on-screen box |
| *… accepted you* / *declined your application* | the applicant | a chat line and an on-screen box |
| *New group: …* | you, for a group that fits your filters | **off** (here only) |
| *… calls a PvP rally at …* (or a world rally) *(from `v0.10.0`)* | everybody but the caller | a chat line |
| *Trial of … ended on …: decide* *(hidden until M12 is complete)* | officers and the Guild Master, once per trial on its end day | a chat line |

### Chat, screen or sound

In [[Settings|Settings]], card **Notifications**, choose for the bank notices and for those of the groups any of:

- **Chat line**: one line starting with `Accord:`. Notices that arrive together are printed together, three lines at most and *and N more*.
- **On-screen notice**: a small box at the top of the screen for 6 seconds. Click it to open its view, right-click to close it. One at a time; when many are waiting they are summed up in one box.
- **Sound**: a sound of the game, at most one every 10 seconds. It is off by default.

The two switches for new requests and for decisions are the same as before, with the same default (on). With all three outputs off, the notices only go to the history.

### No floods

- The first time the addon runs in a guild, what is already there is not announced.
- In the first minutes after you log in, notices of one kind are grouped (*5 new bank requests*) and shown once, when that time ends (at most 5 minutes after the login).
- More than 20 notices of one kind in a minute become one.
- After 30 notices in one session the others only go to the history, and one line says *More notices in /accord inbox*.

## Quiet hours

> **New in `v0.9.0`**. Nothing of the quiet hours has been checked in the real game.

A notice **waits** instead of showing in chat, on screen or with a sound:

- while you are **in combat**, always;
- while you are in a **dungeon, raid, battleground, arena or scenario**: the switch *Also in dungeons, raids and battlegrounds*, on by default, which works also with the quiet hours off;
- during your **quiet hours**: the switch *Quiet hours*, **off by default**, with *From* and *To* (23:00 and 8:00 if you do not change them), in the time of your computer. *From* 23:00 *To* 8:00 means from 23:00 to 7:59.

Set them in [[Settings|Settings]], card **Notifications**. The history of the **Notices** page has every notice at once, also while it waits.

When nothing holds them any more, the waiting notices come out **once, in the order they arrived**: 3 seconds after combat, 5 seconds after leaving the instance, within a minute of the end of the quiet hours. They come together: three chat lines at most and *and N more*, one on-screen box and one sound at most. A notice you have read meanwhile, one that is no longer true, or one that waited more than 12 hours stays in the history only. So do the waiting notices if you reload the interface or log out.

## Summary at login

> **New in `v0.9.0`**. Nothing of the summary at login has been checked in the real game.

A few seconds after you **log in** (not after a `/reload`), the addon says what changed **since your last session** in this guild:

| Line | What it counts | A click opens |
|---|---|---|
| *2 new members: …* | who joined, with up to three names | the Roster |
| *1 member left: …* | who is no longer in the guild | the Roster |
| *3 things wait for you* | the **Now** and **To do** lines of the Inbox | the Inbox |
| *You received 2 likes* | **the number only, never who gave them** | Reputation |
| *Bank: +120g, 14 movements* | the change of the guild's gold and the new entries of the bank logs you may see | the Bank |
| *5 unread notices* | the notices you have not read | the **Notices** page |

A line is there only when it is not zero. **When nothing changed there is nothing**: no chat line, no card, no sound. Things that were already waiting at your last session do not bring up the summary by themselves; they are counted when something is new.

- The lines are on the card **Since your last session** at the top of the Inbox page. Click one to open its view. **Close** takes the card away; otherwise it stays until your next login.
- One chat line sums them up with numbers only: *Accord: since your last session: 2 new members, 2 likes. /accord inbox*. It waits during combat, in instances and in your quiet hours. To switch it off: [[Settings|Settings]], card **Notifications**, *Summary at login*.
- What guild members did while you were away reaches your computer over the first minutes: the card is completed for about two and a half minutes after the login. If there was nothing to say at first, the chat line comes at the end of that time. What arrives later is not in the summary.
- With more than 50 members joined and left together, or after more than 90 days away, the roster lines give numbers without names.
- The first time in a guild there is no summary: the addon only remembers how things are.
