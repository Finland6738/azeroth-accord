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

Limiti noti, scritti nella wiki: il notaio vede chi ha votato nel momento in cui riceve il voto; un ufficiale con un addon modificato potrebbe inventare voti (come nel gioco, gli ufficiali sono fidati); un addon modificato che copia il token di un altro membro blocca i voti di entrambi (`conflict`) finché uno dei due non smette.

### 2.1 Il segreto e il notaio (`Data/Notary.lua`, M4.1)

- **Chi tiene il salt**: solo ufficiali e GM. Un client tiene i salt (`GuildKey:Data().salts`, per gilda) solo finché il suo personaggio è ufficiale, li cancella se viene retrocesso, e non risponde né accetta un salt da chi non è ufficiale nel **proprio** roster. Un salt = 32 byte casuali, scritti in Base64.
- **Casualità**: il client non ha una fonte casuale sicura (nessuna API nel dump di Forever). `Hash.RandomBytes` fa l'hash SHA-256 di un serbatoio di entropia con molte letture fresche (l'orologio del profiler in un ciclo che varia, gli orologi del frame e del server, la memoria di Lua, gli indirizzi di tabelle nuove) e con gli orari di arrivo dei messaggi dell'addon raccolti nella sessione (`Hash.Stir`); il serbatoio si rinnova a ogni estrazione. Non è un generatore crittografico, ma il salt non si indovina dall'ora in cui è nato.
- **Scambio**: messaggi `SALT` su `OFFICER`. 15–30 s dopo l'accesso (o la promozione) un ufficiale chiede (`k = "q"` con le impronte dei salt che ha: 12 cifre esadecimali di un hash, mai il salt); chi ha salt che mancano a chi chiede li manda (`k = "s"`) dopo 0,5–3 s, a meno che un altro ufficiale li abbia già mandati su `OFFICER`. Chi sente impronte che non ha chiede a sua volta (al massimo una volta al minuto). I messaggi `SALT` hanno 60 s di vita: non si salvano per l'accesso dopo.
- **Ripiego per S5** **[verificare]**: finché il client non ha visto un messaggio addon su `OFFICER` (capacità `officerAddonChannel` diversa da `available`), ogni messaggio `SALT` parte **anche** in whisper a ogni ufficiale con l'addon sentito di recente (`Sync:Peers`), e una domanda arrivata in whisper ha la risposta in whisper.
- **Creazione**: un ufficiale che 45 s dopo aver chiesto non ha ancora un salt lo crea e lo manda. Se due ufficiali lo creano insieme, si tengono **tutti** (un anello di al massimo 8, i più vecchi) e tutti usano lo stesso salt **corrente**: il più vecchio per data di creazione, poi per impronta. Il notaio controlla il doppio voto con **ogni** salt dell'anello (M4.2), quindi due salt non permettono due voti.
- **LIKE-07**: se esce l'ultimo ufficiale che ha i salt, il primo ufficiale che chiede senza risposta ne crea uno nuovo; le voci vecchie restano valide, ma il controllo del doppio voto per i voti dati con il salt perso non c'è più (limite scritto nella wiki).
- **Scelta del notaio**: il client stesso se è un ufficiale con un salt; altrimenti gli ufficiali con l'addon sentiti di recente, in ordine di un hash di GUID dell'ufficiale e GUID del votante (sempre lo stesso per un votante, distribuito tra gli ufficiali), saltando quelli già provati per quel voto (`Notary:Choose`). Nessuno disponibile: il voto resta in coda (LIKE-05).

### 2.2 Voti e libro (`Data/Likes.lua`, M4.2)

