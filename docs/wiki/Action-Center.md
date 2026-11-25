# Action Center

*Italiano: [[Centro azioni|Action-Center-it]]*

> **Not in a release yet.** The Action Center (step M9.2) is in the code, switched off until milestone M9 is complete: it arrives with `v0.9.0`. Nothing on this page has been checked in the real game.

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

An officer who asks the bank for something sees the request twice: to decide it, and as their own reminder.

A craft request is only a whisper that you send yourself (see [[Professions and Recipes|Professions-and-Recipes]]): the crafter is not told by the addon. The line is **your own reminder**, kept on your computer and never sent to anybody, at most 20 of them. It is also kept if you decide not to send the whisper: press **Done** to remove it. Orders that the crafter sees come with a later milestone (M13).

## Order and colours

Each line has a coloured dot for its urgency:

- **Now** (red): somebody is waiting for you right now, or it expires within a day. No line uses it yet: the first will be the applicants to your group, in a later step of M9;
- **To do** (accent colour): it is your turn;
- **Reminder** (grey): you are waiting for others, or it is just worth remembering.

The most urgent come first; among equals, what has been waiting longest. The number on the tab counts the lines that are **Now** or **To do**, and the tooltip of the addon in the AddOn Compartment says *Action Center: N to do*.

The chips on top show **All** lines or those of one kind: *Bank*, *Crafting*, *Officers and absences*. When one kind has more than 50 lines, a last line says *and N more*; the list holds at most 200. With nothing to show it says *Nothing waits for you.*

## Not yet here

The history of notices, quiet hours and the summary at login are the next steps of M9.
