# 0026. Recruitment copied by hand, trials among officers, onboarding local, mentors opt in

- Status: Accepted
- Date: 2026-11-26 ([M12.1](../roadmap/M12-recruitment.md), [SPEC-16](../specs/SPEC-16-recruitment-trials-mentors.md))

## Context

M12 helps a guild recruit and welcome people: a recruitment text built from the season roster's gaps (M10) and the handbook (M11), trials that officers follow, a welcome checklist for new members, and mentors suggested from co-play and the social graph. Each part touches something sensitive:

- **Posting.** A recruitment text belongs in public channels (trade, looking for group, Discord). An addon that posts there by itself would spam, would break the game's rules on automated messages, and would speak for the guild without an officer choosing the moment.
- **Trial feedback.** Notes about a person on trial are officer opinions, like the extended notes of M8; the person must not receive them, not even hidden in their saved variables.
- **New members.** Knowing who is new, and how far they got with a checklist, would need data that travels for every tick.
- **Mentors.** Suggesting pairs reads who plays with whom. Putting people forward without their consent, or showing everybody who plays with whom next to the new members, would turn the social index into a judgement (SPEC-10 R7).

## Decision

1. **The addon never posts.** The recruitment text is built on the client every time (head, a description from the handbook's *Guild info* page, the MS1 gaps against the target composition, a contact and an extra line that the officer keeps on their own computer) and shown in a read-only box to copy, as one chat line of 255 bytes or a Discord text of 1900 characters. No module of M12 calls a function that sends a chat or Battle.net message; a test fails if one does. Only officers and the Guild Master open it (one constant).
2. **Trials are an officer-only data set.** `trials` follows every rule of ADR 0023 and SPEC-12 §1 (restricted records, officer senders, `OFFICER` and officer whispers only, local until the officer channel is proven, deleted when the account is no longer an officer). One record per trial (start, length, end, state; extended or closed, never reopened) and one note per officer per trial with the limits of M8.5. The Action Center row and one notice appear on the end day; a decision is taken by hand in the game, Accord only records it.
3. **Onboarding is local.** The new member's own client decides that the character is new (it saw the guild change, or the game's guild log says so, and the guild used Accord before), shows the checklist, ticks items from data it already holds, and sends nothing. Officers do not see the progress.
4. **Mentors opt in; pairs stay on officers' clients.** A data set `mentor`, one record per account, written only by its own account from a click, off by default, left with one click (`off`, delivered to everyone). The list is public. Suggested pairs are computed on an officer's client from the co-play graph, shared companions, the group map and availability, never stored or sent, and nobody is told of a pair.
5. Everything is behind a new switch `recruit`, off until M12.6, which does not turn on other switches; each part that reads M10 or M11 asks for their switch and says what is missing.

## Alternatives considered

- **A "Post" button that sends the text to a chosen channel.** Convenient, but automated posting, and one click away from spamming trade chat from every officer; copying is a second of work.
- **Trials visible to the member** (a "you are on trial until" line). Clearer for the member, but it would split the record in a public and an officer part, and a guild with a trial rank already says it in the game; kept as an option for the owner (SPEC-10 Q35).
- **A shared onboarding record** so officers see who finished the checklist. More traffic for each tick, and it turns a welcome into a check (SPEC-10 Q36).
- **Mentor pairs as records** (accepted by both, visible to the pair). Makes mentoring a formal relation with its own states and notices; the owner may ask for it later (SPEC-10 Q38).
- **Mentors chosen by officers.** Faster, but it puts people forward without their consent.

## Consequences

- Positive: nothing of M12 posts or reaches non-officers that they should not see; the shared traffic grows only by two small data sets written by clicks, outside the first exchange (SPEC-09 §7, SPEC-10 Q26); a member can leave the mentor list at any time.
- Negative: officers paste the recruitment text themselves; the member does not know from Accord that they are on trial; the checklist appears by itself only when the client can tell the character is new (the game's guild log is not in the Forever dump, SPEC-10 R19); the officer-only pairs are an interface rule over co-play data every client has (SPEC-10 R20).
