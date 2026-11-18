# 0003. An Accord tab in Blizzard's guild window, with a standalone window as fallback

- Status: Accepted (to verify in M0, check S1)
- Date: 2026-11-18 ([SPEC-04](../specs/SPEC-04-ui-guild-tab-shell.md))

## Context

The owner wants the addon to live where players already look: the guild window (`CommunitiesFrame`), which has four side tabs (Chat, Roster, Guild Benefits, Guild Info). A fifth tab with the addon's icon should open the Accord panel. Blizzard's frames are protected code: changing their state from an addon can spread *taint* and break protected actions (invites, promotions) in the same window.

## Decision

1. The addon creates **its own tab button**, parented to `CommunitiesFrame`, anchored under the last visible Blizzard tab and shown only when the guild is the selected club.
2. Clicking it shows **the addon's own panel** over the content area of the window. The addon **never calls** Blizzard's `SetDisplayMode` and never replaces Blizzard functions: it only observes them with `hooksecurefunc` / `HookScript`, so that clicking a Blizzard tab hides the Accord panel.
3. The same panel can also open in a **standalone window** (`/accord`, the AddOn Compartment, a key binding). This is the fallback if S1 finds taint or layout problems, and the way to use the addon while the guild window is closed.

## Alternatives considered

- **Replacing a Blizzard tab or the display mode.** Taint risk in a window that hosts protected actions.
- **A standalone window only.** Works always, but the owner explicitly asked for the tab.

## Consequences

- Positive: the addon feels part of the game; Blizzard's code stays untouched.
- Negative: the content area is small for wide tables, so the panel offers a "pop out" to the standalone window; Blizzard layout changes can move the anchor (guarded by Compat and checked at every client update).
