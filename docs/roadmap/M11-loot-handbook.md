# M11 — Loot and guild handbook

**Goal:** the guild handbook: text pages that officers write and every member reads in game. Pages cover:
- extended guild info;
- extended rules;
- extended FAQ;
- raid management;
- roster management;
- loot management.

Loot is documented, not computed: the page describes the system the guild uses and names the loot addon, if one is used. Release: `v0.11.0`.

**Exit criterion:** in game, an officer edits the rules page, and a member who logs in later reads the new version marked as updated.

**Owner's decision (2026-11-19):** no loot engine in Accord. The loot page says which system the guild uses and, if there is one, the addon for it. Accord points to that addon, and reads its data only if it turns out to be possible. This answers SPEC-10 Q6.

### M11.1 — Specification
- Branch: `step/m11-1-spec`
- Scope: write a new SPEC-15 ("Manuale di gilda e loot"), in Italian. It covers:
  - the `handbook` data set: pages, revisions, size limits, who can write;
  - the reader and the editor;
  - the default pages;
  - the loot page and its addon field.
  It also checks which loot addons Forever guilds use and whether any exposes its data.
- Done when:
  - [ ] SPEC-15 is linked from the spec index; SPEC-10 Q6 is marked answered; `tools/check_docs.py` passes.

### M11.2 — Handbook data
- Branch: `step/m11-2-handbook-data`
- Spec: SPEC-15
- Scope:
  - each page has an id, title, body, order and revision, and keeps its last few revisions;
  - only ranks the guild chooses can write (officers by default);
  - pages are synced on `GUILD`, and long bodies are sent in parts.
- Done when:
  - [ ] A page from a non-writer is refused; two edits of the same revision keep the newer and flag the conflict to its author.

### M11.3 — Reader
- Branch: `step/m11-3-reader`
- Spec: SPEC-15; SPEC-04
- Scope: a Handbook view with:
  - the page list;
  - the reader, with headings, lists and links between pages;
  - search;
  - a mark on pages updated since the player last read them.
- Done when:
  - [ ] Every member can read every page offline from the last sync; the "updated" mark clears on reading.

### M11.4 — Editor
- Branch: `step/m11-4-editor`
- Spec: SPEC-15
- Scope: multi-line editing with a preview, the length shown against the limit, and a list of past revisions with "restore".
- Done when:
  - [ ] An edit that would exceed the limit cannot be saved; restore creates a new revision.

### M11.5 — Default pages
- Branch: `step/m11-5-default-pages`
- Spec: SPEC-15
- Scope: empty templates with headings for guild info, rules, FAQ, raid management, roster management (linked to the season roster of M10) and loot management. Officers fill them in game; the templates hold no guild-specific text.
- Done when:
  - [ ] A new guild gets the templates once; deleting one does not bring it back.

### M11.6 — Loot page and loot addon
- Branch: `step/m11-6-loot`
- Spec: SPEC-15
- Scope:
  - the loot page's text, written by officers, with a link to the season roster ("loot follows the declared spec");
  - a field naming the loot addon and where to get it;
  - whether each member's client has that addon loaded, shared in the `HELLO` summary;
  - reading the addon's data only if M11.1 found that it is possible.
- Done when:
  - [ ] Officers see who has the loot addon; without an addon named, nothing is checked.

### M11.7 — In-game check and release
- Branch: `step/m11-7-check`
- Scope: `docs/checklists/M11.md` and the README status. The owner releases `v0.11.0`.
- Done when:
  - [ ] The checklist exists.
  - [ ] The in-game checks pass and the owner tags `v0.11.0`.
