# Instructions for development sessions

The owner speaks Italian: talk to them in Italian. Code, commits, pull requests, issues, README and ADRs are in English; the wiki is bilingual (every `docs/wiki/<Page>.md` has an Italian twin `<Page>-it.md`, same images, and `tools/check_docs.py` checks it); the specification in `docs/specs/` is in Italian ([ADR 0015](docs/adr/0015-interface-and-documentation-languages.md)).

## Where things are

- Specification: `docs/specs/` (SPEC-00…SPEC-10). Decisions: `docs/adr/` (index in `docs/adr/README.md`). User manual: `docs/wiki/`. Plan: `ROADMAP.md` and the milestone files in `docs/roadmap/` (take the next unticked step, tick it in the same PR).
- WoW Forever API dump: `../WoW-Addons/docs/api.json` (consult only, never copy, [ADR 0002](docs/adr/0002-wow-forever-target-and-api-dump.md)).
- Sibling project to copy foundations from: `../azeroth-guild-finder` (same owner, GPL-3.0, [ADR 0018](docs/adr/0018-reuse-azeroth-guild-finder-foundations.md)).

## Git automation (authorized by the owner, ADR 0012)

For every milestone step or fix:

1. Branch from an up-to-date `main`: `step/m<N>-<k>-<name>` (or `fix/…`, `docs/…`, `chore/…`). Never commit to `main`.
2. Do the work. In the same branch update `CHANGELOG.md`, the affected specs/ADRs (and the ADR index), `README.md` + `README.it.md` when features or status change, and `docs/wiki/` for anything user-visible.
3. Run `python -I -X utf8 tools/check_docs.py` (plus the addon tests once they exist).
4. Write the pull request body (what and why, what was **not** verified in the real client) and ship **without asking**:
   `python -I -X utf8 tools/ship_step.py --title "M<N>: <summary>" --body-file <file> --commit "<message>"`
   It squashes the step into one noreply commit, pushes, opens the PR, waits for CI and fast-forwards `main` to the checked commit. If it stops, leave the PR open and report why.
5. The wiki is published by the `Wiki sync` workflow after the merge: never edit the wiki on GitHub.

Do not decide alone what belongs to the owner (licence, names, scope, deleting their data): ask, or open an issue with the options. Open questions are listed in `docs/specs/SPEC-10-risks-open-questions.md`.

## Privacy

No personal data in the repository: no real names, emails (only GitHub noreply addresses), or personal paths (use `<WoW folder>` and similar). `tools/check_docs.py` fails on them. This includes git authorship: this repository's git identity is the noreply address, and `ship_step.py` authors and commits every step with it; never merge from the GitHub web UI or with `gh pr merge` (GitHub would author the commit with the personal email). `prompt.txt` holds the owner's notes and is git-ignored.
