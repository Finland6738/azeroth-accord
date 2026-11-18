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
| `HELLO` | versione dell'addon, digest per insieme di dati | `GUILD` |
| `DIGEST` | risposta a `HELLO` con i propri digest | `WHISPER` |
| `REQ` | richiesta di record (insieme, autori, intervalli) | `WHISPER` |
| `REC` | uno o più record | `GUILD` o `WHISPER` |
| `VOTE` | voto per un like | `WHISPER` al notaio |
| `LEDGER` | voci del libro dei like | `GUILD` |
| `SALT` | segreto di gilda per gli pseudonimi | `OFFICER` |

## 3. Insiemi di dati

`accounts`, `contacts`, `recipes`, `coplay`, `likes`, `bank`, `bankreq`. Ogni record ha `id`, `author`, `rev` (contatore crescente dell'autore) e `time` (ora del server). Vince la `rev` più alta per `id`.

## 4. Sincronizzazione

1. All'accesso, dopo 10–30 s casuali: `HELLO` con un digest (hash troncato) per insieme di dati.
2. Chi ha digest diversi risponde con `DIGEST` in whisper; il nuovo arrivato chiede le differenze con `REQ`.
3. Ogni modifica locale esce subito come `REC` su `GUILD` (accumulata per 5 s).
4. Limiti: al massimo un `HELLO` ogni 5 minuti per client; risposte con attesa casuale e annullate se un altro ha già risposto (NET-04).

## 5. Coda e lockdown

La coda di `Transport` rispetta ChatThrottleLib e un intervallo minimo per distribuzione (`GUILD` e `OFFICER` 1 s, `WHISPER` 0,25 s, da rivedere con S5); durante `C_ChatInfo.InChatMessagingLockdown()` o con le restrizioni attive i messaggi aspettano e partono dopo (NET-05). Nulla si perde finché il client resta acceso; alla disconnessione la coda si salva (`AzerothAccordCharDB.outbox`) e riparte al prossimo accesso.

- Priorità: `ALERT` (risposte e voti: `DIGEST`, `REQ`, `VOTE`, `SALT`), `NORMAL` (`HELLO`, `REC`, `LEDGER`), `BULK`; un messaggio `BULK` che aspetta più di 10 minuti si scarta. Con una `key` resta solo l'ultimo messaggio della stessa chiave.
- `HELLO`: al massimo uno ogni 5 minuti anche a livello di coda (NET-04).
- Un rifiuto per limite di velocità si riprova dopo 5 s, al massimo 3 volte; un rifiuto per lockdown del client è un'attesa, non un tentativo.
- Ogni messaggio porta la chiave della gilda per cui è stato scritto: aspetta finché la gilda non è nota e si scarta se nel frattempo il personaggio è in un'altra gilda. Un messaggio salvato si scarta anche se la sua durata è scaduta a gioco chiuso o se è più vecchio di un giorno.
- Il client rimanda a chi scrive i suoi messaggi `GUILD` e `OFFICER`: l'eco si scarta; un'eco `OFFICER` (o un messaggio `OFFICER` di un altro) prova che il canale degli ufficiali porta i messaggi degli addon (capacità `officerAddonChannel`, S5).

## 6. Fiducia e integrità

Regole di [ADR 0005](../adr/0005-trust-first-hand-records-and-officer-relays.md):

- **Prima mano** (NET-10): un record si accetta se il mittente è l'autore o un personaggio dello stesso account dell'autore.
- **Ritrasmesso** (NET-11): un record di un altro autore si accetta solo se il mittente è ufficiale secondo il roster di chi riceve.
- **Autorità** (NET-12): libro dei like, stato delle richieste in banca e schede riservate si accettano solo da ufficiali.
- **Osservazioni** (NET-13): il co-play si accetta solo da un osservatore presente nel gruppo osservato; si unisce con il massimo.
- Il nome del mittente arriva dal server e non si può falsificare; i contenuti sì, per questo valgono le regole sopra.
