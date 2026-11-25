# Commands

*Italiano: [[Comandi|Commands-it]]*

Type them in the chat box. `/acc` works everywhere `/accord` does.

| Command | What it does |
|---|---|
| `/accord` | Opens or closes the Accord window (you must be in a guild) |
| `/accord roster` | Opens the Roster view |
| `/accord professions` | Opens the Professions view on **who can craft** (see [[Professions and Recipes|Professions-and-Recipes]]) |
| `/accord reputation` | Opens the Reputation view: likes of every player and the Like button, your social index, the group map (officers), *Someone new* to play with *(M4)* |
| `/accord bank` | Opens the Bank view *(M5)* |
| `/accord settings` | Opens the Settings view: Discord name, main character, notices, Roster columns, saved data (see [[Settings|Settings]]) |
| `/accord away 2026-12-31` | Declares that you are away until that day (only officers see it); `/accord away off` clears it, `/accord away` shows it (see [[Guild Roster|Guild-Roster]]) *(M8.3)* |
| `/accord about` | Opens the Info page of Settings: credits, links to copy, licence. `/accord about chat` prints the credits in the chat instead (see [[About and credits|About]]) |
| `/accord backup` | Opens the **Backup** card of the Settings page: export your own data to a text, or import it on another computer (see *Backup and restore* in [[Settings]]) |
| `/accord demo` | Fills every view with an **invented guild**, to try the addon without a guild or to show it. Nothing is sent and nothing is saved; type it again to leave (see [Demo mode](#demo-mode)) |
| `/accord debug` | Opens a diagnostic report, already selected: press Ctrl+C and paste it into a bug report. It contains no player, guild, BattleTag or Discord names |
| `/accord help` | Lists the commands in the chat |

A view that is not in your version yet answers "This part is coming soon".

Other ways to open the window:

- the **AddOn Compartment** (the addon list button next to the minimap): click *Azeroth Accord* (it carries the addon's logo, as does the window);
- a **key binding**: *Options → Keybindings → AddOns → Azeroth Accord*, "Open or close Azeroth Accord";
- the **Accord tab** of the guild window, then **Pop out** for the larger window; **Pop in**, in the title bar of that window, puts the panel back into the guild window while it is open.

`/accord <view>` opens the window on that view's tab (or switches the tab, if the panel is already open in the guild window). Esc closes the window.

## Demo mode

`/accord demo` turns the addon into a guided tour: every view (Roster, member card, Professions and recipes, Reputation with likes and the group map, Bank with its logs and requests, Settings) is filled from an **invented guild**, "Demo Guild", of 60 members with invented names, 20 players with the addon, three professions, a bank and its requests. It works without a guild and without a connection, so it is also the way to look at the addon before you join one.

- A strip at the top of the panel says **Demo: invented guild. Nothing is sent or saved.** and has an *Exit demo* button; the title bar and the line under the panel say *Demo* instead of the number of guildmates.
- **Nothing is sent**: not a message to the guild, not a whisper, not an invitation. What the guild sends you meanwhile is ignored (the sync repairs it a few seconds after you leave). A message that was already waiting to go out waits, and leaves after the demo.
- **Nothing is saved**: you play on a copy of your data, so a like, a bank request, a main or a theme you choose in the demo disappear when it ends. Your real data, your real guild and your real settings come back exactly as they were. A `/reload` or leaving the game also ends the demo: it never stays on.
- You are an officer of the invented guild, so the officers' views are there too (the bank's officers-only tab, the request decisions, the group map).
- The professions and recipe names come from the game itself; if the game does not know a spell, the view shows its number.

Type `/accord demo` again (or `/accord demo off`, or press *Exit demo*) to leave.
