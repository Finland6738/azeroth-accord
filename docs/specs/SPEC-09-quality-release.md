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
