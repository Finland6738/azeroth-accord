# SPEC-09: Qualità, spike e rilascio

## 1. Spike tecnico (M0)

Un addon di prova, `AzAc_Probe`, **mai distribuito**, risponde nel client vero alle domande che il progetto non può risolvere offline. Ogni chiamata è in `pcall`; nessun nome di giocatore o gilda viene stampato o salvato (solo segnaposti, conteggi e tipi).

| Check | Domanda | Decide |
|---|---|---|
| S1 | Si può aggiungere una tab alla `CommunitiesFrame` sotto le 4 esistenti, mostrare un pannello e tornare alle tab di Blizzard senza taint (anche dopo azioni protette come promuovere o invitare, in combattimento, con `/reload`, con la finestra ridotta)? | [ADR 0003](../adr/0003-accord-tab-in-the-guild-window.md), SPEC-04 |
| S2 | `C_Club.GetMemberInfo` per i membri della gilda: sono pieni `profession1/2Name/Rank`, `discordInfo`, `bnetAccountId`, `guid`? Anche per membri offline? | SPEC-05, SPEC-06 |
| S3 | La rubrica nativa delle ricette di gilda funziona (`IsGuildTradeSkillsEnabled`, `QueryGuildMemberRecipes`, `GUILD_RECIPE_KNOWN_BY_MEMBERS`, `GetGuildMemberRecipes`, `GetGuildTradeSkillInfo`)? | [ADR 0010](../adr/0010-native-data-first-shared-data-as-fallback.md), SPEC-06 |
| S4 | Lettura delle proprie ricette dalla finestra della professione di Forever (`GetAllRecipeIDs`, `GetRecipeInfo`, `GetBaseProfessionInfo`); serve la finestra aperta? | SPEC-06 |
| S5 | Messaggi addon su `GUILD` e `OFFICER`: codici di risultato, dimensione, ritmo sicuro, ricezione da parte di un membro semplice su `OFFICER`, blocco in istanza e durante un boss (`InChatMessagingLockdown`) | [ADR 0004](../adr/0004-guild-addon-channels-and-versioned-protocol.md), SPEC-02 |
| S6 | Whisper addon tra compagni di gilda (anche di livello basso) | voti dei like |
| S7 | Gruppo e raid: `UnitGUID` dei membri, `UnitIsInMyGuild`, `GetRaidRosterInfo`, eventuali valori segreti in istanza | SPEC-07 §3.1 |
| S8 | `BNet_GetBattleTagSelf`, `C_Club.SendBattleTagFriendRequest` | SPEC-05 §4 |
| S9 | Banca: schede visibili a un membro e a un ufficiale, oggetti, denaro, registri (formato del tempo, lunghezza), eventi | [ADR 0009](../adr/0009-guild-bank-snapshots-and-officer-approved-requests.md), SPEC-08 |
| S10 | SavedVariables per account condivise tra personaggi e reami; `GetRealmName`, reami connessi nel nome dei membri | [ADR 0006](../adr/0006-account-token-and-always-shared-character-list.md) |
| S11 | Prestazioni: costo del calcolo dell'indice e del roster con 500+ membri (dati finti generati dalla sonda) | SPEC-07 §3.2 |

Risultati in `docs/spike/M0-results.md`, con una decisione **go / revise** per ogni area.

## 2. Test offline

Runner `Tests/run_tests.py` con lupa, client finto e simulatore di rete ([ADR 0016](../adr/0016-offline-tests-with-lupa-and-a-mock-client.md)). Ogni passo aggiunge i test di ciò che costruisce. Casi obbligatori:

- account e alt: unione, personaggi rinominati, autore falso rifiutato;
- like: doppio voto, voto a se stessi o a un alt, ledger da non ufficiale rifiutato, voti in coda senza ufficiali, unione dopo il collegamento degli alt;
- indice sociale: gli esempi della tabella di SPEC-07 §3.2 come test numerici; massimo e non somma tra osservatori;
- banca: foto più recente, permessi delle schede, doppioni nei registri, passaggi di stato delle richieste solo da ufficiali;
- simulatore: 50 client convergono dopo accessi e disconnessioni casuali, con lockdown.

## 3. Verifiche nel client per milestone

