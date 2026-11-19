# SPEC-07: Reputazione e indice sociale

## 1. Scopo

Due segnali diversi: i **like** dicono quanto un giocatore è apprezzato dagli altri; l'**indice sociale** misura in automatico se un giocatore gioca con tanti compagni diversi oppure sempre con lo stesso gruppetto, e la **mappa dei gruppi** mostra se la gilda si divide.

## 2. Like

Decisioni D1 e D2, [ADR 0007](../adr/0007-likes-one-per-account-irreversible-anonymous.md).

| ID | Requisito |
|---|---|
| LIKE-01 | Un account dà **al massimo un like** a ciascun altro account. Il pulsante Like compare su ogni personaggio del destinatario; dopo il voto sparisce da tutti. |
| LIKE-02 | Mai a se stessi né ai personaggi del proprio account. |
| LIKE-03 | **Irrevocabile**: non esiste "togli like". |
| LIKE-04 | **Anonimo**: l'interfaccia mostra solo il totale dell'account destinatario, su tutti i suoi personaggi. Nessuna vista dice chi ha votato. |
| LIKE-05 | Il voto viaggia in whisper a un **ufficiale online** (il notaio), mai su `GUILD`. Se nessun ufficiale è online il voto aspetta in coda e la tab mostra "pending". |
| LIKE-06 | Il notaio verifica (mittente in gilda, account noto, non se stesso, non già votato), calcola lo pseudonimo `HMAC-SHA256(salt, tokenDelVotante)` e pubblica la voce `{pseudonym, target, day}` su `GUILD`. |
| LIKE-07 | Il `salt` lo crea il primo ufficiale o il GM con l'addon, viaggia solo su `OFFICER` e resta solo nei client degli ufficiali. Se l'ultimo ufficiale con il salt lascia la gilda, un nuovo salt riparte da zero solo per i voti nuovi: le voci vecchie restano valide. |
| LIKE-08 | Classifica: vista Reputation con l'elenco degli account ordinabile per like; visibile a tutti. |
| LIKE-09 | Chi non ha l'addon può ricevere like (sul personaggio, che si unisce al suo account quando installa l'addon) ma non darne. |

Limiti noti, scritti nella wiki: il notaio vede chi ha votato nel momento in cui riceve il voto; un ufficiale con un addon modificato potrebbe inventare voti (come nel gioco, gli ufficiali sono fidati).

### 2.1 Il segreto e il notaio (`Data/Notary.lua`, M4.1)

- **Chi tiene il salt**: solo ufficiali e GM. Un client tiene i salt (`GuildKey:Data().salts`, per gilda) solo finché il suo personaggio è ufficiale, li cancella se viene retrocesso, e non risponde né accetta un salt da chi non è ufficiale nel **proprio** roster. Un salt = 32 byte casuali, scritti in Base64.
- **Casualità**: il client non ha una fonte casuale sicura (nessuna API nel dump di Forever). `Hash.RandomBytes` fa l'hash SHA-256 di un serbatoio di entropia con molte letture fresche (l'orologio del profiler in un ciclo che varia, gli orologi del frame e del server, la memoria di Lua, gli indirizzi di tabelle nuove) e con gli orari di arrivo dei messaggi dell'addon raccolti nella sessione (`Hash.Stir`); il serbatoio si rinnova a ogni estrazione. Non è un generatore crittografico, ma il salt non si indovina dall'ora in cui è nato.
- **Scambio**: messaggi `SALT` su `OFFICER`. 15–30 s dopo l'accesso (o la promozione) un ufficiale chiede (`k = "q"` con le impronte dei salt che ha: 12 cifre esadecimali di un hash, mai il salt); chi ha salt che mancano a chi chiede li manda (`k = "s"`) dopo 0,5–3 s, a meno che un altro ufficiale li abbia già mandati su `OFFICER`. Chi sente impronte che non ha chiede a sua volta (al massimo una volta al minuto). I messaggi `SALT` hanno 60 s di vita: non si salvano per l'accesso dopo.
- **Ripiego per S5** **[verificare]**: finché il client non ha visto un messaggio addon su `OFFICER` (capacità `officerAddonChannel` diversa da `available`), ogni messaggio `SALT` parte **anche** in whisper a ogni ufficiale con l'addon sentito di recente (`Sync:Peers`), e una domanda arrivata in whisper ha la risposta in whisper.
- **Creazione**: un ufficiale che 45 s dopo aver chiesto non ha ancora un salt lo crea e lo manda. Se due ufficiali lo creano insieme, si tengono **tutti** (un anello di al massimo 8, i più vecchi) e tutti usano lo stesso salt **corrente**: il più vecchio per data di creazione, poi per impronta. Il notaio controlla il doppio voto con **ogni** salt dell'anello (M4.2), quindi due salt non permettono due voti.
- **LIKE-07**: se esce l'ultimo ufficiale che ha i salt, il primo ufficiale che chiede senza risposta ne crea uno nuovo; le voci vecchie restano valide, ma il controllo del doppio voto per i voti dati con il salt perso non c'è più (limite scritto nella wiki).
- **Scelta del notaio**: il client stesso se è un ufficiale con un salt; altrimenti gli ufficiali con l'addon sentiti di recente, in ordine di un hash di GUID dell'ufficiale e GUID del votante (sempre lo stesso per un votante, distribuito tra gli ufficiali), saltando quelli già provati per quel voto (`Notary:Choose`). Nessuno disponibile: il voto resta in coda (LIKE-05).

