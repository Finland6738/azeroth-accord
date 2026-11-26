# Guild handbook

*Italiano: [[Manuale di gilda|Guild-Handbook-it]]*

> **Not in a release yet.** The handbook is in the code but switched off until milestone M11 is complete: there is no **Handbook** tab and no command. Reading (step M11.3) and writing (step M11.4) are done; the default pages (M11.5) and the loot page (M11.6) come next. Nothing has been checked in the real game. What follows describes how it should work.

The handbook is a set of text pages your guild keeps in the game: information, rules, FAQ, how raids, the roster and the loot work. Officers (and the ranks officers choose) write them; **every member with Accord reads them**. Your computer keeps the pages it has received, so you can read them with nobody else online, as they were at the last sync.

## Reading

Open it with the **Handbook** tab or `/accord handbook`. `/accord handbook rules` opens a page by its name (the one links use); without a name you get the last page you read.

- **On the left**, the pages in the order the guild gave them. Click one to read it.
- **On the right**, the page, with when it was last changed and by whom.
- **Links** in the text open another page, sometimes at one of its headings; **Back** returns to where you were. A grey link leads to a page that does not exist or is not published. A link to the season opens the [[Season|Season-Roster]] view.
- **Web addresses**: click one to get it in a box, then press Ctrl+C. The game cannot open a browser.
- **Search**: type at least 2 characters in the search box at the top right. Titles and lines of the pages are searched, ignoring capitals and accents; click a result to open the page at that line.

## Updated pages

A page that changed since you last read it is marked **Updated**, and the tab shows how many there are. The mark goes away when you keep the page open for 2 seconds, or with **Mark all as read**. The first time, every page is marked. Your own account's changes are not marked. With the [[Action Center|Action-Center]] you also get one line saying how many pages are updated.

What you have read stays on your computer, shared by your characters: nobody else is told.

## If you write pages

Writers are the Guild Master, the officers and the ranks the officers choose. Only they see the buttons below. They also see the pages that are still **templates** (members do not) and any page **Over the limit** of 20.

- **New page** (under the list) and **Edit** (under the page) open the editor. It does not open in combat.
- Choose the selected page's place in the list with the **arrows** next to it.
- **Delete** removes a page for the whole guild; a second click, **Confirm**, does it.
- **Writers** (officers only) chooses the ranks that write besides the officers. If the guild renames or moves a chosen rank, choose it again: the view says so.

### The editor

Write the title and the text. Plain text, line by line:

| You write | You get |
|---|---|
| `# Title` or `## Title` | a heading |
| `- text` (two spaces before it: second level) | a bulleted list |
| `1. text` | a numbered list |
| `[[rules]]` or `[[rules\|our rules]]` | a link to a page, with your own words |
| `[[raid#Bench]]` | a link to a heading of a page |
| `[[season]]` | a link to the season view |

Type the `|` as it is: it is saved as `¦`. Item links, icons and colours are removed when you save (an item keeps its name in brackets).

- Under the text you see **how long it is** against the limit: 4000 bytes a page and 32 000 for the whole handbook (an accented letter counts 2). The title holds 40 bytes, and there are at most 20 pages. **Save** is off while something is over a limit, and the editor says what; nothing you paste is cut off.
- **Preview** shows the page as members will read it; links to missing pages are grey.
- **Cancel** asks for a second click if you changed something.
- What you type is kept as a **draft** on your computer (one at a time). If the game closes, open the editor on the same page and choose **Restore draft**.
- If somebody saved the page while you were writing, you see their text and choose **Keep mine** (yours is written over it) or **Discard mine** (yours stays among the revisions, marked *lost*).

### Revisions

**Revisions** lists the versions **this computer has seen** (the current one and the last 5): older ones are never sent between players. Click one to read it; **Restore** writes it as a new revision, for everybody. A deleted page is under **Deleted pages** at the bottom of the list, where you can restore it the same way.

If two writers save the same revision at once, the later one stays. Only the writer whose text was replaced is told, by a notice and an [[Action Center|Action-Center]] line that opens that text: **Restore** it or **Dismiss** the line.
