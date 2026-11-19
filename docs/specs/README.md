# Azeroth Accord: specifiche di progetto

Addon **non ufficiale** per **WoW: Forever** che aggiunge alla finestra della Gilda una scheda **Accord** con gli strumenti che mancano alla gilda: roster esteso con professioni e ricette, alt dello stesso account, contatti Battle.net e Discord, like, indice sociale contro i gruppetti e banca di gilda con richieste e donazioni.

- Stato: **Bozza 1, da revisionare** (2026-11-18)
- Client di riferimento: WoW Forever `1.60.1`, `## Interface: 16001`, `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT`
- Distribuzione: GitHub Releases (CurseForge facoltativo), installazione manuale
- Lingua dell'addon: inglese e italiano dalla `v1.0.0` ([ADR 0015](../adr/0015-interface-and-documentation-languages.md))
- Lingua di questi documenti: italiano; nomi di codice, API e testi dell'interfaccia in inglese

## Indice

| # | Documento | Contenuto |
|---|---|---|
| 00 | [Visione, ambito e ruoli](SPEC-00-vision-scope.md) | obiettivi, funzioni per versione, ruoli, registro delle decisioni |
| 01 | [Piattaforma e architettura](SPEC-01-platform-architecture.md) | vincoli del client, moduli, librerie, SavedVariables, Compat |
| 02 | [Protocollo di rete](SPEC-02-network-protocol.md) | canali di gilda, messaggi, sincronizzazione, coda, fiducia |
| 03 | [Modello dati](SPEC-03-data-model.md) | account, personaggi, contatti, professioni, like, co-play, banca, richieste |
| 04 | [Scheda Accord e struttura dell'interfaccia](SPEC-04-ui-guild-tab-shell.md) | tab nella finestra Gilda, pannello, finestra autonoma, navigazione |
| 05 | [Roster esteso, alt e contatti](SPEC-05-roster-alts-contacts.md) | tabella dei membri, personaggi dello stesso account, scheda membro, Battle.net e Discord |
| 06 | [Professioni e ricette](SPEC-06-professions-recipes.md) | colonne professione, elenco ricette, "chi sa fare", richieste di crafting |
| 07 | [Reputazione e indice sociale](SPEC-07-reputation-social.md) | like, indice sociale, mappa dei gruppi, compagni suggeriti |
| 08 | [Banca di gilda](SPEC-08-guild-bank.md) | foto della banca, registri, donazioni, richieste di prelievo e deposito |
| 09 | [Qualità, spike e rilascio](SPEC-09-quality-release.md) | verifiche nel client (S1–S11), test offline, tappe di rilascio |
| 10 | [Rischi e domande aperte](SPEC-10-risks-open-questions.md) | rischi tecnici e punti ancora da decidere |
| — | [Mockup e anteprime dell'interfaccia](mockups/README.md) | immagini di progetto di ogni vista principale (in inglese), generate da `tools/make_mockups.py` |

## Convenzioni

- **MUST / SHOULD / MAY**: obbligatorio / raccomandato / facoltativo.
- Le API marcate **[verificare]** non compaiono nel dump oppure il loro comportamento sui server di Forever non è ancora stato osservato: vanno confermate nello spike ([SPEC-09](SPEC-09-quality-release.md#1-spike-tecnico-m0)).
- Ogni requisito ha un identificativo (`GT-xx`, `NET-xx`, `ROS-xx`, `PRO-xx`, `LIKE-xx`, `SOC-xx`, `BANK-xx`…) da citare nelle issue e nelle PR.
- Le decisioni definitive si registrano come ADR in [`docs/adr/`](../adr/README.md).
