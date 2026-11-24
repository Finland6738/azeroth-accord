# 0023. Officer tools observe and suggest; officer data stays among officers

- Status: Accepted
- Date: 2026-11-24 ([M8.1](../roadmap/M8-officer-tools.md), [SPEC-12](../specs/SPEC-12-officer-tools.md))

## Context

M8 gives officers a roster timeline, inactivity counted per account, a cleanup review, a queue of manual actions, longer officer notes and exports. Two questions shape all of it. First, should the addon act on the roster (promote, demote, remove, set notes)? Those calls are protected or need a hardware event, they are the most destructive thing a guild tool can do, and a bug or a forged message would hurt real people. Second, where does officer data go? Notes about members, absences and the observed history must never reach ordinary members, but the `OFFICER` addon channel (spike S5) is not yet proven on WoW Forever, and the existing fallback for the likes salt (whispers between officers) would make officer data travel whenever S5 fails.

## Decision

1. **Observe and suggest, never act.** Accord never calls a function that changes the roster (`GuildPromote`, `GuildDemote`, `GuildUninvite`, `C_GuildInfo.SetNote`, `C_GuildInfo.RemoveFromGuild` and the others listed in SPEC-12 OPS-01), directly or through a macro or a chat command it sends. The cleanup review only fills a **local queue**; the officer does each action by hand in the game window, and a queued action is ticked when the roster shows it done. A static test fails when one of those names appears in the addon's code.
2. **Officer-only data sets.** The timeline, declared absences, extended notes and the inactivity tiers are four new data sets (`timeline`, `absence`, `onotes`, `ocfg`), all restricted: a member's client refuses them, an officer accepts them only from an officer sender (the author may have been demoted since). The one exception is a member's own declared absence, which its account sends first hand by whisper to an online officer.
3. **Only `OFFICER`, and only once proven.** These records travel only on `OFFICER`, or by whisper to a character that is an officer in the sender's roster, and the transport checks it again when the message really leaves the queue. Until the client has seen an addon message arrive on `OFFICER` in this session (capability `officerAddonChannel`), they stay on the computer that wrote them: **no whisper fallback**, unlike the likes salt. Their summary is a new field `m` of `OHELLO`, by group (month of the timeline, bucket of the notes) rather than by author, so older officer clients see nothing they do not understand.
4. **A demoted officer loses them.** When no character of the account in the guild is an officer any more, the client deletes the officer data it holds, except the account's own declared absence.
5. **Inactivity is per account**, from the most recent of its characters (native last online, the `seen` day of alts outside the guild, the own account's logins), and a declared absence hides an account until its return date.

## Alternatives considered

- **One-click actions** (a "Remove" button that calls `GuildUninvite`). Protected or hardware-event calls may be blocked by the client, and an addon that kicks members on its own can be abused by a forged record or a bug. A manual queue costs officers a few clicks and removes the risk.
- **Officer data by whisper while S5 is unproven** (as the salt). It would work on more servers, but a whisper to the wrong character, a stale rank or a renamed member leaks notes about people. Keeping the data local until the channel is proven is the safe default; officers still get every tool on their own computer.
- **Officer data on `GUILD`, hidden by the interface.** Every member's saved variables would hold notes about them.
- **A shared queue between officers.** Two officers would race on the same action; ticking from the roster already shows each officer what another one did.

## Consequences

- Officer tools are fully useful on a single officer's computer even if `OFFICER` never carries addon messages; they become shared among officers as soon as it does.
- The cleanup takes manual steps; the queue shows the name to copy and the game's command to type.
- Officer data lives in the account-wide saved variables: a non-officer alt of an officer account does not see it but keeps it until no character of the account is an officer.
- The visibility choices, the retention of notes about former members and what exports may contain are proposals in [SPEC-10](../specs/SPEC-10-risks-open-questions.md) (Q13–Q15), each changeable in one place.
