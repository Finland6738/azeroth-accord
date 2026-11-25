# 0012. Git flow and automated shipping of milestone steps

- Status: Accepted
- Date: 2026-11-18 (same rules as Azeroth Guild Finder, ADR 0013 there)

## Context

The project is developed in milestone steps, often by automated sessions while the owner is away. The owner asked that every finished step is committed, pushed, opened as a pull request and merged **automatically**, and that the wiki follows every change.

## Decision

1. `main` is always working; nobody commits to it directly (the only exception was the initial bootstrap commit of the empty repository).
2. One branch per step from an up-to-date `main`: `step/m<N>-<name>` for roadmap steps, `fix/…`, `docs/…`, `chore/…` for the rest.
3. Small commits; messages, pull requests and issues in English.
4. **Authorized automation**: when a step is finished, `python -I -X utf8 tools/ship_step.py --title … --body-file …` runs the local checks, merges `origin/main` if needed, pushes, opens the pull request, squashes the step into **one commit authored and committed by the noreply address**, pushes, opens the pull request, waits for the required CI checks on that exact commit and, only if they are green, **fast-forwards `main` to it** and deletes the branch (GitHub then shows the pull request as merged). On any failure it stops and the pull request stays open with the reason.
5. Every pull request says honestly what was **not** verified, especially anything that needs the real client.
6. Never `--force` on `main`, never rewrite published history, never skip hooks.
7. GitHub's own squash merge is not used: it authors the commit with the account's primary (personal) email and refuses the noreply address as `--author-email` ("Invalid email address", seen on the first pull request on 2026-11-18). The fast-forward keeps the history noreply only and puts on `main` exactly the commit CI checked.
8. Choices that belong to the owner (licence, names, scope) are not made autonomously: an issue is opened with the options.
9. **Tests deferred (owner, 2026-11-25).** Until every milestone step is done, steps ship with `--skip-tests`. The script then runs only `tools/check_docs.py` locally, which keeps the privacy and wiki rules. It does not run `Tests/run_tests.py` and it does not wait for CI. `main` is fast-forwarded right after the pull request opens. CI still runs on the pull request and on `main`, for information only. Sessions still write tests and run the files they touch. The full suite, the long tests and CI must be green again before `v1.0.0`.

## Consequences

- Positive: one readable commit per step on `main`, no manual merge work, CI as the gate.
- Negative: no human review before merge; the checks must be good enough to be trusted.
- Negative, while point 9 holds: `main` may carry failing tests until the final pass before `v1.0.0`, and the milestone releases go out without a green CI.