- **Coda del votante**: `Likes:Give(guid)` mette il voto in una coda tenuta su questo computer per la gilda (`GuildKey:Data().likes`, comune a tutti i personaggi dell'account, con l'elenco degli account già votati). Ogni 15 s i voti in coda vanno in `WHISPER` (`VOTE`, `g` = GUID del destinatario, `n` = numero casuale) al notaio scelto da `Notary:Choose`. Nessun ufficiale online: il voto aspetta (`pending`). Un `VOTE` vive 40 s e non si salva per l'accesso dopo (la coda sì).
- **Ricevuta**: il notaio risponde in `WHISPER` con `LEDGER` (`g`, `n`, `r` = esito, `e` = la voce nuova). `ok` e `dup` (già votato) segnano l'account come votato e il pulsante sparisce da tutti i suoi personaggi; `self`, `target` e `conflict` tolgono il voto dalla coda; `nosalt`, `unknown` e `rate` riprovano più tardi (lo stesso ufficiale dopo 60 s; uno che non risponde entro 45 s dopo 5 minuti, intanto si prova il successivo). Una ricevuta conta solo se viene da un ufficiale del proprio roster e porta il numero del voto.
- **Controlli del notaio** (LIKE-06): mittente nel roster, account noto (il suo record `accounts` con il token), destinatario membro della gilda e non dell'account del votante (`self`), nessun personaggio fuori dall'account del votante che pubblichi lo stesso token (`conflict`: il token è pubblico e si potrebbe copiare, e una copia avrebbe lo stesso pseudonimo), al massimo 20 voti al minuto per mittente (`rate`). Un ufficiale con un salt fa da notaio ai propri voti, senza messaggi.
- **Voce**: `{ pseudonym, tag, target, day }`, autore = il notaio. `pseudonym` = le prime 32 cifre esadecimali (128 bit, troncamento ammesso da RFC 2104) di `HMAC-SHA256(salt, token del votante)`; `tag` = le prime 16 di `HMAC-SHA256(salt, "char:" .. GUID del personaggio che vota)`; `day` = giorno del reame. Id = `<prime 16 cifre dello pseudonimo>:<GUID del destinatario>`. La voce va nello `Store` del notaio e la sincronizzazione la manda su `GUILD` come `REC` dell'insieme `likes`, con le stesse regole di ogni record.
- **Doppio voto**: il notaio confronta, con **ogni** salt dell'anello, gli pseudonimi di ogni token dei personaggi del votante e i tag di ogni suo personaggio con le voci che hanno come destinatario un personaggio dell'account del destinatario. Così è `dup` anche un voto ridato dopo un token nuovo (un altro computer), da un alt, a un alt, o con il salt di un altro ufficiale.
- **Solo aggiunte** (LIKE-03): lo `Store` accetta una voce di `likes` solo da un ufficiale (NET-12), solo con `rev` 1, solo con l'id ricavato dal contenuto, e non sostituisce mai una voce che ha (`immutable`). L'autore non deve essere ancora ufficiale: una voce resta valida se il notaio è uscito o è stato retrocesso (LIKE-07).
- **Totale** (LIKE-04): il numero di `pseudonym` **distinti** fra le voci il cui destinatario è un personaggio dell'account; i personaggi uniti solo da una nota pubblica (`main:` / `alt:`) non contano. Quando due personaggi si uniscono più tardi (elenco reciproco) i loro like si sommano senza contare due volte lo stesso votante.

### 2.3 Interfaccia dei like (`UI/Reputation.lua`, M4.3)

- **Scheda del membro**: una sezione *Likes* con il totale dell'account ("uguale su tutti i personaggi") e, se si può votare, **[Like this player]**; il primo clic chiede conferma (il testo diventa "clicca ancora: un like non si può ritirare"), il secondo entro 8 s dà il like. Poi la riga dice "in attesa di un ufficiale" (LIKE-05) o "hai dato il like"; sui propri personaggi non c'è nessuna azione (LIKE-02).
- **Colonna Likes** del roster, ora tra le colonne predefinite: il totale dell'account; verde se il giocatore gli ha dato il like, grigio se il like aspetta un ufficiale.
- **Vista Reputation** (LIKE-08), per tutti: una riga per account con almeno un personaggio nella gilda (il main se è nella gilda, altrimenti il personaggio di livello più alto; quanti personaggi), posto in classifica (a pari like lo stesso posto), totale, e il pulsante **Like** (due clic) o lo stato ("dato", "in attesa", "tu"). Si ordina per like o per nome dalle intestazioni; la casella di ricerca del pannello filtra per qualunque personaggio dell'account; un clic sulla riga apre la scheda del membro nel Roster. Nessuna riga dice chi ha votato (LIKE-04).
- Un rifiuto del notaio (`self`, `target`, `conflict`) si dice in chat. La vista ha **modalità** (pulsanti in alto) a cui i passi successivi aggiungono l'indice sociale, la mappa dei gruppi e i compagni suggeriti; una modalità riservata agli ufficiali non ha il pulsante per gli altri.

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

Realizzazione (`Data/Social.lua`, M4.4; i tre esempi qui sopra sono test numerici in `Tests/test_social.lua`):