## 3. Indice sociale

[ADR 0008](../adr/0008-social-breadth-index-from-co-play.md).

### 3.1 Registrazione (da M2, D6)

- SOC-01: ogni 60 s, se il giocatore è in un gruppo o raid (`IsInGroup`, `GetNumGroupMembers`, `UnitGUID("party1..4"/"raid1..40")`, `UnitIsInMyGuild`) con almeno un altro membro della gilda, aggiunge 1 minuto a **ogni coppia** di membri della gilda presenti nel gruppo **[verificare]** S7.
- SOC-02: si conta anche dentro istanze e raid; l'invio dei dati aspetta la fine del lockdown.
- SOC-03: i dati si pubblicano una volta all'ora e alla disconnessione, per giorno; si uniscono con il **massimo** per coppia e giorno.

Realizzazione (`Data/CoPlay.lua`, M2.6; nessuna vista, solo `/accord debug` con i conteggi):

- Un `C_Timer.NewTicker` di 60 s, avviato all'accesso. Ogni conteggio legge il gruppo (`Compat.Group.Members`), tiene i membri della gilda (`UnitIsInMyGuild`, altrimenti il roster) e aggiunge 1 minuto a **ogni coppia** tra loro, il giocatore compreso. Un membro con GUID nascosto (valore segreto) si riconosce dal nome, se leggibile, tramite il roster; se anche il nome è nascosto si **conta come illeggibile e si lascia fuori**, mai indovinato (`/accord debug` ne dà il numero). Quando almeno un conteggio riconosce i membri senza buchi la capacità `groupGUIDs` passa a `available` **[verificare]** S7.
- Il giorno è quello del calendario del reame (`C_DateAndTime.GetCurrentCalendarTime`, altrimenti la data UTC del `GetServerTime`), come numero `AAAAMMGG`. Una coppia non supera 1440 minuti al giorno.
- **Pubblicazione**: una volta all'ora, alla disconnessione (`PLAYER_LOGOUT`) e al primo conteggio del giorno dopo (per ieri). I minuti si tengono in memoria e partono solo quando cambiano; il lockdown ritarda l'invio (Transport), non il conteggio (SOC-02). Dopo un `/reload` il conteggio riparte da quanto era stato pubblicato.
- **Record a pezzi**: id = `<osservatore>:<giorno>:<n>`, al massimo 100 coppie per record (una raid di 40 ha 780 coppie: 8 pezzi, ciascuno sotto il limite di 8 KB), ogni pezzo con almeno una coppia dell'osservatore (regola NET-13). Solo i pezzi cambiati si riscrivono.
- Più osservatori dello stesso gruppo danno il **massimo** per coppia e giorno (`Store:MergeMax`), non la somma: provato con tre client del simulatore nello stesso gruppo (10 minuti, non 30). Conservazione 90 giorni (`Store:Prune`).

### 3.2 Calcolo

Per ogni account `a` nella finestra degli ultimi 30 giorni:

- `m_b` = minuti giocati con l'account `b` (somma sui giorni, alt uniti); `M = Σ m_b`
- `p_b = m_b / M`
- **compagni effettivi** `N = exp(−Σ p_b · ln p_b)`
- `A` = account attivi nella finestra (almeno 60 minuti di gioco di gruppo in gilda)
- **indice** `= min(100, round(100 · N / (A − 1)))`

| Esempio (A = 41) | N | Indice |
|---|---|---|
| 100 ore sempre con le stesse 4 persone, in parti uguali | 4 | 10 |
| 100 ore, metà con 1 amico e il resto sparso su 20 persone | ≈ 8,9 | 22 |
| 60 ore divise in modo uguale fra 30 persone | 30 | 75 |

- SOC-04: sotto 5 ore di gioco di gruppo in gilda nella finestra l'indice è "not enough data".
- SOC-05: la scheda membro mostra l'indice, `N`, il numero di compagni distinti e i 5 compagni principali con la loro quota.
- SOC-06: il calcolo si fa in locale, al massimo una volta ogni 10 minuti, a pezzi per non bloccare il client.

### 3.3 Mappa dei gruppi

- SOC-10: grafo degli account (peso = minuti insieme); comunità con *label propagation* pesata; **modularità** `Q` come indice di mescolanza della gilda ("bassa: tutti giocano con tutti", "alta: gruppetti").
- SOC-11: vista con l'elenco delle comunità (membri, minuti interni contro minuti verso l'esterno) e un disegno semplice a cerchi.
- SOC-12: visibile a tutti per l'indice personale; la mappa completa è per ufficiali e GM (domanda Q3 in [SPEC-10](SPEC-10-risks-open-questions.md)).

### 3.4 Compagni suggeriti

- SOC-20: riquadro "Play with someone new": membri **online adesso**, di livello compatibile, con cui il giocatore ha giocato meno di 30 minuti negli ultimi 30 giorni; pulsanti Whisper e Invite (azioni del giocatore).
