# SPEC-02: Protocollo di rete

## 1. Canali

| Distribuzione | Uso | Note |
|---|---|---|
| `GUILD` | dati per tutti i membri | il server consegna solo ai membri online |
| `OFFICER` | dati riservati (segreto dei like, schede riservate della banca) | **[verificare]** S5: se non funziona per gli addon, quei dati non viaggiano |
| `WHISPER` | voto al notaio, richieste puntuali di dati | solo tra compagni di gilda |

Prefisso unico `AzAccord` ([ADR 0004](../adr/0004-guild-addon-channels-and-versioned-protocol.md)).

## 2. Formato

`<versione>|<tipo>|<payload>`: `versione` = `1`; `tipo` in maiuscolo; `payload` = Base64 di un byte di formato (`0` = CBOR così com'è, `1` = CBOR compresso con Deflate, usato solo oltre 120 byte e se accorcia) seguito dal CBOR dei campi (`Codec`). Versione e tipo sono testo in chiaro: chi riceve li legge prima di decodificare. Messaggi lunghi divisi da AceComm (pezzi di al massimo 255 byte prefisso compreso). Tipi sconosciuti o versioni maggiori: ignorati senza errori (NET-01); una versione maggiore è segnalata una volta per sessione (`PROTOCOL_NEWER`). Un modulo che aggiunge un tipo lo registra con `Codec:RegisterType`.

| Tipo | Contenuto | Distribuzione |
|---|---|---|
| `HELLO` | versione dell'addon, riepilogo per autore (§4) | `GUILD` |
| `DIGEST` | riservato: non usato dalla sincronizzazione attuale (la risposta a `HELLO` è l'invio diretto dei record, §4) | `WHISPER` |
| `REQ` | richiesta dei record di uno o più autori (chiavi del riepilogo); con `s` = un insieme (non `*`) chiede **solo i record di quell'insieme**, per una vista che li serve subito (§4, punto 7) | `WHISPER` |
| `REC` | uno o più record di un insieme | `GUILD` o `WHISPER` |
| `VOTE` | voto per un like | `WHISPER` al notaio |
| `LEDGER` | voci del libro dei like | `GUILD` |
| `SALT` | segreto di gilda per gli pseudonimi | `OFFICER` |

## 3. Insiemi di dati

`accounts`, `contacts`, `recipes`, `coplay`, `likes`, `bank`, `bankreq`. Ogni record ha `id`, `author`, `rev` (contatore crescente dell'autore) e `time` (ora del server). Vince la `rev` più alta per `id`.

## 4. Sincronizzazione

Le regole di fiducia (§6) dicono **chi** può passare un record: l'account del suo autore o un ufficiale. Per questo la sincronizzazione lavora **per autore** (`Net/Sync.lua`).

- **Riepilogo**: per ogni autore di cui il client ha record, 11 byte: chiave (hash a 32 bit del GUID), digest (24 bit di un hash dei suoi record: insieme, id, `rev`, `time`) e l'ora del record più recente. L'hash dei digest è veloce e non crittografico (una collisione può solo ritardare la sincronizzazione).

1. All'accesso, dopo 10–30 s casuali, poi ogni 15–20 minuti: `HELLO` su `GUILD` con il riepilogo.
2. **Invio**: chi riceve un `HELLO` ed è **più avanti** del mittente per un autore che può consegnare gli manda quei record in whisper (`REC`) dopo 0,5–3 s casuali: gli autori del proprio account sempre; un ufficiale anche gli autori il cui account non ha nessuno online (secondo il roster) e i record del mittente stesso che il mittente non ha più (computer nuovo, file cancellato), ma solo l'ufficiale **designato** per quel mittente (il più piccolo hash di GUID dell'ufficiale e GUID del mittente tra gli ufficiali sentiti di recente): un solo ufficiale risponde (NET-04).
3. **Richiesta**: chi vede un `HELLO` di qualcuno più avanti di lui per un autore che quello può consegnare (lo stesso autore, il suo account o un ufficiale) chiede quell'autore con `REQ` in whisper dopo 1–5 s casuali, salvo che i record siano arrivati nel frattempo. La risposta va su `GUILD` con una chiave di coda per autore e insieme: la stessa richiesta da più client parte una volta sola e tutti quelli rimasti indietro si aggiornano (NET-04).
4. Ogni modifica locale esce come `REC` su `GUILD`, accumulata per 5 s.
5. Limiti: al massimo un `HELLO` ogni 5 minuti per client; un `REC` porta al massimo circa 2,5 KB di record (stima), i più grandi si dividono.
6. Un client che ha perso i propri dati se li riprende così dagli altri, e la sua prossima scrittura riparte dalla `rev` giusta.
7. **Richiesta su misura** (`Sync:RequestSet(insieme, autore)`, per esempio le ricette di un membro quando una vista le apre e non ci sono): un `REQ` con `s` = il nome dell'insieme e la chiave dell'autore, in `WHISPER` a un solo destinatario che può consegnare: l'account dell'autore se è online, altrimenti fino a **due ufficiali** sentiti di recente (scelti per hash, sempre gli stessi). La risposta è un `REC` in `WHISPER` solo al richiedente, con i soli record di quell'insieme (non va su `GUILD`: serve a uno solo). Limiti: la stessa richiesta (insieme e autore) al massimo ogni 5 minuti; chi risponde ne accetta al massimo 20 al minuto per mittente. Se nessuno che possa consegnare è online non si manda nulla e non si ricorda nulla: la prossima chiamata riprova. Chi risponde segue le stesse regole di §4.2: l'account dell'autore o un ufficiale.

**Budget di traffico** (provato dal simulatore, `Tests/test_sync_sim.lua`: 50 client, 5 ufficiali, metà offline all'inizio, 45 minuti di accessi, uscite, scritture e lockdown casuali, 1% di messaggi persi, latenza 0,05–0,5 s):

| Situazione | Limite | Misurato |
|---|---|---|
| Accessi e uscite continui, media per client | ≤ 400 B/min | circa 320 B/min |
| Accessi e uscite continui, client più carico | ≤ 1,5 KB/min | circa 1,3 KB/min |
| Costo di un accesso (tutto il traffico che provoca, per tutta la gilda) | ≤ 8 KB | circa 5 KB |
| Tempo per convergere dopo l'ultimo accesso | ≤ 5 minuti | circa 1 minuto |
| Tutti online e allineati, media per client | ≤ 100 B/min | circa 35 B/min |
| Tutti online e allineati, client più carico | ≤ 200 B/min | circa 90 B/min |

Il riepilogo cresce di 11 byte per autore: con 200 membri con l'addon un `HELLO` pesa circa 3 KB (12 pezzi da 255 byte), ogni 15–20 minuti; per gilde molto più grandi servirà un riepilogo a blocchi (V2).

## 5. Coda e lockdown

La coda di `Transport` rispetta ChatThrottleLib e un intervallo minimo per distribuzione (`GUILD` e `OFFICER` 1 s, `WHISPER` 0,25 s, da rivedere con S5); durante `C_ChatInfo.InChatMessagingLockdown()` o con le restrizioni attive i messaggi aspettano e partono dopo (NET-05). Nulla si perde finché il client resta acceso; alla disconnessione la coda si salva (`AzerothAccordCharDB.outbox`) e riparte al prossimo accesso.

- Priorità: `ALERT` (risposte e voti: `DIGEST`, `REQ`, `VOTE`, `SALT`), `NORMAL` (`HELLO`, `REC`, `LEDGER`), `BULK`; un messaggio `BULK` che aspetta più di 10 minuti si scarta. Con una `key` resta solo l'ultimo messaggio della stessa chiave.
- `HELLO`: al massimo uno ogni 5 minuti anche a livello di coda (NET-04).
- Un rifiuto per limite di velocità si riprova dopo 5 s, al massimo 3 volte; un rifiuto per lockdown del client è un'attesa, non un tentativo.
- Ogni messaggio porta la chiave della gilda per cui è stato scritto: aspetta finché la gilda non è nota e si scarta se nel frattempo il personaggio è in un'altra gilda. Un messaggio salvato si scarta anche se la sua durata è scaduta a gioco chiuso o se è più vecchio di un giorno.
- Il client rimanda a chi scrive i suoi messaggi `GUILD` e `OFFICER`: l'eco si scarta; un'eco `OFFICER` (o un messaggio `OFFICER` di un altro) prova che il canale degli ufficiali porta i messaggi degli addon (capacità `officerAddonChannel`, S5).

## 6. Fiducia e integrità

Regole di [ADR 0005](../adr/0005-trust-first-hand-records-and-officer-relays.md):

- **Prima mano** (NET-10): un record si accetta se il mittente è l'autore o un personaggio dello stesso account dell'autore. "Stesso account" vale solo con l'**elenco reciproco**: ogni personaggio pubblica il proprio record `accounts` (id = il suo GUID) con l'elenco dei personaggi dell'account, e A e B sono dello stesso account solo se il record di A elenca B e quello di B elenca A. Il token dell'account è pubblico e non prova nulla: chi copia il token o elenca un personaggio altrui non diventa il suo account, perché quel personaggio non lo elenca.
- **Ritrasmesso** (NET-11): un record di un altro autore si accetta solo se il mittente è ufficiale secondo il roster di chi riceve.
- **Autorità** (NET-12): libro dei like, stato delle richieste in banca e schede riservate si accettano solo da ufficiali.
- **Osservazioni** (NET-13): il co-play si accetta solo da un osservatore presente nel gruppo osservato; si unisce con il massimo.
- Il nome del mittente arriva dal server e non si può falsificare; i contenuti sì, per questo valgono le regole sopra. Il mittente deve essere nel roster di chi riceve (nome con o senza reame); il suo GUID e il suo grado vengono dal roster, mai dal messaggio.
- **Regole del proprietario**: oltre alla fiducia, ogni insieme dice cosa un autore può scrivere: solo il proprio record `accounts`; `contacts` e `recipes` solo di un personaggio del proprio account; `bankreq` aperte o annullate dal richiedente (o da un suo alt), decise solo da ufficiali; schede riservate di `bank` solo da ufficiali.
- **Forma**: `id` (massimo 64 caratteri), `author` (un GUID di giocatore), `rev` intero da 1, `time` non oltre un'ora nel futuro, dimensione massima per insieme. A parità di `rev` vince il `time` più recente, poi il GUID dell'autore maggiore: ogni client tiene la stessa versione.
- **Conservazione**: co-play 90 giorni, registri della banca 365, richieste chiuse e cancellazioni 60; un record che scadrebbe subito si rifiuta.
