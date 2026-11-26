# 0025. Guild handbook: pages written by chosen ranks, shared once on GUILD, past revisions kept locally

- Status: Accepted
- Date: 2026-11-26 ([M11.1](../roadmap/M11-loot-handbook.md), [SPEC-15](../specs/SPEC-15-guild-handbook-loot.md))

## Context

M11 adds the guild handbook: text pages (guild info, rules, FAQ, raid, roster and loot management) that officers write in game and every member with the addon reads, also offline. Pages are far larger than any record so far (up to 4000 bytes of text, about 2.7 KB on the wire after compression, against a few hundred bytes for most records), they keep their last few revisions, and they come from a group of writers that the guild chooses, not only from officers.

Three things in the existing sync (SPEC-02 §4) do not fit them:

- **Whisper pushes.** A client that is ahead pushes the missing records by whisper to each `HELLO` sender. For a whole handbook (6 to 22 KB on the wire) that is one copy per client that logs in, on top of the first exchange of the availability maps that already goes over the traffic budget (SPEC-10 R17, Q26).
- **Old clients.** A `v0.10` client does not know the set: its digest of a writer would differ from a `v0.11` client's forever, and they would keep asking each other, as M9.9 found for the addon census.
- **Revisions.** Keeping past bodies in synced records would multiply the traffic by the number of revisions, for a feature only writers use.

## Decision

1. **A data set `handbook`, one record per page** (`P:<slug>`: title, body, order, a template flag; deletion is a record with `del` kept for ever, so a deleted page never comes back). The record's `rev` is the page's revision; `Store.Compare` decides between two edits of the same revision (the newer `time` wins), so every client keeps the same one.
2. **Writers are chosen by rank.** The Guild Master and officers always, plus the ranks the officers choose in a `guildcfg` record (`handbook`, rank index with its name; a renamed or reordered rank stops counting until chosen again). The default is in one constant, `Handbook.WRITERS = "officers"`. A page from a non-writer is refused (`authority`); a page stays valid after its author lost the rank (`authorAny`), and officers relay pages like other records.
3. **Pages travel on `GUILD`, once for everybody who waits.** The set has its own summary entry per author (key of `"#" .. GUID`, fields `hb` in `HELLO` and `DIGEST`, `hbb` in `BHELLO`), which older clients ignore. Nobody pushes pages by whisper: a client that is behind asks (`REQ` with `s = "handbook"`), the answer goes on `GUILD` with the queue key per author and set, and every client waiting for the same pages takes them from that one send. A large page goes alone in its `REC`, compressed, in AceComm parts, at `BULK` priority.
4. **Past revisions never travel.** Each client keeps the last five versions it saw of each page, locally; restoring one writes a new revision. A writer whose edit lost a conflict keeps their text locally and is told (a notice and an Action Center row).
5. **The text is plain and inert.** A small line format (two heading levels, lists, links between pages); no game escape codes (`|`) are stored or accepted, the reader escapes HTML before SimpleHTML shows it, and web addresses are only text to copy.
6. **Loot stays described** (SPEC-10 Q6, ADR 0022). The loot page adds a `guildcfg` record `loot` (the guild's loot system and loot addon, chosen by officers), written together with the loot source of ADR 0022 so the two never disagree; who has the addon comes from the census (M9.9) with its visibility rules; the download address of a known addon is in Accord's code, and an officer's address for another addon is accepted only from a short list of addon sites. FDCP's rules summary is shown beside the page, read live, never copied into it.
7. Everything is behind the switch `raid`, which M11.8 turns on.

## Alternatives considered

- **Use the normal per-author sync with whisper pushes.** Simplest, but a whole handbook per login, and endless repair with `v0.10` clients.
- **Bodies only on demand when a page is opened.** Almost no traffic, but members could not read offline what they never opened, and the "updated" mark would need a separate index.
- **Split bodies into part records** (`P:<slug>:<k>`). Independent retries for each part, but a page would be shown only when all parts of one revision are there, and a conflict could mix parts of two edits. AceComm's own parts and a retry at the next `HELLO` are enough for pages of a few KB.
- **Synced revisions.** Every writer could restore any revision, at several times the traffic; kept as an option for the owner (SPEC-10 Q28).
- **Templates written automatically at login.** Two writers logging in together would both write, and a guild that does not want them would get them; a writer's click seeds them once.

## Consequences

- Positive: the traffic of a handbook is one send per page per wave of requests, not per client; `v0.10` clients are not disturbed; a conflict never loses text; the guild decides who writes.
- Negative: the history of a page depends on what each client saw (a writer who was offline across two edits cannot restore the middle one); a lost AceComm part delays a page until the next `HELLO` of a holder (up to 25 minutes); rank-based writers depend on the rank indices of the roster; SimpleHTML and the multi-line edit box are not verified in the Forever client yet (M11.8).
