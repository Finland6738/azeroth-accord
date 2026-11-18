# SPEC-02: Protocollo di rete

## 1. Canali

| Distribuzione | Uso | Note |
|---|---|---|
| `GUILD` | dati per tutti i membri | il server consegna solo ai membri online |
| `OFFICER` | dati riservati (segreto dei like, schede riservate della banca) | **[verificare]** S5: se non funziona per gli addon, quei dati non viaggiano |
| `WHISPER` | voto al notaio, richieste puntuali di dati | solo tra compagni di gilda |

Prefisso unico `AzAccord` ([ADR 0004](../adr/0004-guild-addon-channels-and-versioned-protocol.md)).

## 2. Formato

`<versione>|<tipo>|<payload>`: `versione` = `1`; `payload` = CBOR compresso in Base64 (`Codec`). Messaggi lunghi divisi da AceComm. Tipi sconosciuti o versioni maggiori: ignorati (NET-01).

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

La coda di `Transport` rispetta ChatThrottleLib e un intervallo minimo per distribuzione; durante `C_ChatInfo.InChatMessagingLockdown()` o con le restrizioni attive i messaggi aspettano e partono dopo (NET-05). Nulla si perde finché il client resta acceso; alla disconnessione la coda si salva e riparte al prossimo accesso.

## 6. Fiducia e integrità

Regole di [ADR 0005](../adr/0005-trust-first-hand-records-and-officer-relays.md):

- **Prima mano** (NET-10): un record si accetta se il mittente è l'autore o un personaggio dello stesso account dell'autore.
- **Ritrasmesso** (NET-11): un record di un altro autore si accetta solo se il mittente è ufficiale secondo il roster di chi riceve.
- **Autorità** (NET-12): libro dei like, stato delle richieste in banca e schede riservate si accettano solo da ufficiali.
- **Osservazioni** (NET-13): il co-play si accetta solo da un osservatore presente nel gruppo osservato; si unisce con il massimo.
- Il nome del mittente arriva dal server e non si può falsificare; i contenuti sì, per questo valgono le regole sopra.
