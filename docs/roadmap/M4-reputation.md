# M4 — Reputation: likes and the social index

**Goal:** likes from account to account, irreversible and anonymous; the social index, the group map and suggested teammates.

**Exit criterion:** in game, two members like a third through an online officer and every client shows the same total; the social index shows for members with enough data.

### M4.1 — Guild salt and the notary
- Branch: `step/m4-1-salt-notary`
- Spec: LIKE-06, LIKE-07; ADR 0007
- Scope: salt creation and sharing on `OFFICER` (whisper fallback if S5 says so), choice of the notary among online officers.
- Done when:
  - [x] Officers create, share and converge on one salt (also when two create it at once, and by whisper when `OFFICER` carries no addon messages); members never hold it and no `SALT` goes on `GUILD`; the notary is chosen among online officers (covered by `Tests/test_notary.lua`, with the network simulator; HMAC-SHA256 checked against RFC 4231 in `Tests/test_hash.lua`).

### M4.2 — Votes and the ledger
- Branch: `step/m4-2-likes-ledger`
- Spec: LIKE-01–LIKE-05, LIKE-09
- Scope: `Data/Likes.lua`: vote queue, notary checks, pseudonyms, append-only ledger, authority rule, totals per account.
- Done when:
  - [x] Tests: double vote, self and alt votes, forged ledger, queued votes, merge after alt linking (`Tests/test_likes.lua`, with the network simulator: votes wait for an officer, two clients like a third and every client shows the same total; also a new token, another salt, a copied token, the append-only store).

### M4.3 — Like button, column and Reputation view
- Branch: `step/m4-3-likes-ui`
- Spec: LIKE-04, LIKE-08
- Scope: Like on the member card, likes column, pending state, the Reputation view.
- Done when:
  - [x] The card has the account's total and a Like action confirmed by a second click, then the pending or given state; the Likes column is a default column (green when liked, grey while pending); the Reputation view lists every account by likes with places, sort, search, a two-click Like and a click to the card, and never shows who voted (covered by `Tests/test_reputation_view.lua`).

### M4.4 — Social index computation
- Branch: `step/m4-4-social-index`
- Spec: SPEC-07 §3.2; ADR 0008
- Scope: `Data/Social.lua`: accounts, 30-day window, entropy, index, chunked computation.
- Done when:
  - [x] The examples of SPEC-07 §3.2 are numeric tests (`Tests/test_social.lua`: N = 4 → 10, N ≈ 8.94 → 22, N = 30 → 75 with A = 41; also the maximum over observers, alts merged, the 30-day window, "not enough data", the computation in steps at most every ten minutes, 200 accounts in about 10 ms offline).

### M4.5 — Social column and card breakdown
- Branch: `step/m4-5-social-ui`
- Spec: SOC-04, SOC-05
- Scope: index column, card with effective partners, distinct partners and top 5 shares, explanation tooltip.
- Done when:
  - [x] The card shows the index (with its explanation tooltip), effective and distinct partners, the time and the top 5 shares, or "not enough data"; the Social column and the Social mode of the Reputation view exist; members see only their own index and officers everyone's (SPEC-10 Q3 proposal, still open) (covered by `Tests/test_social_ui.lua`).

### M4.6 — Group map
- Branch: `step/m4-6-group-map`
- Spec: SOC-10–SOC-12
- Scope: weighted label propagation, modularity, communities list and circle drawing, visibility per Q3.
- Done when:
  - [x] Weighted label propagation and modularity are exact on known graphs and deterministic; the Groups mode shows the mixing, the circles of players and the list of communities to officers and the Guild Master only (SPEC-10 Q3 proposal, still open) (covered by `Tests/test_group_map.lua`).

### M4.7 — Suggested teammates and v0.4.0
- Branch: `step/m4-7-suggestions`
- Spec: SOC-20
- Scope: "Play with someone new" box; `docs/checklists/M4.md`; wiki "Likes and Social Index"; tag `v0.4.0`.
