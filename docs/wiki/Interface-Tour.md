# Interface tour

## The Accord tab

Open the guild window (default key `J`). Under the four tabs of the game (Chat, Roster, Guild Benefits, Guild Info) there is a fifth one with a guild tabard icon: **Accord**. Its tooltip says *Azeroth Accord*.

- Clicking it shows the Accord panel over the content of the guild window. Clicking any of the game's tabs goes back to it; closing the window closes the panel.
- The tab shows only while your **guild** is the selected community, and not in the small (minimized) guild window.
- The panel has nothing protected in it: it opens and closes in combat too, and it never changes how the game's own tabs work.
- If a game update changes the guild window so much that the tab cannot be placed, the tab simply does not appear: use `/accord` for the standalone window, and `/accord debug` says why.

## The panel

- **Top bar**: the sync state, for example *3 guildmate(s) with Accord online · updated 2 min ago*, and **Pop out**, which moves the panel into its own, larger window. A search box appears once a view can search.
- **Navigation** on the left: **Roster**, **Professions**, **Reputation**, **Bank**, **Settings**, each one as soon as the version that brings it is out. The first test version (`v0.1.0`) has no view yet: the panel shows a welcome text, while the addon already exchanges its data with the guild in the background. The **Roster** view comes with the next version.

## The standalone window

`/accord`, the AddOn Compartment entry, a key binding or **Pop out** open the same panel in a window you can move (drag the title) and resize (the corner at the bottom right). It remembers its place and size for each character; Esc closes it. See [[Commands|Commands]].
