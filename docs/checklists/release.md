# Release check: settings, Italian, performance, diagnostics, package (M6) and v0.6.0

The offline tests prove that the code agrees with our assumptions about the client; this checklist proves that the client agrees with the code, and that the package is what you mean to ship. It is the **exit check of milestone M6** and it is **not done yet**: nobody has run this version on WoW Forever, and **no tag exists**. When it passes, and the checks of M1 to M5 have passed, you tag `v0.6.0` ([docs/RELEASING.md](../RELEASING.md)); until then there is no release. The same check is run again over everything before `v1.0.0`, which comes after M15 ([ADR 0020](../adr/0020-one-version-per-milestone.md)).

**Exit criterion of M6:** in game, the settings work and survive a reload, the interface is complete in Italian, a large guild stays fast and small, `/accord debug` is safe to paste, and the zip the release workflow builds installs and loads.

Report the results with the *In-game test report* issue form (or in the table at the end) and tick the M6.1 to M6.3 "in game" boxes and M6.7 in [M6-release.md](../roadmap/M6-release.md).

## 0. Before anything: the checks that come first

The tag covers every milestone, so every earlier check has to be done on the build you tag (or on one that differs from it only by documentation):

| Check | File | Tag it unlocks |
|---|---|---|
| M1: loading, the Accord tab, taint, two clients | [M1.md](M1.md) | `v0.1.0` |
| M2: roster, alts, contacts, co-play | [M2.md](M2.md) | `v0.2.0` |
| M3: professions and recipes | [M3.md](M3.md) | `v0.3.0` |
| M4: likes, social index, group map | [M4.md](M4.md) | `v0.4.0` |
| M5: guild bank | [M5.md](M5.md) | `v0.5.0` |
| This one | `release.md` | `v0.6.0` |

You may run them all in one session on the same two or three clients. A check that fails stops the tag it unlocks, and the later ones too, since each builds on the earlier. **The M0 probe results (S1 to S11) are still not in**: the earlier checklists answer them; this one answers S11 (performance) at the end.

## What you need

