# Events

*Italiano: [[Eventi|Events-it]]*

> **From `v0.10.0`**: no earlier version has it. Nothing on this page has been checked in the real game. What follows describes how it should work.

The game calendar is the guild's shared ground for events. Accord **does not keep its own copy** of the calendar: it reads the guild's events from the game calendar and writes your answer **into the game calendar itself**. So the game, Finland Dragon Credit Points (FDCP) and the other addons all see the same answer, wherever you gave it.

## The Events view

Open it with its tab or `/accord events`. The [**Rallies**](#pvp-and-world-rallies) are described on this page too; from `v0.13.0` they are a page of the **Groups** icon of the rail.

- **The event picker**: the guild's events of the game calendar from 7 days ago to 14 days ahead, **whoever created them** (an officer, the game's own window, another addon). Choosing one reads everybody's answers from the calendar.
- **Your answer**: choose your **role** and press **Sign up**, **Tentative** or **Decline**. Accord writes the answer into the game calendar and says when it is saved. An answer you give in the game's calendar window shows in Accord too.
- **The answers**: who signed up, who is tentative and who declined, with the role each one chose in Accord, and the roles signed up so far (tank, healer, melee, ranged).
- **Open game calendar** opens the game's own calendar window.

## Your role

The game calendar has no place for a role, so Accord keeps it and shares it with the guild. It is chosen for you, and you can change it before you sign up:

- from your season declaration's **MS1** (see [[Season roster|Season-Roster]]);
- from your **MS2**, when your MS1's role is already covered for the officers' target composition and your MS2's is not;
- from your **class**, if you have no declaration: **you can sign up without one**.

The role you chose for an event stays chosen.

## When Accord waits

The game has **one open event at a time**, shared by its calendar window and every addon. Accord opens an event only for a moment, to read its answers or to give yours, and closes it right after. It waits, and says so, when:

- the game's calendar window is open (answer there, or close it and try again);
- the calendar is busy with another action;
- you are in combat or fighting a boss.

If the game does not let an addon answer for you, Accord opens the game's calendar window instead: answer there.

## Raid-Helper events from Discord

Officers can paste the export of a Raid-Helper event: it shows here with the calendar event of the same date and time, or on its own, and can be written into the game calendar after a confirmation. See [[Raid-Helper events|Raid-Helper]].

## Raid and bench

Officers and the Guild Master make the **line-up** of an event of the game calendar (or of one kept only in Accord) in the same view. Everybody who has Accord sees it when they choose the event: **your place** (in the raid, on the bench, or not placed), the raid and the bench with each role, and the raid's roles against the target composition (see [[Season roster|Season-Roster]]).

Officers also see:

- **Signed up, not placed**: who signed up or is tentative in the game calendar, and the matched sign-ups of a [[Raid-Helper event|Raid-Helper]]. A *Declined* given in the game wins over Discord.
- **MS2 for a short role**: when the raid is under the target in a role, the players whose declared MS2 is that role.
- a row to **choose a player** and press **To raid**, **To bench** or **Remove**. Choose the line that says *as ... (MS2)* to place a player as their MS2. One player counts once, whichever character: placing another character replaces the first. Who changes their answer afterwards is marked *no longer signed up*.

An event that is only on Discord has no line-up: put it into the game calendar first.

### Into the game calendar

Placing a player writes **nothing** into the calendar. **Write to calendar**, then **Confirm**, writes the raid as *confirmed* and the bench as *standby*, **only for the members who have not answered in the game** (for example those who signed up on Discord only): an answer a member gave in the game is **never changed**, so who signed up in the game stays *signed up*. The other limits are those of [[Raid-Helper events|Raid-Helper]]: one write at a time, at most 40 members per confirmation, stopping at the first error. Whether the game allows these writes has not been checked on WoW Forever.

**Export** gives the line-up back to Discord with the event's sign-ups.

### With FDCP as the source

When the officers chose **FDCP** for the season roster and the line-up, Accord has no line-up of its own and nobody can write one in Accord. The view says so and, where your FDCP gives the open raid night (officers' clients), shows its raid and bench, read-only. Line-ups made in Accord before are hidden, not deleted.

## Without the game calendar

Only when your client has **no usable calendar** (the game gives no event list within a minute), officers and the Guild Master can create an event in Accord: a title, the date and time (`YYYY-MM-DD HH:MM`) and the raid size. Members answer it in Accord. These events are always marked **Not in the game calendar**, also for members whose game has a calendar, and the game, FDCP and the other addons do not see them. When FDCP is the guild's source, the event says that **answers given there do not count for FDCP**, which reads sign-ups from the game calendar only.

## PvP and world rallies

A **rally** is a quick call to the guild: "PvP at the crossroads in 15 minutes". Open the **Rallies** page of **Groups**.

- **Calling one**: choose **PvP** or **World**, write the **meeting point in words** (at most 60 characters), choose when it starts (now to 2 hours) and how long it lasts (15 minutes to 2 hours), and press **Call a rally**. Any member with the addon may call one. You have **one open rally** at a time (a new one closes the older) and can call **at most 4 in an hour**.
- **Changing it**: only the caller can, with **Change** (the start stays within 2 hours of the first call) and **Close**. Officers cannot change or remove somebody else's rally.
- **Answering**: choose the rally and press **Coming** or **Not coming**. Everybody who has Accord sees who answered what. You can change your mind.
- **It ends by itself**: at its end time it shows as ended on every client, and 10 minutes later it is removed with its answers. Nobody has to do anything.
- **Notice**: a new rally gives a chat line (the [[Action Center|Action-Center]] lets you change that, and keeps one line per open rally). Notices follow the quiet hours.
- Logging in later, you receive the open rallies of the callers who are online; who answered arrives when you open the Rallies page. A rally whose caller is offline cannot be sent to you.

**No position is ever shared.** Accord does not read where your character is and sends no coordinates and no map: the meeting point is only the text the caller writes. During a boss fight a rally or an answer waits until the fight is over.

## What is shared

- Your answer to a calendar event is **in the game calendar**, as if you had answered in the game.
- Your **role** for an event, and your answers to events kept only in Accord, reach the whole guild like the other guild data, and are listed in *What I share* (see [[Privacy and Data|Privacy-and-Data]]). They are removed 2 days after the event.
- A **line-up** (who is in the raid and who is on the bench) is written by officers, reaches the guild and is removed 2 days after the event. It is a plan, not a record of who came.
- A **rally** and your answers to rallies reach the whole guild, are listed in *What I share* and are removed 10 minutes after the rally ends. They hold no position.
- Accord never answers for somebody else, and it records **no attendance**: nothing says who was at a raid.
- During a boss fight Accord sends nothing but its short urgent messages, as FDCP does.
