# Interface tour

*Italiano: [[Giro dell'interfaccia|Interface-Tour-it]]*

## The Accord tab

Open the guild window (default key `J`). Under the four tabs of the game (Chat, Roster, Guild Benefits, Guild Info) there is a fifth one with the Accord logo: **Accord**. Its tooltip says *Azeroth Accord*.

![The guild window with the Accord tab selected: a fifth tab under the game's four, the panel with the navigation rail at the left, the Guild row of pages at the top, the filters and the Roster](../specs/mockups/previews/accord-tab-roster.webp)

![The same screen with numbered notes: the tab, the sync state, the navigation, the filters, the sortable columns, a row, and Pop out](../specs/mockups/img/01-accord-tab.webp)

*Design previews, not screenshots: drawn from the addon's own layout and texts with invented characters and items, because the addon has not been run in the game yet ([all previews](https://github.com/Finland6738/azeroth-accord/blob/main/docs/specs/mockups/previews/README.md)).*

- Clicking it opens the **Accord window** in the place of the guild window, which closes: the guild window is too small for Accord's wider tables. The Accord window moves, resizes and remembers where you put it. *Settings → Open Accord inside the guild window* brings back the panel described next.
- With that setting on, clicking it shows the Accord panel over the guild window (its list of communities too), in the colours of the theme, and while it is open **the window around it wears the theme too**: a themed frame with the name of your guild, a themed cross, and the five side tabs as rounded tiles (the open one has a soft filled tile). Clicking any of the game's tabs puts the game's own look back and goes back to its content; closing the window closes the panel.
- When officers have bank requests waiting, the tab carries a small red badge with their number.
- The tab shows only while your **guild** is the selected community, and not in the small (minimized) guild window.
- The panel has nothing protected in it: it opens and closes in combat too, and it never changes how the game's own tabs work: the addon only makes the game's window art see-through while the panel is open and puts it back afterwards.
- If a game update changes the guild window so much that the tab cannot be placed, the tab simply does not appear: use `/accord` for the standalone window, and `/accord debug` says why.

## The panel

The panel has **two levels of navigation**, the same in the guild window and in the standalone window *(from `v0.13.0`)*:

- **The rail** down the left side: one icon per place of the addon. Hover an icon for its name; click it to go there. The open one has its icon filled with a soft rounded shape behind it, and an icon carries a small red number when something waits there (the bank requests on *Economy*, the things to do on *Home*). **Settings** is at the bottom. Officers and the Guild Master also have **Officers**; members do not see that icon.
- **One row of tabs** at the top of each place: its name first, then one tab per page; the open page is bright with a short line under it, which slides to the tab you click. A place with a single page shows only its name. Inside a page there is never a second row of tabs: what you see in it is chosen with the filters or a **Show** menu (for example the Bank's Tabs, Items, Requests…).
- The page you opened last is remembered for each character, and the rail opens each place on the page you left it on.

| Icon | Place | Pages |
|---|---|---|
| Home | **Home** | [[Action Center|Action-Center]], Notices |
| Guild | **Guild** | [[Roster|Guild-Roster]], [[Reputation|Likes-and-Social-Index]], Mentors, [[Guild addons|Guild-Addons]] |
| Swords | **Raid** | [[Season|Season-Roster]], [[Events|Events]], [[Raid|Raid-and-Loot-Addons]], [[Availability|Availability]] |
| Group add | **Groups** | [[Group finder, Post a group, My group|Groups]], Rallies |
| Construction | **Professions** | [[Recipes|Professions-and-Recipes]] (and later Orders and the Shopping list) |
| Bank building | **Economy** | [[Bank|Guild-Bank]] (and, when M13 is complete, the Market and the Goals) |
| Celebration | **Community** | [[Handbook|Guild-Handbook]] |
| Shield | **Officers** (officers only) | Inactive, Queue, Timeline, Trials ([[Guild Roster|Guild-Roster]]) |
| Gear, at the bottom | **Settings** | [[General|Settings]], What I share, [[Info|About]] |

- At the right of the row: a **Search** box, while the open page can search (what you type goes to that page), and, in the guild window, **Pop out**, which moves the panel into its own, larger window. If the row is too narrow for every tab, the last ones are behind **More**.
- In the guild window a thin line at the bottom shows the **sync state**, for example *3 guildmate(s) with Accord online · updated 2 min ago* (the standalone window shows it under its title).
- If a page ever fails to draw, it shows a short message instead and the others keep working; clicking its tab again tries again.
- **New in `v0.9.0`:** the [[Action Center|Action-Center]], [[Groups|Groups]] and [[Guild addons|Guild-Addons]] views.
- **From `v0.10.0`**: the [[Season|Season-Roster]], [[Events|Events]] and [[Availability|Availability]] views.
- **From `v0.11.0`**: the [[Raid|Raid-and-Loot-Addons]] and [[Handbook|Guild-Handbook]] views.
- **From `v0.12.0`**: no new tab, but the [[recruitment text|Season-Roster]] in the Season view, the **Trials** page of Officers ([[Guild Roster|Guild-Roster]]), the [[welcome checklist|Action-Center]] and the **Mentors** mode of Reputation (a page of Guild from `v0.13.0`) ([[Likes and Social Index|Likes-and-Social-Index]]).
- **The views of the first release, `v0.8.0`**: **Roster**, **Professions**, **Reputation**, **Bank**, **Settings** (officers also have **Officers**, with the inactive players, the queue of actions to do by hand and the roster timeline: see [[Guild Roster|Guild-Roster]]). The **Roster** view comes with the roster version, and the **Settings** view (see [[Settings|Settings]]; the same page is in the game's settings window) with the release version; see [[Guild Roster|Guild-Roster]]. The **Professions** view (a member's recipe list, opened from the roster) comes with the professions version; see [[Professions and Recipes|Professions-and-Recipes]]. The **Reputation** view (likes, one row per player sorted by likes, with the Like button; your social index; the group map for officers; *Someone new* to play with) comes with the reputation version; see [[Likes and Social Index|Likes-and-Social-Index]]. The **Bank** view (the guild bank tab by tab, its money, a searchable list of items) comes with the bank version (officers also see the number of waiting requests on the tab); see [[Guild Bank|Guild-Bank]].

## Sorting the lists

- **Every list with columns is a table**: click a column title to sort it, click it again to reverse. The sorted title is in the accent colour with an arrow. Rows with nothing in that column go last; columns that hold buttons have no sort.
- **Lists without columns** (the handbook's pages, the suggested mentors) have a **Sort by** button: choose the order in its menu, and choose it again to reverse it.
- Each list **remembers its order for every character**.

## Buttons, filters and rows

The controls look and behave the same in every view (the rules of Google's Material 3, drawn with Accord's themes):

- **Buttons**: the one **filled** button, in the theme's accent, is the main action of a view or of a window (for example *Save* or *Send request*); the others are softly filled, outlined or plain text.
- **Filters** are rounded boxes you can switch on and off: a filter that is on is filled and shows a **check mark** (*Online*, *Mains only*, the tabs of the guild bank).
- A choice between a few things (the theme, the font) is a row of joined buttons, the chosen one filled with a check mark. They choose; they never move you to another page.
- The **selected row** of a list (the member whose card is open, the group or the handbook page you chose) is filled with the same soft colour.
- A pointer over a control shades it lightly; a control that cannot be used now is faded.

## The themes

The panel comes in three themes, chosen in **Settings → Appearance** (see [[Settings|Settings]]): **Nebula**, the dark default, **Aurora**, a light one, and **Accord**, dark with the green and gold of the logo. They change colours only: every view looks the same in all three, and the choice shows at once.

![The Roster in the light theme Aurora](../specs/mockups/previews/roster-aurora.webp)

![The member card in the Accord theme](../specs/mockups/previews/member-card-accord.webp)

*Design previews, not screenshots: drawn from the addon's own layout and texts with invented characters and items, because the addon has not been run in the game yet ([all previews](https://github.com/Finland6738/azeroth-accord/blob/main/docs/specs/mockups/previews/README.md)).*

## The standalone window

![The standalone window: the same panel in a window you can move and resize, here on the Likes of the Reputation view](../specs/mockups/previews/window-standalone.webp)

`/accord`, the AddOn Compartment entry, a key binding or **Pop out** open the same panel in a window of its own, in the colours of the theme:

- the **title bar** at the top: the round Accord logo, **AZEROTH ACCORD**, the sync state under it, **Pop in** and the close button. **Pop in** shows while the guild window is open on your guild: it puts the panel back into the guild window and closes this one. (The addon never opens the game's guild window by itself.)
- under it, the same **rail**, **row of tabs** and **Search** box as in the guild window;
- drag the title bar to move the window, and the small mark in the bottom-right corner to resize it. It opens at 1380 × 720 (smaller on a smaller screen) and cannot be made smaller than 720 × 460; it remembers its place and size for each character. Esc closes it.

Clicking the Accord tab of the guild window while this window is open moves the panel there and closes the window, so the panel is never in two places. See [[Commands|Commands]].