Ogni milestone termina con una lista di prove in gioco (`docs/checklists/`), da fare con almeno due account o due giocatori; i risultati si segnalano con il modulo "In-game test report".

## 4. Rilascio

`v0.x` alla fine di ogni milestone dopo M1 (per la gilda del proprietario), `v0.9` beta a fine M5, `v1.0.0` a fine M6. Pacchetto con il packager BigWigs (come Azeroth Guild Finder), GitHub Releases; CurseForge facoltativo.

## 5. Rifinitura e prestazioni (M6.3)

**Stati vuoti, di caricamento e di errore.** Ogni vista dice cosa sta succedendo quando non ha nulla da mostrare (roster non ancora caricato, nessun dato della banca, nessun elenco di ricette, indice sociale in calcolo, registri e richieste vuoti), con un testo che spiega cosa fare, mai una tabella vuota. `Tests/test_states.lua` blocca questi testi e apre ogni vista, la scheda del membro, la pagina Settings e `/accord debug` in un client privo delle API facoltative (`C_Club`, `C_Spell`, `C_TradeSkillUI`, `C_GuildInfo`, la banca, BattleTag, `C_AddOns`...) senza errori Lua. Una vista che solleva un errore mentre viene costruita non porta giù il pannello: l'errore va al gestore di errori del gioco (quindi a `/accord debug`, "Last errors"), la vista mostra "This view could not be drawn" con l'invito ad allegare il rapporto, le altre viste funzionano, e un clic sulla voce di navigazione la ricostruisce da capo (`Shell:Select(id, true)`).

**Prestazioni e dimensioni.** `Tests/test_large_guild.lua` costruisce una gilda affollata: 1000 membri, 400 con l'addon (160 account), due elenchi di 250 ricette ciascuno, 90 giorni di co-play (60 osservatori, circa il 30% dei giorni, 30 coppie per record), 2000 like, 3 lettori della banca con 6 schede, registri e denaro, 120 richieste. Misura la dimensione del file salvato, la memoria e il tempo di ogni passo pesante, e fissa dei limiti circa doppi di quanto serve a un PC di sviluppo, così una macchina lenta non fallisce ma un peggioramento di dieci volte sì. I numeri sono **offline** (Lua 5.1 di lupa, non il client): quelli del gioco sono il controllo S11 ([§1](#1-spike-tecnico-m0)) e la lista di prove di rilascio.

| Misura (gilda affollata) | Offline | Limite del test |
|---|---|---|
| file `AzerothAccordDB` scritto | 3,6 MB | 8 MB |
| di cui co-play (1620 record) / like (2000) / ricette (800) / account (400) / contatti (400) | 2,6 MB / 0,54 MB / 0,47 MB / 0,23 MB / 0,09 MB | — |
| memoria del solo contenuto del registro | +5,8 MB | — |
| memoria alla fine, dopo aver aperto tutte le viste | +25 MB sul client vuoto | 80 MB |
| `/reload` con il file (serializza, carica, valida) | 0,85 s | 4 s |
| costruzione del roster di 1000 membri | 0,12 s | 1,5 s |
| raggruppamento per account | 0,01 s | 1 s |
| vista Roster: apertura, ordinamento, raggruppamento | 0,21 s | 2 s |
| indice sociale e mappa dei gruppi | 0,06 s | 2 s |
| "Who can craft", prima ricerca (indice di 200.000 voci) | 0,17 s | 2 s |
| vista Reputation / vista Bank | 0,03 s / 0,005 s | 1,5 s / 1 s |
| pagina Settings con le dimensioni | 0,26 s | 1,5 s |
| passaggio di conservazione (`Store:Prune`) | 0,001 s | 0,5 s |

Il co-play è l'ottanta per cento del file ([SPEC-10 R6](SPEC-10-risks-open-questions.md)): una gilda più attiva di questa fa crescere il file in proporzione ai giorni di conservazione (90) e al numero di osservatori, non ai membri. La pagina Settings mostra le dimensioni per insieme di dati e "Cancella i dati della gilda" le azzera; `/accord debug` riporta anche la memoria che il gioco attribuisce all'addon (`GetAddOnMemoryUsage`, [verificare] in gioco).
