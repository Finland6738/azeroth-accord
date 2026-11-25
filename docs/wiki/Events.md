# Events

*Italiano: [[Eventi|Events-it]]*

> **Arrives with `v0.10.0`.** The Events view is in the code and switched off until milestone M10 is complete; no released version has it, `v0.9.0` included. Nothing on this page has been checked in the real game. What follows describes how it will work.

The game calendar is the guild's shared ground for events. Accord **does not keep its own copy** of the calendar: it reads the guild's events from the game calendar and writes your answer **into the game calendar itself**. So the game, Finland Dragon Credit Points (FDCP) and the other addons all see the same answer, wherever you gave it.

## The Events view

Open it with its tab or `/accord events`.

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

## Without the game calendar

Only when your client has **no usable calendar** (the game gives no event list within a minute), officers and the Guild Master can create an event in Accord: a title, the date and time (`YYYY-MM-DD HH:MM`) and the raid size. Members answer it in Accord. These events are always marked **Not in the game calendar**, also for members whose game has a calendar, and the game, FDCP and the other addons do not see them. When FDCP is the guild's source, the event says that **answers given there do not count for FDCP**, which reads sign-ups from the game calendar only.

## What is shared

- Your answer to a calendar event is **in the game calendar**, as if you had answered in the game.
- Your **role** for an event, and your answers to events kept only in Accord, reach the whole guild like the other guild data, and are listed in *What I share* (see [[Privacy and Data|Privacy-and-Data]]). They are removed 2 days after the event.
- Accord never answers for somebody else, and it records **no attendance**: nothing says who was at a raid.
- During a boss fight Accord sends nothing but its short urgent messages, as FDCP does.
