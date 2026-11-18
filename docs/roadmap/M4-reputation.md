# M4 — Reputation: likes and the social index

**Goal:** likes from account to account, irreversible and anonymous; the social index, the group map and suggested teammates.

**Exit criterion:** in game, two members like a third through an online officer and every client shows the same total; the social index shows for members with enough data.

### M4.1 — Guild salt and the notary
- Branch: `step/m4-1-salt-notary`
- Spec: LIKE-06, LIKE-07; ADR 0007
- Scope: salt creation and sharing on `OFFICER` (whisper fallback if S5 says so), choice of the notary among online officers.

### M4.2 — Votes and the ledger
- Branch: `step/m4-2-likes-ledger`
- Spec: LIKE-01–LIKE-05, LIKE-09
- Scope: `Data/Likes.lua`: vote queue, notary checks, pseudonyms, append-only ledger, authority rule, totals per account.
- Done when:
  - [ ] Tests: double vote, self and alt votes, forged ledger, queued votes, merge after alt linking.

### M4.3 — Like button, column and Reputation view
- Branch: `step/m4-3-likes-ui`
- Spec: LIKE-04, LIKE-08
- Scope: Like on the member card, likes column, pending state, the Reputation view.

### M4.4 — Social index computation
- Branch: `step/m4-4-social-index`
- Spec: SPEC-07 §3.2; ADR 0008
- Scope: `Data/Social.lua`: accounts, 30-day window, entropy, index, chunked computation.
- Done when:
  - [ ] The examples of SPEC-07 §3.2 are numeric tests.

### M4.5 — Social column and card breakdown
- Branch: `step/m4-5-social-ui`
- Spec: SOC-04, SOC-05
- Scope: index column, card with effective partners, distinct partners and top 5 shares, explanation tooltip.

### M4.6 — Group map
- Branch: `step/m4-6-group-map`
- Spec: SOC-10–SOC-12
- Scope: weighted label propagation, modularity, communities list and circle drawing, visibility per Q3.

### M4.7 — Suggested teammates and v0.4.0
- Branch: `step/m4-7-suggestions`
- Spec: SOC-20
- Scope: "Play with someone new" box; `docs/checklists/M4.md`; wiki "Likes and Social Index"; tag `v0.4.0`.