- WoW Forever, a guild with **at least 50 members** (the more the better: S11 wants 500 or more, but the owner's guild decides), and **two or three clients with the addon** in it: **O**, an officer; **A**, a member; optionally **I**, a client whose game language is Italian (`itIT`; set it in the game's launcher, under the game's settings).
- The package to test: **the zip built by the release workflow**, not the files of the repository. How (nothing is published): Actions → *Release* → *Run workflow* on `main`, `draft_tag` empty; download the artifact `AzerothAccord-package` from the run (see [RELEASING](../RELEASING.md), "Try it without publishing anything"). Extract it into `<WoW folder>/_forever_/Interface/AddOns/` so the folder is `AzerothAccord/` with the TOC inside. Do this on every client.
- A text editor for the notes, and a screenshot tool.

## What is not known yet (this is what the check is for)

| # | Question | Where to see it | What the addon does if the answer is "no" |
|---|---|---|---|
| 1 | Does the game's own settings window (*Options → AddOns*) get an **Azeroth Accord** page (`Settings.RegisterCanvasLayoutCategory`)? Does the page fit and scroll in it? | step 2 | no page there; `/accord settings` still works; `/accord debug` → *Settings*: "game panel: unavailable" |
| 2 | Does `GUILD_CHANGED` with the same key (what **Clear guild data** emits) make every part start again and the guild resend its data? | step 2.7 | the data is empty until the next login or the next change of guild |
| 3 | Does `GetAddOnMemoryUsage` give a figure for the addon? How many MB in a big guild? | step 4: `/accord debug` → *Memory* | the report says "Memory: unknown" |
| 4 | What does a big guild cost: login, opening the Roster (sort, group), the first *who can craft* search, the social index, the saved file? **(S11)** | step 4 | the budgets of [SPEC-09 §5](../specs/SPEC-09-quality-release.md) are offline numbers; yours replace them |
| 5 | Is the Italian text right in the game's frames: no overflow, no cut button, no English left? Do the game's own Italian words (ranks, professions, the vault) match ours? | step 3 | a text fix, never a code change |
| 6 | Does the zip the workflow builds load: `## Version` filled in, `Config.DEV` false, the libraries embedded, no `Tests/` or `docs/`? | step 1 | the workflow's own checks stop it; tell us what is wrong |
| 7 | Do the **design previews** look like the real window? (they are drawings, [ADR 0019](../adr/0019-design-previews-original-art-invented-data.md)) | step 6 | the previews are replaced by screenshots view by view |

## 1. The package (M6.5)

1. Extract the zip as above. The folder is `AzerothAccord/`, with `AzerothAccord.toc`, `LICENSE`, `Core/`, `Data/`, `Net/`, `UI/`, `Locale/`, `Libs/`. No `Tests/`, `docs/`, `tools/`, `.github`, `*.md`.
2. Start the game (or `/reload`). **No Lua error**, no chat message at login. The AddOns list shows *Azeroth Accord* with the version **of the zip** (not `@project-version@`).
3. `/accord debug`: the first lines say `addon: <the version>`, `client: 1.60.1 …`, `locale:`, `role:`, `guild size:`. Check that the addon version is a real version and that the **Saved data** section says `no problems`.
4. It must be a release build, not a development one: `/run print(AzerothAccord.Config.DEV)` prints `false` in the package (and `true` in a checkout of the repository).
5. Repeat on a second client with a **clean** `WTF` folder (no saved data): the addon starts without errors and creates its data.

## 2. Settings (M6.1)

1. `/accord settings` opens the **Settings** view in the panel; the page scrolls with the mouse wheel to the end (saved data and *Clear guild data*) and back.
2. **The game's own settings**: *Options → AddOns → Azeroth Accord*. Does the page exist? Does it show the **same** page, fit the window and scroll? A change in one place shows in the other at once. (Question 1.) *Defaults* in that window does nothing harmful.
3. **Contacts**: type a Discord name, *Save*: "Saved and shared with your guild."; an invalid one (`http://x`) is refused with the message; it appears on the member card on **O** within a minute.
4. **Main character**: with two characters of the account on the realm, *Choose main…* lists them; pick the lower-level one: the line says it, **the grouped Roster** and the card on the other client show it as the main. Pick the other back.
5. **Notifications**: as an officer you see both switches, as a member only the second. Switch *Tell me in chat about new bank requests* off on **O**, make a request on **A**: **O** gets no chat line but still sees the counter on the tab. Switch it on: the next request gives one line. Same for *when my bank requests are decided* (approve one of A's).
6. **Roster columns**: untick two columns, `/reload`: they are still gone (the choice is per character); *Default columns* brings them back.
7. **Saved data**: the sizes make sense (account, this character, this guild, one line per kind of data with its records) and contain no names. Click **Clear guild data** once: the button says how much will go; wait 10 seconds: it goes back to its label. Click twice quickly: the data is cleared, the Roster and the other views are empty for a moment and **fill in again within a few minutes** as guildmates with the addon are online (question 2). **Your likes** (the member card still says you gave your like to that player) and your Discord name are still there. As an officer: the likes still work (the guild's likes key was kept).
8. `/reload`: every setting is as you left it.

## 3. Italian (M6.2)

1. On client **I** (Italian game language) start the game: `/accord help` answers "Comandi:". Open **every** view (Roster, Professioni, Reputazione, Banca, Impostazioni), the member card, the recipe list, *Chi può creare*, every Bank mode, the diagnostics box and the Settings page in the game's settings window.
2. Look for: any English left (apart from the names the game gives and what players type), text that **overflows** its frame or is cut, a button too narrow for its label, a line that runs into another. Take a screenshot of each problem.
3. Compare our words with the game's own Italian for the same thing (ranks, professions, *Banca di gilda*, *sussurro*, *gruppo*). Where they differ, write both: we follow the game.
4. The `/accord debug` report stays in English on purpose.

## 4. Performance, memory and size (M6.3, S11)

1. With the biggest guild you have, log in with the addon. Does the **login** stutter more than usual? How long until the Accord tab works?
2. Open **Roster**: how long until the rows show? Sort by two columns, turn on *By account*, search for a name: any delay or hitch? Open **Professions → who can craft**, type a common word: the first search may take a moment (the index is built once), the second must be instant.
3. Open **Reputation → Social** (as an officer, **Groups**): how long does the first open take?
4. `/accord debug`: write down **guild size**, the **Memory** line (MB), the **Saved data** sizes (account, this guild, and each kind of data: *coplay* is the big one). Do the same again **a week later** if you can.
5. Did the game's frame rate drop while the panel was open, or while the addon synced after login? (Open the game's own addon CPU view or the `Ctrl+R` frame-rate display if you use one.)
6. These numbers answer **S11**: put them in the report; they replace the offline table of [SPEC-09 §5](../specs/SPEC-09-quality-release.md).

## 5. Errors, empty states and diagnostics (M6.3, M6.4)

1. A fresh character in a guild: every view says what to do when it has nothing to show (no blank frame). Open the **Bank** view before anyone with the addon has opened the vault: it explains.
2. **A view that fails.** In the chat: `/run AzerothAccord.Shell:RegisterView("broken", { label = "Broken", order = 95, build = function() error("test error in AzerothAccord") end })`, then open the panel (`/accord`) and select **Broken** in the navigation: the view says **"This view could not be drawn"** and the other views still work. The game shows the Lua error once. `/accord debug` → *Last errors* lists it. `/reload` removes it.
3. **The report holds no name.** Read the whole `/accord debug` report on a client in a real guild: **no** player, guild, realm, BattleTag, Discord name, folder of your PC or account token anywhere. (If you find one, that is a bug: send the line with the name blurred.) In *Last errors*, the test error above shows without any name.
4. The box: it opens **selected**, shows "N lines, M characters", **Ctrl+C** copies, typing is undone, **Esc** closes. Paste the report into a new *Bug report* form (do not submit): its first lines match the form's fields (addon, client, language, role, guild size).

## 6. The pictures (M6.6)

1. Open the Accord tab and each view, side by side with its **design preview** (`docs/specs/mockups/previews/`, or the wiki). Write down the differences that matter (a missing control, another order, a colour, a wrong text). The previews are drawings: spacing and fonts will differ.
2. Take **screenshots** of the views you want in the manual (blur the names; or use a guild of test characters): they replace the previews view by view ([ADR 0019](../adr/0019-design-previews-original-art-invented-data.md), rule 6).

## 7. The release workflow (M6.5): dry run, draft, test tag

Only when steps 1 to 6 pass, and **only you** can do these ([RELEASING](../RELEASING.md)):

1. **Dry run** (already used above): the zip is built and checked, nothing is published.
2. **Draft release**: *Run workflow* with `draft_tag` = `v0.0.1-alpha.1`. A *draft* GitHub Release appears with the zip and the **notes taken from the changelog**; read them, then delete the draft.
3. **Test tag** (public pre-release; delete it afterwards): `git tag -a v0.0.1-alpha.1 -m "Test tag"`, `git push origin v0.0.1-alpha.1`; check the release, the zip, that CurseForge was skipped ("CurseForge skipped" in the run) and then `gh release delete v0.0.1-alpha.1 --cleanup-tag --yes`. **Check `git config user.email` is the noreply address before tagging.**

## 8. The decisions that wait for you (SPEC-10)

Decide, or say "as implemented", before `v0.6.0`; nothing here blocks the checks:

| # | Question | Implemented as |
|---|---|---|
| Q1 | Technical names (`AzerothAccord`, `AzAccord`, `/accord`, `/acc`) | as proposed |
| Q2 | The tab icon: the game's icon or an original drawing | the game's guild tabard icon |
| Q3 | Who sees the others' social index and the group map | officers and the Guild Master; everyone their own |
| Q4 | Bank tabs a rank cannot see in the game | hidden in the addon too |
| Q5 | Who sees the donations ranking | everyone |
| Q7 | The `main:` / `alt:` note convention | `main: <name>` = "my main is <name>" |
| Q8 | Main recipe source | the game's directory when it answers, the shared lists otherwise |
| Q9 | Where to distribute (GitHub only, or also CurseForge and others) | GitHub Releases only; CurseForge ready but off |

## 9. Releasing (after the results are in)

1. Every box above is ticked, the results are reported, the M1 to M5 checks have passed.
2. Follow [RELEASING.md](../RELEASING.md), "Releasing a version": promote the changelog (`python -I -X utf8 tools/release_notes.py --promote 0.6.0`), update the status of the READMEs and the wiki, merge, then tag `v0.6.0` **from the merge commit** with the noreply identity and push the tag.
3. Watch the run, download the release zip once, install it and run steps 1 and 2 of this check on it.
4. Tick the M6.7 box in [M6-release.md](../roadmap/M6-release.md) and announce.

## What to report if something does not work

| Symptom | What to send |
|---|---|
| Lua error | the error text (error frame or BugSack) and what you did |
| No *Azeroth Accord* page in the game's settings | `/accord debug` → *Settings* line, and the Lua error if any |
| Clear guild data does not refill | `/accord debug` → *Store* and *Sync* lines before and after, who was online |
| An English text in the Italian client, or a cut one | a screenshot and the view |
| Slow or heavy | the guild size, the *Memory* and *Saved data* lines and the step where it was slow |
| A name in the report | the line with the name blurred, and the section it was in |
| The zip does not load | the workflow run link and `/accord debug` |
| A preview differs from the real window | a screenshot next to the preview's name |

## Result

| Date | Client build | Debug report | Package loads | Settings (game panel, clear data) | Italian | S11 numbers | Memory / saved file | Failed view and report | Previews vs real | Workflow dry run | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | | | |
