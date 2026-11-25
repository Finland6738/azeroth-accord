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

Ogni milestone rilascia `v0.<milestone>.0` (da `v0.1.0` a fine M1 fino a `v0.15.0` a fine M15); le correzioni di una milestone alzano solo l'ultimo numero (`v0.6.1`, `v0.6.2`); `v1.0.0` arriva quando tutte le milestone previste sono finite ([ADR 0020](../adr/0020-one-version-per-milestone.md)). Pacchetto con il packager BigWigs (come Azeroth Guild Finder), GitHub Releases; CurseForge facoltativo e spento finché il proprietario non decide ([SPEC-10 Q9](SPEC-10-risks-open-questions.md)). Il flusso (`.github/workflows/release.yml`, `docs/RELEASING.md`) parte solo con un tag `vX.Y.Z[-alpha|-beta|-rc[.N]]` o a mano: controlla il contenuto (`tools/check_package.py`), costruisce lo zip, lo ricontrolla, lo tiene come artefatto per 14 giorni, crea la GitHub Release con le note prese da `CHANGELOG.md` (`tools/release_notes.py`) e, solo se configurato, carica su CurseForge. Decisione del proprietario del 2026-11-25: il primo rilascio è `v0.8.0`, prima delle prove in gioco (da `v0.1.0` a `v0.7.0` non vengono taggate); da M9 in poi `v0.<N>.0` esce dopo ogni milestone completata, e i pezzi non finiti delle milestone successive restano spenti (`Core/Features.lua`). I passi di sviluppo non creano tag.

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

## 6. Diagnostica e segnalazioni (M6.4)

`/accord debug` ([SPEC-04 §4](SPEC-04-ui-guild-tab-shell.md)) apre il rapporto (`Core/Diagnostics.lua`, `UI/DiagnosticsBox.lua`) in una casella a sola lettura, già selezionata, con il numero di righe e di caratteri. Regole:

- **Nessun nome.** Il rapporto si costruisce solo da parole fisse e numeri: nessun nome di giocatore, di gilda o di reame, nessun BattleTag o nome Discord, nessun token dell'account, nessun GUID, nessuna cartella del PC. `Tests/test_report.lua` riempie una gilda di nomi (roster, note, account, contatti, richieste con testo, registri) e verifica che nessuno compaia. L'unico testo libero è il messaggio degli errori dell'addon: `Diag.Redact` sostituisce con `<player>` e `<guild>` ogni nome che il client conosce (personaggio, gilda, compagni, BattleTag, Discord, anche nella forma `Nome-Reame`, solo parole intere, almeno 3 caratteri) e qualunque cosa abbia la forma di un BattleTag.
- **Intestazione allineata al modulo.** Le prime righe (`addon:`, `client:` e `locale:`, `role:`, `guild size:`) sono i campi del modulo "Bug report" (`.github/ISSUE_TEMPLATE/bug_report.yml`), con gli stessi nomi; `tools/check_addon.py` fallisce se una riga dell'intestazione non è nominata nel modulo. Anche il modulo "In-game test report" accetta il rapporto, con l'id della prova (`M3 step 4`).
- **Limite.** 30.000 caratteri, tagliati sul confine di una riga e con l'avviso; contano le prime sezioni (intestazione, invio, ultimi errori).
- **Contenuto.** Capacità e API (Compat), stato dell'invio, ultimi errori, dimensioni dei dati salvati e memoria (§5), una sezione per modulo con soli conteggi e stati.

## 7. Budget di traffico condiviso (M10)

Il budget di [SPEC-02 §4](SPEC-02-network-protocol.md#4-sincronizzazione) misura **solo Accord**: la media per client durante accessi e uscite è al massimo **450 B/min** dopo M9.10 (era 400, alzata con il censimento degli addon acceso, [SPEC-10 R14](SPEC-10-risks-open-questions.md)), il client più carico al massimo 2 KB/min. Ma i limiti del server sui messaggi degli addon valgono per **tutti gli addon del giocatore insieme**: FDCP, gli addon di loot di [M11](../roadmap/M11-loot-handbook.md#addons-on-wow-forever) e gli altri mandano sugli stessi canali `GUILD`, `OFFICER` e `WHISPER` (regola di integrazione 9 di [M10](../roadmap/M10-calendar-raids.md#integration-rules-owner-2026-11-24), [SPEC-14](SPEC-14-calendar-raids-season.md) RAID-08). Regole da M10:

- **Il limite della media non sale per M10.** Quello che M10 aggiunge (season, ruoli per evento, importazioni, disponibilità, raduni) è stimato sotto i 20 B/min per client ([SPEC-14 §11](SPEC-14-calendar-raids-season.md#11-traffico)) e deve stare nei 450 B/min di oggi, misurato nel simulatore da M10.3, M10.5 e M10.8. Se non ci sta, prima si riduce il traffico (meno pubblicazioni, riepiloghi a parte come il censimento), poi si chiede al proprietario, come per R10 e R14.
- **Coda condivisa.** Accord manda attraverso ChatThrottleLib, la stessa libreria di AceComm che usa FDCP: la banda del client si divide tra gli addon che la usano, e un addon non affama l'altro. Un addon che non la usa resta fuori da questo equilibrio: per questo Accord tiene i suoi intervalli minimi per distribuzione ([SPEC-02 §5](SPEC-02-network-protocol.md#5-coda-e-lockdown)).
- **Silenzio durante i boss** ([SPEC-14 §10](SPEC-14-calendar-raids-season.md#10-silenzio-durante-i-boss)): da `ENCOUNTER_START` a `ENCOUNTER_END` Accord non manda messaggi `NORMAL` né `BULK`, come FDCP, che durante un raid manda i suoi.
- **Prova con FDCP.** La prova in gioco di M10.10 misura il traffico di Accord con FDCP caricato durante una serata di raid (`/accord debug`, sezione dell'invio) e controlla che nessuno dei due addon veda rifiuti per limite di velocità.
