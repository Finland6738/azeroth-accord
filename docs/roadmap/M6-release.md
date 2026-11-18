# M6 — Release

**Goal:** `v1.0.0`: settings, Italian interface, polish, packaging and the full manual.

### M6.1 — Settings
- Branch: `step/m6-1-settings`
- Scope: Settings view and the game's Settings panel: Discord handle, main character, columns, notifications, data sizes and "clear guild data".

### M6.2 — Italian interface
- Branch: `step/m6-2-itit`
- Spec: ADR 0015
- Scope: complete `Locale/itIT.lua`; a test that checks every key in both locales.

### M6.3 — Polish and performance
- Branch: `step/m6-3-polish`
- Scope: empty states, loading states, error texts, large-guild profiling (S11 numbers), memory and SavedVariables sizes.

### M6.4 — Diagnostics and bug reports
- Branch: `step/m6-4-diagnostics`
- Scope: `/accord debug` report box without names, issue form fields aligned.

### M6.5 — Packaging and release workflow
- Branch: `step/m6-5-packaging`
- Scope: BigWigs packager, GitHub Releases, optional CurseForge, `docs/RELEASING.md`.

### M6.6 — Release checklist and v1.0.0
- Branch: `step/m6-6-release`
- Scope: `docs/checklists/release.md` in game, wiki complete, READMEs, tag `v1.0.0`.
