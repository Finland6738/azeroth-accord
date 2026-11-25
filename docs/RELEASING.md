# Releasing

> Adapted from Azeroth Guild Finder (docs/RELEASING.md), same owner, GPL-3.0 ([ADR 0018](adr/0018-reuse-azeroth-guild-finder-foundations.md)).

**No tag exists yet, and none is created by the development sessions.** Every tag waits for the owner's in-game checks. The workflow below has never run: its first run is the dry run in *Try it without publishing anything*.

How a version of Azeroth Accord is built and published. The workflow is [release.yml](../.github/workflows/release.yml); the decisions are in [ADR 0011](adr/0011-embedded-ace3-savedvariables-and-schema-versions.md). Only the repository owner tags and adds secrets.

## The versions

| Tag | When | The in-game check that comes first |
|---|---|---|
| `v0.1.0` | end of M1, for the owner's guild | [M1](checklists/M1.md) |
| `v0.2.0` | end of M2 | [M2](checklists/M2.md) |
| `v0.3.0` | end of M3 | [M3](checklists/M3.md) |
| `v0.4.0` | end of M4 | [M4](checklists/M4.md) |
| `v0.5.0` | end of M5 | [M5](checklists/M5.md) |
| `v0.6.0` | end of M6 | [the release check](checklists/release.md) |
| `v0.7.0` | end of M7 | [M7](checklists/M7.md) |
| `v0.8.0` | end of M8 (the owner releases it before the check is run, 2026-11-25) | [M8](checklists/M8.md) |
| `v0.9.0` … `v0.15.0` | end of M9 … M15 ([the plan](roadmap/README.md)) | the milestone's own checklist, written in its last step |
| `v0.<N>.<F>` | the F-th fix release of milestone N (`v0.6.1`, `v0.6.2`, …) | the checks the fix touches |
| `v1.0.0` | when every planned milestone, up to M15, is done | [the release check](checklists/release.md), run again over everything |

Every milestone is released as `v0.<milestone>.0`, and its fixes raise only the last number ([ADR 0020](adr/0020-one-version-per-milestone.md)). The checks are cumulative: the one of a later version repeats nothing of an earlier one, so run them in order, or all together on the build you mean to tag (one tag then covers them all and the earlier tags are simply skipped). A pre-release suffix (`-alpha`, `-beta`, `-rc`) makes the GitHub Release a pre-release.

## What a tag does

Pushing a tag `vMAJOR.MINOR.PATCH` (optionally `-alpha`, `-beta` or `-rc`, with `.N`: `v0.6.0`, `v0.6.1`, `v0.7.0-beta.1`) starts the workflow **Release**, which:

1. checks what the package will contain (`tools/check_package.py`);
2. builds the zip with the [BigWigs packager](https://github.com/BigWigsMods/packager): libraries from `.pkgmeta`, `## Version` filled in with the tag, `Tests/`, `docs/`, `tools/` and Markdown left out, `LICENSE` kept, development code switched off;
3. checks the zip itself (`tools/check_package.py --zip`) and keeps it as a workflow artifact for 14 days;
4. creates the **GitHub Release** with that zip (a pre-release when the tag has `-alpha`, `-beta` or `-rc`); its body is the section of `CHANGELOG.md` for the version (`tools/release_notes.py`: the section of the exact tag, else of the base version, else *Unreleased*);
5. uploads to **CurseForge**, only if both the `CF_API_KEY` secret and the project ID in the TOC are set (not for `-rc` tags). Otherwise it says "CurseForge skipped" and the run stays green.

Check the package locally at any time, with no network and no secrets:

```bash
python -I -X utf8 tools/check_package.py --list
```

## Try it without publishing anything

1. **Dry run**: Actions → *Release* → *Run workflow* on `main`, leave `draft_tag` empty. It builds and checks the zip; download it from the run's artifacts and look inside. Nothing is published.
2. **Draft release**: run it again with `draft_tag` = `v0.0.1-alpha.1`. It creates a **draft** GitHub Release with the zip; only you can see drafts. Open it, then delete the draft. No tag is pushed and CurseForge is not touched.
3. **Test tag** (this makes a real, public pre-release; delete the release and the tag afterwards):

   ```bash
   git tag -a v0.0.1-alpha.1 -m "Test tag for the release workflow"
   git push origin v0.0.1-alpha.1
   ```

   Afterwards: `gh release delete v0.0.1-alpha.1 --cleanup-tag --yes`.

## Setting up CurseForge (once)

CurseForge is **optional and off** ([SPEC-09 §4](specs/SPEC-09-quality-release.md#4-rilascio)): whether Azeroth Accord goes there at all, and under which project, is an open decision of the owner ([SPEC-10 Q9](specs/SPEC-10-risks-open-questions.md)). Nothing is set up for it: the TOC has the project line commented out and the repository has no `CF_API_KEY` secret, so a tag publishes on GitHub only and the workflow says *CurseForge skipped*. To switch it on once decided:

1. Create a project on [CurseForge](https://www.curseforge.com/wow/addons) for World of Warcraft addons: name *Azeroth Accord*, licence GPL-3.0, the unofficial notice and the privacy summary ([Privacy and Data](wiki/Privacy-and-Data.md)) on the description. Make sure the project's game versions include **WoW Forever**.
2. Copy the **Project ID** (a number, on the project's *About* panel) into the TOC: in `AzerothAccord/AzerothAccord.toc` replace the commented line `# ## X-Curse-Project-ID: 0` with `## X-Curse-Project-ID: 12345` (your number, two `#` signs, no space in front). Ship that in a normal pull request.
3. Create an API token at <https://www.curseforge.com/account/api-tokens>.
4. Add it in the GitHub repository: **Settings → Secrets and variables → Actions → New repository secret**, name `CF_API_KEY`, value the token. Do this yourself; never paste the token in an issue, a pull request or a chat.
5. Push a `-beta` tag (a pre-release) before the first real version, and look at the CurseForge file: its game version and release type (*Beta*).

Until steps 2 and 4 are both done, tags only publish on GitHub.

## Releasing a version

1. Everything merged on `main`, CI green, the in-game checklist of the version passed ([`docs/checklists/`](checklists/release.md)) and its results reported.
2. In a normal pull request: promote the changelog with `python -I -X utf8 tools/release_notes.py --promote 0.6.0` (*Unreleased* becomes `## [0.6.0] - <date>` and a new empty *Unreleased* goes on top), and update the status of the README, `README.it.md` and the wiki. Check what the release will say: `python -I -X utf8 tools/release_notes.py v0.6.0`.
3. Tag the merge commit and push the tag. **Check your git identity first**: an annotated tag records the tagger's name and email, and this repository's rule is the GitHub noreply address ([CLAUDE.md](../CLAUDE.md), Privacy). `git config user.email` must print an `@users.noreply.github.com` address; then:

   ```bash
   git tag -a v0.6.0 -m "Azeroth Accord 0.6.0"
   git push origin v0.6.0
   ```

4. Watch the run in the Actions tab, then open the GitHub Release (and CurseForge) and download the zip once: the folder must be `AzerothAccord/` with the TOC inside.
5. Wrong release? Delete the GitHub Release and the tag (`gh release delete vX --cleanup-tag --yes`), remove the file on CurseForge, fix, and tag again with a new patch number; do not reuse a tag that was public.
