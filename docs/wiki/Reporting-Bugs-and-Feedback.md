# Reporting bugs and feedback

Open an issue in the repository with the *Bug report* form, or share ideas and questions in the Feedback discussions. Test results from the real game have their own form, *In-game test report*.

## The report

Type `/accord debug` in game. A box opens with the report already selected: press **Ctrl+C**, close the box, and paste the text into the form. It shows how many lines and characters it has; it is cut at 30,000 characters (the end is what is cut; the important sections come first).

**It contains no player, guild, BattleTag or Discord names, no account token, no character ids, and no folders of your PC.** If an error message of the addon happens to name a guildmate, your guild or you, the name is replaced by `<player>` or `<guild>` before it goes in the report. Replace any other name you paste yourself with a placeholder such as `<player>`.

The report starts with the facts the *Bug report* form asks for, under the same names, so you can copy them across:

| Report line | Form field |
|---|---|
| `addon:` | Addon version |
| `client:` and `locale:` (plus `interface:` and `project id:`) | Game client |
| `role:` (member, officer or guild master) | Your role when it happened |
| `guild size:` | Guild size (optional; it matters for slowness and memory) |

After that it lists:

- whether the addon can send right now (or waits because of a chat lockdown or a restriction, for example during a boss);
- the last errors of the addon, with the folders of your computer removed;
- **Features**: which parts of the game the addon could use on your client (`available`), could not (`missing`), or has not been able to check yet (`unknown`, for example the guild bank before you open it);
- **APIs**: every game function the addon uses and whether it worked;
- **Saved data**: the size of the saved data (account, character and the current guild, per kind of data) and **Memory**: the memory the game says the addon uses;
- one section per part of the addon (sync, store, roster, likes, bank...) with counts and states only.

Paste the report whole: a report with the first lines cut off cannot be matched to a version. If the game also shows a Lua error box, paste its text too.

## Where to send what

- Something does not work: *Bug report* issue.
- It works but could be better, or you have a question: Feedback discussion.
- You ran a check of the in-game checklist: *In-game test report* issue, with the check id (for example `M3 step 4`) and, best, the report.
