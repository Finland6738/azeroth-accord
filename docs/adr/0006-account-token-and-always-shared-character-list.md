# 0006. Account identity: an account token and an always-shared character list

- Status: Accepted
- Date: 2026-11-18 ([SPEC-05 §3](../specs/SPEC-05-roster-alts-contacts.md#3-personaggi-dello-stesso-account))

## Context

The owner wants to click a character and see **all the characters of the same Battle.net account on that realm**, without asking. The game does not expose another member's account: `ClubMemberInfo.bnetAccountId` is expected to be empty for guild members (to verify in M0, S2) and the BattleNet API only describes one's own friends.

## Decision

1. Account-wide SavedVariables hold a random **account token** (created once) and the list of every character of the account that logs in with the addon on each realm.
2. The addon **always** shares this list with the guild (owner decision D3: no opt-out), together with the main character the player chose (default: the highest-level, most played character).
3. The list is first-hand data (ADR 0005): it is accepted only from one of the characters it contains.
4. Characters of a member who never installed the addon remain separate until that member logs in with it; a member may also add the alt relation in the guild note convention, read as a hint (`alt: <name>`).

## Alternatives considered

- **An anonymous count only** (as in Azeroth Guild Finder). The owner wants the names.
- **Asking players to type their alts.** Error-prone and the owner wants it automatic.

## Implementation note (M1.6)

The token travels in clear inside the shared data, so a modified client could copy another member's token. The token is therefore used only to group characters for display, never as a proof. Each character publishes **its own** account record (one record per character, written only by it), and two characters count as the same account only when each one's record lists the other (mutual listing). A client that lists somebody else's character as its alt gains nothing: that character's own record does not list it back. This is how NET-10 ("a character of the same account") is checked in `Net/Store.lua`.

## Implementation note (M2.2)

`Data/Accounts.lua` builds the groups as the connected components of the mutual-listing graph. A character outside the guild cannot publish a record, so it is shown as *claimed* by the members who list it (never as proven); a guild member listed without listing back is ignored. A group whose members publish different tokens is flagged. The note hints (`main: <name>`, `alt: <name>`) only group members who have no record of their own. Stale characters (ACC-04) are dropped only after `GetPlayerInfoByGUID` has answered for some other character of the account, so that an alt that is not played for months is never lost by mistake.

## Implementation note (M4.2)

The token is also the input of the likes' pseudonyms (ADR 0007). Because it is public, a notary refuses a vote (`conflict`) when a character outside the voter's account publishes the same token: a copy would otherwise share the voter's pseudonym.

## Note (M7.1): the guild of each listed character

By the owner's decision of 2026-11-20, the guild of each listed character is shared too, so that an alt outside the guild shows "Other guild: <name>" or "No guild" instead of a bare "not in guild". From M7.3 each entry of the list for a character that is **not** in the record's guild carries `guild` (the guild name, or empty for no guild) and `seen` (the day of that character's last login with the addon, rounded to the UTC day so that exact login times are not shared). Like the list, it is always shared (D3) and has no switch. It is as old as that character's last login, and the other guild never sees anything of Accord's data. Characters known only from a public note show no guild. Older clients ignore the two fields, and the record keeps the size limit of the set that older clients enforce (characters in the roster are kept first, because mutual listing needs them). Details: [SPEC-11 §2](../specs/SPEC-11-data-trust.md#2-la-gilda-degli-alt-fuori-dalla-gilda-m73).

## Consequences

- Positive: alts grouped without any typing, also across characters not in the guild.
- Negative: only works for members with the addon; it is personal data, documented in the wiki page "Privacy and Data". From M7.3 it includes the guild of alts outside the guild and the day they were last seen.
