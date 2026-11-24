# SPEC-03: Modello dati

Tutti i record hanno `id`, `author` (GUID del personaggio che scrive), `rev`, `time` ([SPEC-02 §3](SPEC-02-network-protocol.md#3-insiemi-di-dati)). I dati vivono in `AzerothAccordDB.guilds[<reame>/<gilda>]`.

## 1. Account e personaggi (`accounts`)

Un record **per personaggio**: `id` = GUID del personaggio, scritto solo da lui (o ripassato da un suo alt già provato, o da un ufficiale).

| Campo | Tipo | Note |
|---|---|---|
| `token` | stringa casuale di 16 byte (Base64) | creato una volta per account, mai cambiato |
| `chars` | lista di `{guid, name, realm, classID, level, inGuild}` | tutti i personaggi dell'account entrati con l'addon su questo reame (e quelli visti nella stessa gilda su un altro), al massimo 40; `inGuild` dice se sono nel roster |
| `main` | GUID | scelto dal giocatore; predefinito: livello più alto, poi il personaggio aggiunto per primo |
| `addonVersion` | stringa | per la diagnostica |

Autore valido: il personaggio stesso (`id` = `author`), che deve comparire in `chars`. Due personaggi sono dello **stesso account** solo se il record di ciascuno elenca l'altro (elenco reciproco, [SPEC-02 §6](SPEC-02-network-protocol.md#6-fiducia-e-integrità)): il `token` viaggia in chiaro e si potrebbe copiare, quindi serve solo a raggruppare, mai a provare.

## 2. Contatti (`contacts`)

Un record per personaggio (`id` = GUID), scritto da lui o da un suo alt; i contatti di un account sono il record più recente tra i suoi personaggi.

| Campo | Tipo | Note |
|---|---|---|
| `account` | token | |
| `battleTag` | stringa | da `BNet_GetBattleTagSelf()` **[verificare]** S8 |
| `discord` | stringa | scritto dal giocatore nelle impostazioni (massimo 32 caratteri, solo nome utente, niente link); il `discordInfo` nativo **[verificare]** S2 lo legge chi mostra i contatti, per ogni membro, e vince sul valore condiviso |

## 3. Ricette (`recipes`)

Un record per personaggio e professione: `id` = `<GUID>:<skillLine>` (un `id` diverso si rifiuta), scritto dal personaggio o da un suo alt.

| Campo | Tipo | Note |
|---|---|---|
| `char` | GUID | |
| `skillLine` | numero | ID della professione (quello del roster: il giocatore ha la sua professione con lo stesso id) |
| `name` | stringa | nome della professione, per mostrarla anche senza i dati nativi |
| `rank`, `maxRank` | numeri | |
| `ids` | testo | spellID delle ricette conosciute, ordinati, codificati a differenze (varint a 7 bit, bit alto = altro byte) e poi in Base64: testo ASCII, sicuro in SavedVariables e nei messaggi; circa 1,5 byte per ricetta prima del Base64 |
| `n` | numero | quante ricette ci sono in `ids` |
| `h` | numero | impronta a 32 bit di professione, grado e `ids`: cambia quando cambia la lista o il grado (PRO-06) |

La **fonte** non è un campo: i record di questo insieme sono sempre condivisi (di un addon); le liste native non si salvano mai ([ADR 0010](../adr/0010-native-data-first-shared-data-as-fallback.md)). Il lettore non si fida del testo: `Recipes.Decode` rifiuta Base64 non valido, numeri tagliati, differenze nulle, id fuori campo e più di 3000 ricette.

## 4. Gioco di gruppo (`coplay`)

| Campo | Tipo | Note |
|---|---|---|
| `day` | numero `AAAAMMGG` (calendario del reame) | |
| `pairs` | mappa `"<guidA>:<guidB>" → minuti` (GUID ordinati) | personaggi, non account: l'unione in account si fa al calcolo |
| `observer` | GUID | deve comparire in almeno una coppia ([SPEC-02 §6](SPEC-02-network-protocol.md#6-fiducia-e-integrità)) |

Id del record: `<GUID osservatore>:<giorno>:<n>`; un giorno con più di 100 coppie si divide in pezzi (n = 1, 2, ...), ciascuno con almeno una coppia dell'osservatore.

## 5. Like (`likes`)

| Elemento | Campi | Chi lo scrive |
|---|---|---|
| Voce del libro | `{pseudonym (32 cifre esadecimali), tag (16), target (GUID), day}`; il notaio è l'autore del record; id = `<16 cifre dello pseudonimo>:<target>`, `rev` sempre 1 ([SPEC-07 §2.2](SPEC-07-reputation-social.md#22-voti-e-libro-datalikeslua-m42)) | solo ufficiali; mai cambiata né cancellata |
| Coda e voti dati (locale) | `GuildKey:Data().likes = { queue = { [GUID] = {at, n} }, given = { [GUID] = time } }` | solo sul computer del votante, mai condivisi |
| Segreto di gilda | `salt` (32 byte, in Base64), con la data di creazione | primo ufficiale o GM; solo su `OFFICER` (whisper tra ufficiali finché S5 non è provato), mai salvato dai membri; nei client degli ufficiali `GuildKey:Data().salts` = `{ [impronta] = { k, at } }`, al massimo 8 ([SPEC-07 §2.1](SPEC-07-reputation-social.md#21-il-segreto-e-il-notaio-datanotarylua-m41)) |

Totale di un account = numero di `pseudonym` distinti nelle voci il cui `target` è uno dei suoi personaggi ([ADR 0007](../adr/0007-likes-one-per-account-irreversible-anonymous.md)).

## 6. Banca (`bank`)

Ogni record appartiene a chi l'ha scritto (l'id comincia con il suo GUID: nessuno scrive la foto di un altro). Più autori possono avere una foto della stessa scheda: in vista vince la più recente ([SPEC-08 §5](SPEC-08-guild-bank.md#5-cattura-databanklua-m51)).

| Elemento | Id | Campi |
|---|---|---|
| Foto di una scheda | `<GUID>:t<scheda>` | `kind = "tab"`, `tab` (1-8), `name`, `icon`, `rank` (grado di chi l'ha letta), `restricted` (solo ufficiali), `it` (oggetti `slot.itemID.quantità[.variante]`, al massimo 98, separati da virgole), `n`, `h` |
| Denaro | `<GUID>:money` | `kind = "money"`, `money` (rame) |
| Registro | `<GUID>:log:<scheda>` | `kind = "log"`, `tab` (0 = denaro, 1-8), `rank`, `restricted` (solo schede oggetti), `e` (voci `tipo,nome,oggetto,quantità,ora` separate da `;`, al massimo 150), `n`, `h` ([SPEC-08 §8](SPEC-08-guild-bank.md)) |

Conservazione: foto e denaro 90 giorni, registri 365 ([SPEC-02 §6](SPEC-02-network-protocol.md#6-fiducia-e-integrità)).

## 7. Richieste in banca (`bankreq`)

Id `<GUID del richiedente>:<n>` (n conta le richieste di quel personaggio); l'autore è il richiedente, o l'ufficiale che ha deciso l'ultimo passaggio.

| Campo | Tipo | Note |
|---|---|---|
| `kind` | `withdraw` / `deposit` / `donation` | prelievo, deposito (oggetto che si offre), donazione (promessa) |
| `requester` | GUID | chi ha aperto la richiesta |
| `itemID`, `count` **oppure** `amount` | numeri | oggetto e quantità (1-9999), o oro in rame (fino a 100 000 oro); un deposito vuole un oggetto |
| `reason` | testo, massimo 120 caratteri | senza caratteri di controllo né `|` |
| `status` | `open` → `approved` / `rejected` → `fulfilled`; `cancelled` dall'autore | solo `open` e `cancelled` dal richiedente (o da un suo alt, stesso account); `approved`, `rejected`, `fulfilled` solo da ufficiali |
| `note` | testo, massimo 120 caratteri | il motivo di un rifiuto |
| `history` | lista di `{s = stato, by = GUID, t = ora}`, al massimo 8 | dalla più vecchia; la prima voce (l'apertura) resta |
| `created` | ora del server | |

Passaggi ammessi: `open` → `approved`, `rejected`, `fulfilled`, `cancelled`; `approved` → `fulfilled`, `rejected`; gli stati chiusi non si muovono. **Versione da tenere**: vince lo stato più alto (`open` < `cancelled` < `approved` < `rejected` < `fulfilled`), poi la `rev`, il `time` e l'autore: una decisione scritta nello stesso momento di un annullamento vince su tutti i client, così convergono. Il **contenuto** (richiedente, tipo, oggetto, quantità, importo, creazione) non può cambiare dopo l'apertura. Un richiedente può avere al massimo 5 richieste aperte. Le richieste chiuse si cancellano dopo 60 giorni. Tutta la gilda vede tutte le richieste.

## 8. Impostazioni della gilda (`guildcfg`)

Da M10.2 ([ADR 0022](../adr/0022-integrations-with-raid-and-loot-addons.md)). Scelte della gilda fatte dagli ufficiali e uguali per tutti. Oggi un solo record, id `sources`: la **fonte** di ogni dato, cioè l'addon che lo possiede per tutta la gilda (una fonte per dato).

| Campo | Valori | Note |
|---|---|---|
| `raid` | `accord` / `fdcp` | roster della season (MS1, MS2, OS), formazione e panchina; predefinito `accord` |
| `loot` | `none` / `fdcp` | crediti e posto in coda di un membro, riassunto delle regole del loot; predefinito `none` (Accord non ha un motore del loot) |

Lo scrivono solo ufficiali e Guild Master; si accetta solo se il mittente è un ufficiale (NET-12); l'autore può aver perso il grado dopo (`authorAny`). Un record con un id diverso da `sources` o con un valore sconosciuto si rifiuta (`owner`). Senza record valgono i predefiniti. Nessuna scadenza: vale finché un ufficiale non lo cambia.
