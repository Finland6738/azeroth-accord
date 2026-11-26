# Azeroth Accord: specifiche di progetto

Addon **non ufficiale** per **WoW: Forever** che aggiunge alla finestra della Gilda una scheda **Accord** con gli strumenti che mancano alla gilda: roster esteso con professioni e ricette, alt dello stesso account, contatti Battle.net e Discord, like, indice sociale contro i gruppetti e banca di gilda con richieste e donazioni.

- Stato: **Bozza 1, da revisionare** (2026-11-18)
- Client di riferimento: WoW Forever `1.60.1`, `## Interface: 16001`, `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT`
- Distribuzione: GitHub Releases (CurseForge facoltativo), installazione manuale
- Lingua dell'addon: inglese e italiano dalla `v0.6.0` ([ADR 0015](../adr/0015-interface-and-documentation-languages.md))
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
| 11 | [Fiducia nei dati](SPEC-11-data-trust.md) | M7: etichette di provenienza, gilda degli alt fuori gilda, modalità demo, backup personale, pannello "cosa condivido", limiti contro i client malevoli e le gilde grandi |
| 12 | [Strumenti per ufficiali](SPEC-12-officer-tools.md) | M8: cronologia osservata del roster, inattività per account con fasce e assenze dichiarate, revisione guidata e coda di azioni manuali (nessuna azione automatica), note estese, esportazioni CSV e per Discord, chi vede cosa e dati degli ufficiali solo su `OFFICER` |
| 13 | [Centro azioni e avvisi](SPEC-13-action-center-notices.md) | M9: Centro azioni con i fornitori dei moduli, livelli degli avvisi, cronologia, ore di quiete, riepilogo all'accesso; cercagruppi solo per la gilda (annunci di breve vita, candidature al capo, inviti, il Group Finder del gioco solo in privato e dal clic del capo); censimento degli addon caricati |
| 14 | [Calendario, raid e roster della season](SPEC-14-calendar-raids-season.md) | M10: roster della season (MS1, MS2, OS, bloccato per la season), fonte scelta dagli ufficiali (Accord o FDCP), eventi e iscrizioni sul calendario del gioco, importazione degli eventi di Raid-Helper, panchina e composizione, mappa della disponibilità (solo presenza online, nessuna presenza ai raid), raduni PvP e nel mondo |
| 15 | [Manuale di gilda e loot](SPEC-15-guild-handbook-loot.md) | M11: insieme `handbook` (pagine con revisione, scrittori per grado scelti dalla gilda, testi lunghi su `GUILD` una volta per tutti, revisioni passate solo locali, conflitti segnalati all'autore), lettore e editor, pagine predefinite date una volta, pagina del loot (sistema e addon scelti dagli ufficiali, chi lo ha caricato, indirizzo di download, suggerimento di FDCP, riassunto delle regole di FDCP accanto); nessun motore del loot |
| — | [Stile dell'interfaccia](ui-style.md) | la famiglia di FDCP: differenze di Accord, impostazioni dell'aspetto, schede, tre temi (Nebula, Aurora, Accord) con contrasto |
| — | [Mockup e anteprime dell'interfaccia](mockups/README.md) | immagini di progetto di ogni vista principale nel nuovo aspetto (in inglese), generate da `tools/make_mockups.py`, e il [confronto con FDCP](mockups/compare/README.md) |

## Convenzioni

- **MUST / SHOULD / MAY**: obbligatorio / raccomandato / facoltativo.
- Le API marcate **[verificare]** non compaiono nel dump oppure il loro comportamento sui server di Forever non è ancora stato osservato: vanno confermate nello spike ([SPEC-09](SPEC-09-quality-release.md#1-spike-tecnico-m0)).
- Ogni requisito ha un identificativo (`GT-xx`, `NET-xx`, `ROS-xx`, `PRO-xx`, `LIKE-xx`, `SOC-xx`, `BANK-xx`…) da citare nelle issue e nelle PR.
- Le decisioni definitive si registrano come ADR in [`docs/adr/`](../adr/README.md).
