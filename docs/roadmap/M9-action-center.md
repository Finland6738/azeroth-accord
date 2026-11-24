# M9 — Action Center and notifications

**Goal:**
- one place for everything that waits on the player, one history of notices, quiet hours, and a short digest at login;
- a **group finder for the guild only**, like the game's premade groups panel: a leader posts a group for a dungeon, a raid, questing or anything else, and members apply with a role;
- a **Guild addons** table: which addons the guild's members use, with a count for each.

Release: `v0.9.0`.

**Exit criterion:** in game:
- a craft request and a bank request both appear in the Action Center; nothing pops up during quiet hours or combat, and the login digest lists what changed since the last session;
- a leader posts a dungeon group needing a tank and a healer, two members apply with those roles, the leader accepts them and they are invited; nobody outside the guild sees the group;
- the Guild addons table lists the addons of the members who share them, with the right counts.

### M9.1 — Specification
- Branch: `step/m9-1-spec`
- Scope: write a new SPEC-13 ("Centro azioni e avvisi"), in Italian. It defines:
  - the provider interface modules register with, the notice levels, quiet hours and the digest;
  - the guild group finder: the `groups` data set (short-lived, written only by its leader), listing types and fields, applications, invitations, expiry, and what the game's own Group Finder allows on Forever (`C_LFGList`, `isPrivateGroup`, checked against the dump);
  - the addon census: what is shared, its switch, who sees what (SPEC-10 Q11), size limits.
- Done when:
  - [ ] SPEC-13 is linked from the spec index; `tools/check_docs.py` passes.

### M9.2 — Action Center
- Branch: `step/m9-2-action-center`
- Spec: SPEC-13
- Scope: an inbox of pending items. Modules register a provider: craft requests, bank requests and the officers' inbox now; sign-ups, trials and polls later. Each item opens its own view.
- Done when:
  - [ ] Items from three providers show in one list, sorted by urgency and date; resolving one in its view removes it.

### M9.3 — Notification centre
- Branch: `step/m9-3-notifications`
- Spec: SPEC-13
- Scope: a history of notices with read and unread, a switch per module, and a choice of chat line, toast or sound. It replaces the bank notices of M5 without changing their defaults.
- Done when:
  - [ ] The M5 options still work; a muted module produces no notice but still adds to the history.

### M9.4 — Quiet hours
- Branch: `step/m9-4-quiet`
- Spec: SPEC-13
- Scope: quiet hours set by the player; notices are held during combat and in instances, and released after.
- Done when:
  - [ ] Held notices come out once, in order, after combat or the quiet hours.

### M9.5 — Login digest
- Branch: `step/m9-5-digest`
- Spec: SPEC-13
- Scope: a short summary a few seconds after login: new and departed members, pending items, likes received (the number only), bank changes. Each line links to its view.
- Done when:
  - [ ] The digest is empty and silent when nothing changed; it never names who gave a like.

### M9.6 — Guild group finder: listings and applications
- Branch: `step/m9-6-groups-data`
- Spec: SPEC-13
- Scope: the owner asked (2026-11-24) for a group finder like the game's premade groups panel, but only for the guild and its members.
  - A **listing** has:
    - a type: dungeon, raid, quest, elite, PvP, farming, professions, help, other;
    - the activity: a dungeon or raid from a fixed table, or a quest or zone as text;
    - a minimum level;
    - the roles still needed (tanks, healers, damage);
    - a note and a meeting point as text, never an exact position.
  - Listings are synced on `GUILD` and accepted only from members in the roster. Only the leader changes or closes a listing. A listing closes by itself when the group is full, when the leader logs out, or after a time limit.
  - **Applications** go to the leader by addon whisper, with the roles chosen. The leader accepts or declines. Accepting invites the player with `InviteUnit` through Compat.
  - The "help" type replaces the help requests that were planned as M15.2: "need a hand" for a quest, a dungeon or an elite, with the zone name only.
- Tests: `Tests/test_groups.lua`: a listing from outside the guild or forged by another author is refused; applications reach only the leader; full, expired and abandoned listings close on every client; the simulator keeps the traffic inside the budget with 50 open listings.
- Done when:
  - [ ] The tests pass.
- Real client: `InviteUnit` from an addon on Forever, and the chat lockdown inside instances.

### M9.7 — Guild group finder: the view
- Branch: `step/m9-7-groups-view`
- Spec: SPEC-13; `ui-style.md`
- Scope:
  - a **Groups** tab in the style of the premade groups panel:
    - the list with filters by type, activity, level and the role the player can fill;
    - a form to post a group;
    - the leader's list of applicants, with accept and decline;
  - the role offered is preselected from the player's spec, or from the season declaration once M10 exists;
  - an Action Center item for the leader's pending applicants;
  - an optional notice, through the notification centre, for new listings that match the player's own filters and roles. It is off by default and quiet in combat and quiet hours.
- Done when:
  - [ ] A group can be posted, found, applied to, accepted and closed from the view; the wiki has a page in English and Italian.

### M9.8 — The game's Group Finder, privately
- Branch: `step/m9-8-groups-game`
- Spec: SPEC-13
- Scope:
  - if the Forever client lets a group be listed as private, visible to friends and guild members (`isPrivateGroup` of `C_LFGList`), the leader can also post the same group there with one click of their own;
  - Accord never lists a group publicly, and never lists one without the leader's click;
  - if the client does not allow it, this step records that, and the guild finder of M9.6–M9.7 stays the only one.
- Done when:
  - [ ] With the capability present, a private listing is created from the leader's click and closed with the guild listing; without it, nothing is offered.
- Real client: whether private listings exist on Forever, who sees them, and whether creating one needs a hardware event.

### M9.9 — Guild addons
- Branch: `step/m9-9-addons`
- Spec: SPEC-13; SPEC-10 Q11
- Scope: the owner asked (2026-11-24) for a tab listing the addons the guild's members use, with a count for each.
  - **Census:** each client publishes the list of its own **loaded** addons (folder name, title and version, from `C_AddOns` through Compat). It is published at login and again only when the list changes, compressed and capped in size. Blizzard's own addons are left out. A switch in Settings turns sharing off; the "what I share" panel of M7.6 lists it.
  - **Guild addons tab:**
    - one row per addon: its name, how many members use it, their share of the members who run Accord, and the versions in use;
    - search, and sorting by every column;
    - who uses a given addon, shown to those allowed by SPEC-10 Q11.
  - The count always says it is out of the members **who run Accord and share their list**. Members without Accord are not known.
  - M10.2 reads the known raid and loot addons from this census instead of keeping its own field.
- Tests: `Tests/test_addons_census.lua`: counts over many authors; an author who turns sharing off disappears from the counts; changed lists replace old ones; oversized lists are capped; old entries drop after the usual retention.
- Done when:
  - [ ] The tab shows the right counts; with sharing off nothing is sent; the wiki explains what is shared.

### M9.10 — In-game check and release
- Branch: `step/m9-10-check`
- Scope: `docs/checklists/M9.md` and the README status. The owner releases `v0.9.0`.
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.9.0`.
