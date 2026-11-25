# Groups

*Italiano: [[Gruppi|Groups-it]]*

> **New in `v0.9.0`**, the next release. Nothing on this page has been checked in the real game; in particular the invitation sent by the addon, also inside an instance.

The **Groups** tab is the game's premade groups panel, **for your guild only**: a leader posts a group, guild members apply with a role, the leader accepts them and they are invited. Open it with its tab or with `/accord groups`. Nobody outside the guild sees a group, and only members who use the addon take part.

The tab has three pages: **Groups** (the list), **Post a group** and **My group**.

## Finding a group

Each row shows the type, the activity, the levels, the roles still needed (shield: tank, cross: healer, sword: damage), the players already there out of the size, the leader, when it was posted, the time left and its state. The newest come first. Hover a row for the note and the meeting point.

Filters:

- the **type** chips: *All*, or any of *Dungeon, Raid, Quest, Elite, PvP, Farming, Professions, Help, Other* together;
- **All activities** or one of those listed now;
- **Fits my level**, on by default;
- the **roles** your class can take: choose one or more to see only the groups that still need them;
- the search box at the top: activity, leader, note and meeting point.

The type, level and role filters are saved on your computer.

A group that closes stays in the list, grey, for 10 minutes: *Full*, *Expired*, *Leader offline*, *Replaced* or *Closed*.

## Applying

Click a row. Under the list, choose a role, write a short comment if you like (60 characters) and press **Apply**. The role is already chosen for you: the role you saved in the game's Group Finder if the group needs it, else your role in your current party, else the first role your class can take.

The application goes **by whisper to the leader only**: nobody else knows you applied. The panel and the list then say *Applied as healer, waiting*, then *Accepted: watch for the invitation* or *Declined*. **Withdraw** takes a waiting application back. You can have 3 applications waiting; after a *Declined* you wait 10 minutes before applying to the same group again. The invitation is the game's own: you accept it yourself.

## Posting a group

On **Post a group** choose:

- the **type**; for a dungeon or a raid the instance (those for your level come first), for the others a few words (a quest, a zone, a battleground...). A **Help** group says only the zone, filled in with where you are;
- the **levels**, the **group size**, how many are **in the group** already (empty: your current party) and how many **tanks, healers and damage** you still need, no more than the free places;
- a **note** (80 characters) and a **meeting point** in words (40): the addon never shares your position;
- how long the group stays listed: 30 minutes, 1, **2** or 4 hours.

Press **Post**. You have one open group per character: if you already have one, the button asks you to click again to close it and post the new one. With a group open, **Update** changes the roles, the players, the levels, the note and the meeting point, and **Close group** closes it.

A group also closes by itself when nobody is needed any more or the party is full, when its time ends, and when you log out (a `/reload` does not close it).

## My group: the applicants

The **My group** page lists who applied, with class, level, role, comment and how long ago; the number of applicants shows on the tab. **Accept** invites the player to your party and takes one off the role they chose; **Decline** tells them no. The addon never accepts anybody by itself and never invites without your click.

- Only the leader of the party or raid can invite.
- With 5 players in a party and a larger group size, *Convert your party to a raid first*: the addon never converts it for you.

## Also in the game's Group Finder

If the game lets a group be listed **privately**, **My group** has a button **Also list in the game's finder** next to *Close group*. One click of yours puts the same dungeon or raid group in the game's own Group Finder as a **private group**: your guild sees it there, and so do **your friends outside the guild** (the button's tooltip says so). The addon:

- never lists a group **publicly**, never writes a title or a comment there, and never lists anything without your click;
- offers the button only to the leader (or a player alone), outside combat, for a dungeon or raid the game's finder knows;
- removes it in the same click that closes your guild group (*Close group*, a new post that replaces it, an *Accept* that fills it). When the guild group closes by itself, a notice asks you to remove it, and the button becomes **Remove from the game's finder**;
- if the game ever shows the group as public, asks you to remove it and does not offer the button again on that version of the game.

Players who apply from the game's Group Finder are handled in the game's own window. If the game does not allow private listings, there is no button and no text: the guild group finder is the only one. Whether WoW Forever allows them has not been checked in the game yet.

## Notices and the Action Center

With the [[Action Center|Action-Center]]:

- every waiting applicant is a **Now** line of the Inbox, which opens **My group**;
- a notice tells you about a new applicant, and about the leader's answer to your application (chat line and on-screen box by default);
- the notice of a **new group that fits you** is **off by default**. Switch it on in [[Settings|Settings]], card **Notifications**, *New groups that fit my filters*. It counts the types of your saved filters, your level and the roles you chose (or any role your class can take), and comes at most once every 5 minutes. While it is off it is only kept, marked *muted*, in the history.

Like every notice, these wait during combat, in instances and in your quiet hours.

## What is shared

A group you post is sent to the guild and disappears 10 minutes after it ends; it is not kept in backups or exports. An application goes only to the leader and is kept on the two computers until the group closes. See [[Privacy and Data|Privacy-and-Data]].
