# 0009. Guild bank: shared snapshots and requests approved by officers

- Status: Accepted (to verify in M0, check S9)
- Date: 2026-11-18 ([SPEC-08](../specs/SPEC-08-guild-bank.md))

## Context

The owner wants to see the guild bank from the guild window, request withdrawals and deposits, and see donations. The game exposes bank contents only while the bank is open at the vault (`QueryGuildBankTab`, `GetGuildBankItemInfo`), and only for the tabs the player's rank can see. The logs (`GetGuildBankTransaction`, `GetGuildBankMoneyTransaction`) hold a limited, recent history.

## Decision

1. **Snapshots.** Whenever a member with the addon opens the bank, the addon reads every tab it may view, the money and the logs, and shares a snapshot per tab with its time. The newest snapshot per tab wins.
2. **Permissions are respected.** A tab that only some ranks can view travels only on `OFFICER` (if officers only) or is not shared at all; the default follows the game's tab permissions (open question Q4 for the owner).
3. **Logs accumulate.** Log entries are merged over time (deduplicated by type, name, item, amount and the hour bucket) to keep a donation history longer than the game's.
4. **Requests.** Members create withdrawal, deposit and donation requests visible to the guild; only officers change their status (approved, rejected, fulfilled), which is an authority record (ADR 0005). Handing the item over stays manual (mail or trade).

## Alternatives considered

- **Reading the bank remotely.** Not possible with the game API.
- **Sharing all tabs to everyone.** Would bypass the guild's own permissions.

## Consequences

- Positive: an always-available view of the bank, a donation history, a transparent request flow.
- Negative: the view is only as fresh as the last visit to the bank; the age of each tab is always shown.