- **Finestra**: i 30 giorni del reame che finiscono oggi, oggi compreso (`Social.CutoffDay`, aritmetica delle date senza `time()`).
- **Osservatori**: per giorno e coppia di personaggi vale il **massimo** tra gli osservatori, mai la somma (NET-13).
- **Account**: i personaggi diventano account con `Accounts:AccountKey` (i personaggi **provati** dall'elenco reciproco; una nota `main:`/`alt:` non unisce nulla, come per i like); una coppia di due personaggi dello stesso account si lascia fuori; i minuti si sommano sui giorni e sui personaggi.
- **Minuti**: `M` = Σ `m_b` conta i minuti **per compagno**: un'ora con quattro compagni di gilda vale quattro ore. Le coppie non dicono quanto tempo il giocatore è stato in gruppo, solo con chi; "5 ore" (SOC-04) e "60 minuti" (per `A`) si misurano così.
- **A** = gli account con almeno 60 minuti nella finestra; l'indice c'è solo con almeno 5 ore e `A ≥ 2`.
- **A pezzi** (SOC-06): una coroutine che si ferma ogni 40 record (o giorni, o account) e riparte al frame dopo con `C_Timer.After(0)`; si ricalcola solo se i dati sono cambiati e l'ultimo calcolo ha più di 10 minuti (o se si chiede esplicitamente), la prima volta 90 s dopo l'accesso. Misura offline: 200 account e 30 giorni (circa 3000 coppie) in circa 10 ms. Il risultato tiene anche il grafo degli account (minuti per coppia di account) per la mappa dei gruppi e i compagni suggeriti.

Interfaccia (`UI/Social.lua`, M4.5):

- **Scheda del membro** (SOC-05): sezione *Social index* con l'indice su 100, i compagni effettivi su quanti giocatori attivi, i compagni diversi, il tempo con compagni di gilda (contato per compagno) e i 5 con cui ha giocato di più con la loro quota; un **tooltip** sulla riga dell'indice spiega cosa misura (e che non dice chi è un buon giocatore, R7). Sotto le 5 ore: "dati insufficienti (x h delle 5 h)"; senza gioco di gruppo: "nessun gioco di gruppo negli ultimi 30 giorni"; prima del primo calcolo: "in calcolo".
- **Colonna Social** del roster: l'indice, un trattino sotto le 5 ore; solo per chi vede l'indice degli altri.
- **Vista Reputation, modalità Social**: il proprio indice con lo stesso dettaglio; per chi vede gli altri, l'elenco di tutti per indice (dati insufficienti in fondo), una riga apre la scheda.
- **Chi vede cosa** (SOC-12, Q3 **ancora aperta**): è attuata la proposta di SPEC-10, ognuno il **proprio** indice, ufficiali e GM quello di **tutti** (e la mappa, M4.6). Il punto da cambiare quando il proprietario decide è uno solo: `Social.OTHERS_VISIBLE_TO` in `Data/Social.lua` (`"officers"` o `"everyone"`). Il calcolo resta locale e uguale per tutti: la regola decide solo cosa si mostra.

### 3.3 Mappa dei gruppi

- SOC-10: grafo degli account (peso = minuti insieme); comunità con *label propagation* pesata; **modularità** `Q` come indice di mescolanza della gilda ("bassa: tutti giocano con tutti", "alta: gruppetti").
- SOC-11: vista con l'elenco delle comunità (membri, minuti interni contro minuti verso l'esterno) e un disegno semplice a cerchi.
- SOC-12: visibile a tutti per l'indice personale; la mappa completa è per ufficiali e GM (domanda Q3 in [SPEC-10](SPEC-10-risks-open-questions.md)).

Realizzazione (`Data/GroupMap.lua`, `UI/GroupMap.lua`, M4.6):

- **Grafo**: quello dell'indice sociale (minuti per coppia di account negli ultimi 30 giorni), calcolato una volta per risultato.
- **Comunità**: *label propagation* pesata e deterministica: ogni account parte con la propria etichetta; a turni, in ordine fisso, prende l'etichetta con più minuti tra i suoi compagni (a parità tiene la propria, altrimenti la più piccola); si ferma quando un turno non cambia nulla (al massimo 30). Stessi dati, stessi gruppi su ogni client.
- **Modularità** `Q = Σ_c [L_c/m − (d_c/2m)²]` (m = minuti di tutte le coppie, `L_c` minuti dentro `c`, `d_c` somma dei minuti degli account di `c`); lettura: sotto 0,3 "ben mescolata", da 0,3 "qualche gruppo", da 0,5 "gruppetti".
- **Vista** (modalità *Groups* della vista Reputation, solo per ufficiali e GM finché Q3 è aperta): il riepilogo (lettura e valore di `Q`, giocatori, gruppi, ore insieme), un disegno con un cerchio di punti colorati per gruppo (il nome al passaggio del mouse, un clic apre la scheda, cerchi più grandi per gruppi più grandi) e l'elenco dei gruppi con i giocatori (per minuti insieme) e i minuti dentro il gruppo contro quelli con il resto della gilda.
- Provato offline: due triangoli uniti da un ponte debole danno due gruppi e `Q = 2·(30/61 − 1/4) ≈ 0,4836`; quattro gruppetti danno "gruppetti"; 200 account in pochi millisecondi.

### 3.4 Compagni suggeriti

- SOC-20: riquadro "Play with someone new": membri **online adesso**, di livello compatibile, con cui il giocatore ha giocato meno di 30 minuti negli ultimi 30 giorni; pulsanti Whisper e Invite (azioni del giocatore).

Realizzazione (`UI/Suggest.lua`, M4.7): modalità *Someone new* della vista Reputation, per tutti. "Livello compatibile" = al massimo 5 livelli di differenza; i minuti sono quelli del grafo dell'indice sociale (tutti i personaggi dei due giocatori; senza un calcolo ancora fatto valgono 0); una riga per giocatore (il suo personaggio online più vicino di livello), prima chi ha meno minuti insieme, poi il livello più vicino, al massimo 12. **Whisper** apre la casella della chat con `/w Nome ` (l'addon non manda nulla); **Invite** chiama `C_PartyInfo.InviteUnit` (nel dump; altrimenti `InviteUnit`, **[verificare]**) e lo dice in chat.
