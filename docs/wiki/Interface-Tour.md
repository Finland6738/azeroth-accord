# Interface tour

## The Accord tab

Open the guild window (default key `J`). Under the four tabs of the game (Chat, Roster, Guild Benefits, Guild Info) there is a fifth one with a guild tabard icon: **Accord**. Its tooltip says *Azeroth Accord*.

![The guild window with the Accord tab selected: a fifth tab under the game's four, the panel with its top bar, navigation and the Roster view](../specs/mockups/previews/accord-tab-roster.webp)

![The same screen with numbered notes: the tab, the sync state, the navigation, the filters, the sortable columns, a row, and Pop out](../specs/mockups/img/01-accord-tab.webp)

*Design previews, not screenshots: drawn from the addon's own layout and texts with invented characters and items, because the addon has not been run in the game yet ([all previews](https://github.com/Finland6738/azeroth-accord/blob/main/docs/specs/mockups/previews/README.md)). These pictures still show the previous look (navigation on the left, the game's colours): the panel now has tabs along the top and the colours of the chosen theme, as described below. New pictures come before version `v0.6.0`.*

- Clicking it shows the Accord panel over the content of the guild window, in the colours of the theme (the game's own window around it is not changed). Clicking any of the game's tabs goes back to it; closing the window closes the panel.
- When officers have bank requests waiting, the tab carries a small round mark with their number.
- The tab shows only while your **guild** is the selected community, and not in the small (minimized) guild window.
- The panel has nothing protected in it: it opens and closes in combat too, and it never changes how the game's own tabs work.
- If a game update changes the guild window so much that the tab cannot be placed, the tab simply does not appear: use `/accord` for the standalone window, and `/accord debug` says why.

## The panel

- **Tabs** along the top: **Roster**, **Professions**, **Reputation**, **Bank**, **Settings**. The open tab is bright with a short line under it, which slides to the tab you click. The last tab you opened is remembered for each character. The **Bank** tab shows a small count when bank requests wait for an officer.
- At the right of the tabs: a **Search** box, while the open view can search (what you type goes to that view), and, in the guild window, **Pop out**, which moves the panel into its own, larger window.
- In the guild window a thin line at the bottom shows the **sync state**, for example *3 guildmate(s) with Accord online · updated 2 min ago* (the standalone window shows it under its title).
- If a view ever fails to draw, it shows a short message instead and the other tabs keep working; clicking its tab again tries again.
- **The views, one per tab**: **Roster**, **Professions**, **Reputation**, **Bank**, **Settings**, each one as soon as the version that brings it is out. The first test version (`v0.1.0`) has no view yet: the panel shows a welcome text, while the addon already exchanges its data with the guild in the background. The **Roster** view comes with the roster version, and the **Settings** view (see [[Settings|Settings]]; the same page is in the game's settings window) with the release version; see [[Guild Roster|Guild-Roster]]. The **Professions** view (a member's recipe list, opened from the roster) comes with the professions version; see [[Professions and Recipes|Professions-and-Recipes]]. The **Reputation** view (likes, one row per player sorted by likes, with the Like button; your social index; the group map for officers; *Someone new* to play with) comes with the reputation version; see [[Likes and Social Index|Likes-and-Social-Index]]. The **Bank** view (the guild bank tab by tab, its money, a searchable list of items) comes with the bank version (officers also see the number of waiting requests on the tab); see [[Guild Bank|Guild-Bank]].

## The standalone window

![The standalone window: the same panel in a window you can move and resize, here on the Likes of the Reputation view](../specs/mockups/previews/window-standalone.webp)

*Design preview in the previous look (Blizzard-style frame, navigation on the left); it is replaced before `v0.6.0`.*

`/accord`, the AddOn Compartment entry, a key binding or **Pop out** open the same panel in a window of its own, in the colours of the theme:

- the **title bar** at the top: the round Accord logo, **AZEROTH ACCORD**, the sync state under it, **Pop in** and the close button. **Pop in** shows while the guild window is open on your guild: it puts the panel back into the guild window and closes this one. (The addon never opens the game's guild window by itself.)
- under it, the same **tabs** and **Search** box as in the guild window;
- drag the title bar to move the window, and the small mark in the bottom-right corner to resize it. It opens at 920 × 600 and cannot be made smaller than 720 × 460; it remembers its place and size for each character. Esc closes it.

Clicking the Accord tab of the guild window while this window is open moves the panel there and closes the window, so the panel is never in two places. See [[Commands|Commands]].
