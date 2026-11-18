# SPEC-00: Visione, ambito e ruoli

## 1. Problema

La finestra della Gilda di WoW Forever è scarna: un elenco di nomi, gradi e note. Non dice chi sa fare cosa, chi è l'alt di chi, come contattare un compagno fuori dal gioco, cosa c'è in banca, né se la gilda gioca davvero insieme o si divide in gruppetti. Accord aggiunge queste informazioni **dentro la finestra della Gilda**, con una scheda in più.

## 2. Obiettivi

1. Ogni membro trova in pochi secondi **chi sa creare un oggetto** e gli chiede di farlo.
2. Cliccando su un personaggio si vedono **tutti i personaggi dello stesso account** sul reame, senza chiedere.
3. Il roster mostra i **contatti** Battle.net e Discord di chi usa l'addon.
4. La gilda vede la **banca** anche lontano dal forziere, con richieste di prelievo e deposito e lo storico delle donazioni.
5. I membri si danno **like** (apprezzamento) e il GM vede un **indice sociale** che dice chi gioca con tanti compagni diversi e se si formano gruppetti.
6. Tutto resta **dentro la gilda**: nessun server esterno, nessun dato fuori dal gioco ([ADR 0001](../adr/0001-client-only-addon-guild-only-data.md)).

## 3. Cosa resta fuori (sempre)

- Nessun server esterno, nessun collegamento a internet, nessuna telemetria.
- Nessuna azione automatica sulla banca o sui gradi: l'addon mostra, propone e registra; prelievi, depositi, inviti e promozioni restano azioni del giocatore nel gioco.
- Nessun dato condiviso fuori dalla propria gilda.

## 4. Ambito per versione

### V1 (`v1.0.0`)

| Area | Contenuto | Milestone |
|---|---|---|
| Scheda Accord | tab nella finestra Gilda, pannello con navigazione, finestra autonoma, `/accord` | M1 |
| Roster esteso | tabella ordinabile e filtrabile: nome, livello, classe, grado, zona, ultimo accesso, professione 1 e 2, like, indice sociale, contatti | M2 |
| Alt | personaggi dello stesso account sul reame, main scelto dal giocatore | M2 |
| Contatti | BattleTag e Discord sempre condivisi, copia con un clic, richiesta d'amicizia BattleTag nativa | M2 |
| Professioni | clic sulla professione di un membro → elenco delle sue ricette; ricerca "chi sa fare X"; richiesta di crafting | M3 |
| Reputazione | like da account ad account, irrevocabili e anonimi; indice sociale; mappa dei gruppi; compagni suggeriti | M4 |
| Banca | foto per scheda, ricerca, registri, donazioni, richieste di prelievo/deposito/donazione con approvazione degli ufficiali | M5 |
| Rilascio | impostazioni, inglese e italiano, pacchetto, wiki | M6 |

### V2 e successive (backlog)

Iscrizioni ai raid e presenze, integrazione con il sistema di loot della gilda, bacheca e note extra, obiettivi collettivi, sondaggi, mappa delle fasce orarie, strumenti per ufficiali (inattivi, promozioni), export. Dettagli in [docs/roadmap/V2-backlog.md](../roadmap/V2-backlog.md).

## 5. Ruoli

Il ruolo si ricava dal client e si aggiorna a ogni `PLAYER_GUILD_UPDATE`, `GUILD_ROSTER_UPDATE` e `GUILD_RANKS_UPDATE`.

| Ruolo | Come si riconosce | Cosa aggiunge |
|---|---|---|
| Membro | `IsInGuild()` | tutte le viste in lettura, like, richieste in banca, richieste di crafting |
| Ufficiale | `C_GuildInfo.IsGuildOfficer()` | notaio dei like, approvazione delle richieste in banca, foto delle schede riservate, indice sociale di tutta la gilda |
| GM | `IsGuildLeader()` | come l'ufficiale, più la creazione del segreto di gilda se nessun ufficiale lo ha ancora |

Senza gilda la scheda non compare; `/accord` dice "You are not in a guild".

## 6. Registro delle decisioni

| # | Decisione | Fonte |
|---|---|---|
| D1 | Like **da account ad account**: un solo like per account verso ciascun altro account; il totale si vede su tutti i personaggi del destinatario; mai a se stessi né ai propri alt | proprietario, 2026-11-18 |
| D2 | Like **anonimi**: si mostra solo il totale | proprietario, 2026-11-18 |
| D3 | Elenco degli alt, BattleTag e Discord **sempre condivisi** con la gilda (nessuna opzione per spegnerli) | proprietario, 2026-11-18 |
| D4 | Ordine delle milestone: roster → professioni → reputazione → banca | proprietario, 2026-11-18 |
| D5 | Nome **Azeroth Accord**, repository `azeroth-accord`, licenza GPL-3.0 | proprietario, 2026-11-18 |
| D6 | Registrazione del gioco di gruppo attiva **già da M2**, anche se l'indice sociale si vede da M4, così lo storico esiste quando arriva la vista | proposta, approvata con il piano |
| D7 | Nomi tecnici proposti: cartella `AzerothAccord`, prefisso `AzAccord`, comandi `/accord` e `/acc` | proposta, da confermare (Q1 in [SPEC-10](SPEC-10-risks-open-questions.md)) |
