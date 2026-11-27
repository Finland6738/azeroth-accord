# SPEC-02: Protocollo di rete

## 1. Canali

| Distribuzione | Uso | Note |
|---|---|---|
| `GUILD` | dati per tutti i membri | il server consegna solo ai membri online |
| `OFFICER` | dati riservati (segreto dei like, schede riservate della banca, da M8 gli strumenti per ufficiali di [SPEC-12](SPEC-12-officer-tools.md), che senza S5 restano locali) | **[verificare]** S5: finché il client non ha visto un messaggio addon su `OFFICER`, il segreto dei like viaggia anche in whisper tra ufficiali ([SPEC-07 §2.1](SPEC-07-reputation-social.md#21-il-segreto-e-il-notaio-datanotarylua-m41)); le schede riservate della banca no |
| `WHISPER` | voto al notaio, richieste puntuali di dati | solo tra compagni di gilda |

Prefisso unico `AzAccord` ([ADR 0004](../adr/0004-guild-addon-channels-and-versioned-protocol.md)).

## 2. Formato

`<versione>|<tipo>|<payload>`: `versione` = `1`; `tipo` in maiuscolo; `payload` = Base64 di un byte di formato (`0` = CBOR così com'è, `1` = CBOR compresso con Deflate, usato solo oltre 120 byte e se accorcia) seguito dal CBOR dei campi (`Codec`). Versione e tipo sono testo in chiaro: chi riceve li legge prima di decodificare. Messaggi lunghi divisi da AceComm (pezzi di al massimo 255 byte prefisso compreso). Tipi sconosciuti o versioni maggiori: ignorati senza errori (NET-01); una versione maggiore è segnalata una volta per sessione (`PROTOCOL_NEWER`). Un modulo che aggiunge un tipo lo registra con `Codec:RegisterType`.

| Tipo | Contenuto | Distribuzione |
|---|---|---|
| `HELLO` | versione dell'addon, riepilogo per autore (§4); da M9.9 `c` = il riepilogo a parte del censimento degli addon | `GUILD` |
| `DIGEST` | riservato: non usato dalla sincronizzazione attuale (la risposta a `HELLO` è l'invio diretto dei record, §4) | `WHISPER` |
| `REQ` | richiesta dei record di uno o più autori (chiavi del riepilogo); con `s` = un insieme (non `*`) chiede **solo i record di quell'insieme**, per una vista che li serve subito (§4, punto 7) | `WHISPER` |
| `REC` | uno o più record di un insieme | `GUILD` o `WHISPER` |
| `OHELLO` | come `HELLO` ma per i **record solo per ufficiali** (le schede della banca lette da un ufficiale): riepilogo `s` calcolato solo su quei record; un ufficiale più avanti spedisce i mancanti in whisper (§4). Da M8 anche `m`, il riepilogo per gruppo degli insiemi degli strumenti per ufficiali ([SPEC-12 §1.5](SPEC-12-officer-tools.md#15-sincronizzazione-tra-ufficiali)); un client precedente lo ignora | `OFFICER` |
| `VOTE` | voto per un like: `g` = GUID del destinatario, `n` = numero del voto ([SPEC-07 §2.2](SPEC-07-reputation-social.md#22-voti-e-libro-datalikeslua-m42)) | `WHISPER` al notaio |
| `LEDGER` | ricevuta del notaio: `g`, `n`, `r` = esito, `e` = la voce nuova del libro (le voci arrivano a tutti come `REC` dell'insieme `likes`, su `GUILD`) | `WHISPER` al votante |
| `GAPP` | da M9.6: candidatura a un annuncio di gruppo e risposta del capo, `g` = id dell'annuncio, `k` = `apply`, `cancel`, `accept`, `decline`, `full` ([SPEC-13 §6.5](SPEC-13-action-center-notices.md#65-candidature-il-messaggio-gapp)) | `WHISPER` tra candidato e capo |
| `GASK` | da M9.6: chiede gli annunci di gruppo aperti, `h` = impronte di quelli già noti; ogni capo risponde con il proprio `REC` in whisper ([SPEC-13 §6.7](SPEC-13-action-center-notices.md#67-chi-arriva-dopo-il-messaggio-gask)) | `GUILD` |
| `RASK` | da M10.9: chiede i raduni aperti, `h` = impronte di ciò che si ha, `a` = anche le risposte; ognuno risponde in whisper con il proprio `REC` ([SPEC-14 §9](SPEC-14-calendar-raids-season.md#9-raduni-pvp-e-nel-mondo-m109)); al più due ogni 10 minuti | `GUILD` |
| `SALT` | segreto di gilda per gli pseudonimi: `k = "q"` (domanda, `f` = impronte dei salt che si hanno) o `k = "s"` (`s` = lista di `{b = salt in Base64, at = creazione}`) | `OFFICER`; anche `WHISPER` tra ufficiali finché S5 non è provato |

## 3. Insiemi di dati

`accounts`, `contacts`, `recipes`, `coplay`, `likes`, `bank`, `bankreq`, `guildcfg` (da M10.2), e da M8 gli insiemi solo per ufficiali `timeline`, `absence`, `onotes`, `ocfg` ([SPEC-12 §1.2](SPEC-12-officer-tools.md#12-insiemi-solo-per-ufficiali)), e da M9 `groups` (annunci di gruppo: **volatile**, fuori da ogni riepilogo e solo di prima mano, [SPEC-13 §6.2](SPEC-13-action-center-notices.md#62-linsieme-groups)) e `addons` (censimento degli addon, [SPEC-13 §8.2](SPEC-13-action-center-notices.md#82-linsieme-addons)), e da M10 `season`, `raidev`, `avail` e `rally` (volatile) ([SPEC-14](SPEC-14-calendar-raids-season.md), dietro l'interruttore `season`), e da M11 `handbook` (le pagine del manuale, con un riepilogo a parte nei campi `hb` di `HELLO` e `DIGEST` e `hbb` di `BHELLO`, e senza invio in whisper: chi è indietro chiede e la risposta va su `GUILD`, [SPEC-15 §3.6](SPEC-15-guild-handbook-loot.md#36-sincronizzazione), dietro l'interruttore `raid`), e da M12 `trials` (le prove, solo per ufficiali come gli insiemi di M8) e `mentor` (le offerte dei mentori) ([SPEC-16](SPEC-16-recruitment-trials-mentors.md), dietro l'interruttore `recruit`), e da M13 `orders` (gli ordini di crafting: un record del compratore e uno dell'artigiano), `wish` (le liste dei desideri), `board` (la bacheca compro/vendo) e `goals` (gli obiettivi di gilda), con un riepilogo a parte loro (`ec`, `ecb`) ([SPEC-17](SPEC-17-guild-economy.md), dietro l'interruttore `econ`). Ogni record ha `id`, `author`, `rev` (contatore crescente dell'autore) e `time` (ora del server). Vince la `rev` più alta per `id`.

## 4. Sincronizzazione

Le regole di fiducia (§6) dicono **chi** può passare un record: l'account del suo autore o un ufficiale. Per questo la sincronizzazione lavora **per autore** (`Net/Sync.lua`).

- **Riepilogo**: per ogni autore di cui il client ha record, 11 byte: chiave (hash a 32 bit del GUID), digest (24 bit di un hash dei suoi record: insieme, id, `rev`, `time`) e l'ora del record più recente. L'hash dei digest è veloce e non crittografico (una collisione può solo ritardare la sincronizzazione).

1. All'accesso, dopo 10–30 s casuali, poi ogni 15–20 minuti: `HELLO` su `GUILD` con il riepilogo.
2. **Invio**: chi riceve un `HELLO` ed è **più avanti** del mittente per un autore che può consegnare gli manda quei record in whisper (`REC`) dopo 0,5–3 s casuali: gli autori del proprio account sempre; un ufficiale anche gli autori il cui account non ha nessuno online (secondo il roster) e i record del mittente stesso che il mittente non ha più (computer nuovo, file cancellato), ma solo l'ufficiale **designato** per quel mittente (il più piccolo hash di GUID dell'ufficiale e GUID del mittente tra gli ufficiali sentiti di recente): un solo ufficiale risponde (NET-04).
3. **Richiesta**: chi vede un `HELLO` di qualcuno più avanti di lui per un autore che quello può consegnare (lo stesso autore, il suo account o un ufficiale) chiede quell'autore con `REQ` in whisper dopo 1–5 s casuali, salvo che i record siano arrivati nel frattempo. La risposta va su `GUILD` con una chiave di coda per autore e insieme: la stessa richiesta da più client parte una volta sola e tutti quelli rimasti indietro si aggiornano (NET-04).
4. Ogni modifica locale esce come `REC` su `GUILD`, accumulata per 5 s. I **record solo per ufficiali** (`Store.IsRestricted`: oggi le foto della banca lette da un ufficiale) escono invece su `OFFICER`, mai su `GUILD`, e non entrano in nessun riepilogo `HELLO` né in nessuna risposta su `GUILD` o `WHISPER` a un membro; gli ufficiali se li scambiano con `OHELLO` (su `OFFICER`, al massimo uno ogni 5 minuti, insieme al `HELLO`) e con l'invio in whisper di §4.2 (solo l'ufficiale designato, o l'account dell'autore). Senza messaggi addon su `OFFICER` (S5) restano a chi li ha letti: nessun ripiego su `GUILD` o `WHISPER`.
5. Limiti: al massimo un `HELLO` ogni 5 minuti per client; un `REC` porta al massimo circa 2,5 KB di record (stima), i più grandi si dividono.
6. Un client che ha perso i propri dati se li riprende così dagli altri, e la sua prossima scrittura riparte dalla `rev` giusta.
7. **Richiesta su misura** (`Sync:RequestSet(insieme, autore)`, per esempio le ricette di un membro quando una vista le apre e non ci sono): un `REQ` con `s` = il nome dell'insieme e la chiave dell'autore, in `WHISPER` a un solo destinatario che può consegnare: l'account dell'autore se è online, altrimenti fino a **due ufficiali** sentiti di recente (scelti per hash, sempre gli stessi). La risposta è un `REC` in `WHISPER` solo al richiedente, con i soli record di quell'insieme (non va su `GUILD`: serve a uno solo). Limiti: la stessa richiesta (insieme e autore) al massimo ogni 5 minuti; chi risponde ne accetta al massimo 20 al minuto per mittente. Se nessuno che possa consegnare è online non si manda nulla e non si ricorda nulla: la prossima chiamata riprova. Chi risponde segue le stesse regole di §4.2: l'account dell'autore o un ufficiale.

**Budget di traffico** (provato dal simulatore, `Tests/test_sync_sim.lua`: 50 client, 5 ufficiali, metà offline all'inizio, 45 minuti di accessi, uscite, scritture e lockdown casuali, 1% di messaggi persi, latenza 0,05–0,5 s):

| Situazione | Limite | Misurato |
|---|---|---|
| Accessi e uscite continui, media per client | ≤ 450 B/min (era 400: alzato in M9.10 con il censimento acceso, [SPEC-10 R14](SPEC-10-risks-open-questions.md)) | circa 405 B/min con il seme del test (circa 310 senza censimento) |
| Accessi e uscite continui, client più carico | ≤ 2 KB/min (era 1,5: alzato in M7.7, [SPEC-10 R10](SPEC-10-risks-open-questions.md)) | circa 1,8 KB/min con il seme del test; da M9 un altro seme arriva a 2,1 KB/min (R14) |
| Costo di un accesso (tutto il traffico che provoca, per tutta la gilda) | ≤ 8 KB | circa 5 KB |
| Tempo per convergere dopo l'ultimo accesso | ≤ 5 minuti di norma; ≤ 25 minuti (un periodo di `HELLO`) se un messaggio va perso: la riparazione aspetta il `HELLO` successivo di chi ha il record | da circa 30 secondi a circa 15 minuti, secondo i messaggi persi (con 1% di perdita) |
| Tutti online e allineati, media per client | ≤ 100 B/min | circa 80 B/min |
| Tutti online e allineati, client più carico | ≤ 200 B/min | circa 110 B/min |

**Riepilogo a parte** (da M9.9, [SPEC-13 §8.7](SPEC-13-action-center-notices.md#87-come-è-fatto-m99)): i record dell'insieme `addons` non entrano nel riepilogo per autore ma in una voce propria per autore (chiave di `"+" .. GUID`), mandata in `c` del `HELLO`, in `cb` del `BHELLO` (12 blocchi) e in `c` del `DIGEST`; invio, richiesta e ritrasmissione sono gli stessi (§4.2, §4.3). Un client che non manda quei campi (la `v0.8.0`) vede riepiloghi identici a prima e non riceve nulla del censimento oltre ai `REC` su `GUILD`, che ignora. Costo: 11 byte in più nel `HELLO` per ogni autore che condivide. Misurato nel simulatore (50 client, 5 ufficiali, 60–110 addon ciascuno, 1% di messaggi persi, `Tests/test_addons_census.lua`): con accessi, uscite ed elenchi che cambiano il traffico medio è di circa 82 B/min per client (il più carico circa 540), tutti allineati circa 44 B/min (il più carico circa 60), dentro i limiti qui sopra; il primo scambio degli elenchi, a gilda nuova, costa circa 140 KB in tutto. Un `BHELLO` di 1000 autori con entrambi i riepiloghi pesa 477 B. Da M12.5 (`recruit` acceso) nello stesso riepilogo a parte stanno anche le offerte dell'insieme `mentor` ([SPEC-16 §6.1](SPEC-16-recruitment-trials-mentors.md#61-linsieme-mentor)).

**Riepilogo del catalogo delle ricette** (2026-11-27, [SPEC-06 §1.5](SPEC-06-professions-recipes.md#15-il-catalogo-delle-ricette-della-gilda-datarecipecataloguelua-2026-11-27)): l'insieme `recipecat` ha un quarto tipo di voci per autore (chiave di `"%" .. GUID`), in `rc` del `HELLO` (mandato anche vuoto, così chi conosce l'insieme si distingue da chi no), in `rcb` del `BHELLO` (1 blocco) e in `rc` del `DIGEST`; invio e richiesta come per il censimento. Non può stare in `c`: un client dalla `v0.9.0` alla `v0.11.0` calcola `c` con il solo censimento, e un `c` con il catalogo dentro non sarebbe mai uguale al suo (i due client si rimanderebbero record per sempre). Regola: un insieme che un client già rilasciato non conosce non entra mai in un tipo di riepilogo esistente.

**Riepilogo dell'economia** (da M13, [SPEC-17 §10.2](SPEC-17-guild-economy.md#102-il-riepilogo-ec)): i quattro insiemi di M13 (`orders`, `wish`, `board`, `goals`), che nessun client fino alla `v0.12.0` conosce, hanno un quinto tipo di voci per autore (chiave di `"$" .. GUID`), in `ec` del `HELLO` e del `DIGEST` e in `ecb` del `BHELLO` (1 blocco), mandato solo con l'interruttore `econ` acceso (anche vuoto); invio e richiesta come per il catalogo. Un insieme che arriverà dopo (le aste di M13.7) avrà un tipo suo.

Il riepilogo cresce di 11 byte per autore: con 200 membri con l'addon un `HELLO` pesa circa 3 KB (12 pezzi da 255 byte), ogni 15–20 minuti; per gilde molto più grandi serve un riepilogo a blocchi: oltre 200 autori un `BHELLO` di 96 blocchi, con la risposta `DIGEST` solo dell'ufficiale designato e dell'account del mittente, provato con 1000 accessi insieme in M7.7 ([SPEC-11 §6](SPEC-11-data-trust.md#6-limiti-contro-i-client-malevoli-e-le-gilde-grandi-m77)).

## 5. Coda e lockdown

La coda di `Transport` rispetta ChatThrottleLib e un intervallo minimo per distribuzione (`GUILD` e `OFFICER` 1 s, `WHISPER` 0,25 s, da rivedere con S5); durante `C_ChatInfo.InChatMessagingLockdown()` o con le restrizioni attive i messaggi aspettano e partono dopo (NET-05). Nulla si perde finché il client resta acceso; alla disconnessione la coda si salva (`AzerothAccordCharDB.outbox`) e riparte al prossimo accesso.

- Priorità: `ALERT` (risposte e voti: `DIGEST`, `REQ`, `VOTE`, `LEDGER`, `SALT`), `NORMAL` (`HELLO`, `REC`), `BULK`; un messaggio `BULK` che aspetta più di 10 minuti si scarta. Con una `key` resta solo l'ultimo messaggio della stessa chiave.
- `HELLO`: al massimo uno ogni 5 minuti anche a livello di coda (NET-04).
- Un rifiuto per limite di velocità si riprova dopo 5 s, al massimo 3 volte; un rifiuto per lockdown del client è un'attesa, non un tentativo.
- Ogni messaggio porta la chiave della gilda per cui è stato scritto: aspetta finché la gilda non è nota e si scarta se nel frattempo il personaggio è in un'altra gilda. Un messaggio salvato si scarta anche se la sua durata è scaduta a gioco chiuso o se è più vecchio di un giorno.
- Il client rimanda a chi scrive i suoi messaggi `GUILD` e `OFFICER`: l'eco si scarta; un'eco `OFFICER` (o un messaggio `OFFICER` di un altro) prova che il canale degli ufficiali porta i messaggi degli addon (capacità `officerAddonChannel`, S5).

## 6. Fiducia e integrità

Regole di [ADR 0005](../adr/0005-trust-first-hand-records-and-officer-relays.md):

- **Prima mano** (NET-10): un record si accetta se il mittente è l'autore o un personaggio dello stesso account dell'autore. "Stesso account" vale solo con l'**elenco reciproco**: ogni personaggio pubblica il proprio record `accounts` (id = il suo GUID) con l'elenco dei personaggi dell'account, e A e B sono dello stesso account solo se il record di A elenca B e quello di B elenca A. Il token dell'account è pubblico e non prova nulla: chi copia il token o elenca un personaggio altrui non diventa il suo account, perché quel personaggio non lo elenca.
- **Ritrasmesso** (NET-11): un record di un altro autore si accetta solo se il mittente è ufficiale secondo il roster di chi riceve.
- **Autorità** (NET-12): libro dei like, stato delle richieste in banca e schede riservate si accettano solo da ufficiali. Per il libro dei like basta che il **mittente** sia ufficiale: una voce resta valida anche se il suo notaio non lo è più (LIKE-07). Il libro è **solo aggiunte**: una voce ha `rev` 1, un id ricavato dal contenuto, e non si sostituisce mai.
- **Solo ufficiali** (BANK-02): un client che non è di un ufficiale rifiuta un record `restricted` da chiunque lo spedisca (motivo `restricted`); un ufficiale lo accetta solo se mittente e autore sono ufficiali (NET-12).
- **Osservazioni** (NET-13): il co-play si accetta solo da un osservatore presente nel gruppo osservato; si unisce con il massimo.
- Il nome del mittente arriva dal server e non si può falsificare; i contenuti sì, per questo valgono le regole sopra. Il mittente deve essere nel roster di chi riceve (nome con o senza reame); il suo GUID e il suo grado vengono dal roster, mai dal messaggio.
- **Regole del proprietario**: oltre alla fiducia, ogni insieme dice cosa un autore può scrivere: solo il proprio record `accounts`; `contacts` e `recipes` solo di un personaggio del proprio account; `bankreq` aperte o annullate dal richiedente (o da un suo alt) con un id che comincia con il suo GUID, decise solo da ufficiali, con il contenuto che non cambia e lo stato più alto che vince ([SPEC-03 §7](SPEC-03-data-model.md#7-richieste-in-banca-bankreq)); schede riservate di `bank` solo da ufficiali; `guildcfg` solo da ufficiali (NET-12, anche dopo che l'autore ha lasciato il grado) e solo con scelte valide ([SPEC-03 §8](SPEC-03-data-model.md#8-impostazioni-della-gilda-guildcfg)). Un client di una versione precedente ignora un insieme che non conosce.
- **Forma**: `id` (massimo 64 caratteri), `author` (un GUID di giocatore), `rev` intero da 1, `time` non oltre un'ora nel futuro, dimensione massima per insieme. A parità di `rev` vince il `time` più recente, poi il GUID dell'autore maggiore: ogni client tiene la stessa versione.
- **Conservazione**: co-play 90 giorni, registri della banca 365, richieste chiuse e cancellazioni 60, cronologia del roster 365 (dal giorno del record), assenze 30 dopo il rientro, note estese cancellate 60 ([SPEC-12](SPEC-12-officer-tools.md)); un record che scadrebbe subito si rifiuta.
