# 0003. An Accord tab in Blizzard's guild window, with a standalone window as fallback

- Status: Accepted (to verify in M0, check S1)
- Date: 2026-11-18 ([SPEC-04](../specs/SPEC-04-ui-guild-tab-shell.md))

## Context

The owner wants the addon to live where players already look: the guild window (`CommunitiesFrame`), which has four side tabs (Chat, Roster, Guild Benefits, Guild Info). A fifth tab with the addon's icon should open the Accord panel. Blizzard's frames are protected code: changing their state from an addon can spread *taint* and break protected actions (invites, promotions) in the same window.

## Decision

1. The addon creates **its own tab button**, parented to `CommunitiesFrame`, anchored under the last visible Blizzard tab and shown only when the guild is the selected club.
2. Clicking it shows **the addon's own panel** over the content area of the window. The addon **never calls** Blizzard's `SetDisplayMode` and never replaces Blizzard functions: it only observes them with `hooksecurefunc` / `HookScript`, so that clicking a Blizzard tab hides the Accord panel.
3. The same panel can also open in a **standalone window** (`/accord`, the AddOn Compartment, a key binding). This is the fallback if S1 finds taint or layout problems, and the way to use the addon while the guild window is closed.

## Update (M6.18)

The owner asked that everything a player sees is in the new look, the window's name, frame and side tabs too ([ADR 0021](0021-interface-follows-the-ecosystem-style-of-fdcp.md) said Blizzard's frame stays only observed). Decision 2 stands (no `SetDisplayMode`, no replaced Blizzard function), and one rule is added: **while the Accord panel is open the guild window is dressed in the theme** (`UI/GuildSkin.lua`, GT-07). The Blizzard art of the frame (its own textures, `NineSlice`, title, portrait, the close button's art, the backgrounds of the side tabs) is made transparent with `SetAlpha(0)`, the old alpha is kept and put back when the panel closes, another Blizzard tab is chosen, the window closes or another community is selected; the themed frame, the guild's name, the cross and the tab tiles are frames of the addon. The Accord tab is a plain button, no longer Blizzard's tab template. The icons of Blizzard's tabs stay (they are what the tabs do). Risk: a layout the addon does not know (each part is looked up by name under `pcall`: it costs a part of the look, never an error) and Blizzard re-showing a part; both are to check in the real client ([the release check](../checklists/release.md), step 7).

## Update (2026-11-26, found in game)

In the real WoW Forever client the Accord tab covered the fourth Blizzard tab. Forever does not stack the side tabs in the order of their keys (`ChatTab`, `RosterTab`, `GuildBenefitsTab`, `GuildInfoTab`), so "under the last visible tab in key order" was the wrong place. The tab now goes under the **lowest tab as the window draws them**, at the **distance measured** between Blizzard's tabs, and anchors again on the next frame, once positions are known. It falls back to key order and a 20-point gap when positions are not known yet. `/accord debug` lists each side tab's position and the chosen anchor. The owner also asked for the **game's tab frame with the Accord logo inside**: the tab is made from `CommunitiesFrameTabTemplate` again, and the M6.18 tile is only the fallback when the client refuses the template. While the panel is open the theme draws the Accord tab like Blizzard's (GT-07).

## Alternatives considered

- **Replacing a Blizzard tab or the display mode.** Taint risk in a window that hosts protected actions.
- **A standalone window only.** Works always, but the owner explicitly asked for the tab.

## Consequences

- Positive: the addon feels part of the game; Blizzard's code stays untouched.
- Negative: the content area is small for wide tables, so the panel offers a "pop out" to the standalone window; Blizzard layout changes can move the anchor (guarded by Compat and checked at every client update).
