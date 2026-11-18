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
| `discord` | stringa | `discordInfo` nativo se c'è **[verificare]** S2, altrimenti scritto dal giocatore (massimo 32 caratteri, solo nome utente, niente link) |

## 3. Ricette (`recipes`)

| Campo | Tipo | Note |
|---|---|---|
| `char` | GUID | |
| `skillLine` | numero | ID della professione |
| `rank`, `maxRank` | numeri | |
| `ids` | lista ordinata di spellID delle ricette | codificata a differenze (varint) prima del CBOR |
| `source` | `native` / `shared` | [ADR 0010](../adr/0010-native-data-first-shared-data-as-fallback.md) |

## 4. Gioco di gruppo (`coplay`)

| Campo | Tipo | Note |
|---|---|---|
| `day` | `AAAAMMGG` (ora del server) | |
| `pairs` | mappa `"<guidA>:<guidB>" → minuti` (GUID ordinati) | personaggi, non account: l'unione in account si fa al calcolo |
| `observer` | GUID | deve comparire in almeno una coppia ([SPEC-02 §6](SPEC-02-network-protocol.md#6-fiducia-e-integrità)) |

## 5. Like (`likes`)

| Elemento | Campi | Chi lo scrive |
|---|---|---|
| Voce del libro | `{pseudonym, target (GUID), day, notary}` | solo ufficiali |
| Segreto di gilda | `salt` (32 byte) | primo ufficiale o GM; solo su `OFFICER`, mai salvato dai membri |

Totale di un account = numero di `pseudonym` distinti nelle voci il cui `target` è uno dei suoi personaggi ([ADR 0007](../adr/0007-likes-one-per-account-irreversible-anonymous.md)).

## 6. Banca (`bank`)

| Elemento | Campi |
|---|---|
| Foto di una scheda | `{tab, name, icon, viewRanks, items: [{slot, itemID, link, count}], time, author}` |
| Denaro | `{money, time, author}` |
| Voce di registro | `{kind (deposit, withdraw, move, repair, buyTab…), name, itemID?, count?, amount?, hourBucket}` |

## 7. Richieste in banca (`bankreq`)

| Campo | Tipo | Note |
|---|---|---|
| `kind` | `withdraw` / `deposit` / `donation` | |
| `itemID`, `count` o `amount` | | oggetto o denaro |
| `reason` | testo, massimo 120 caratteri | |
| `status` | `open` → `approved` / `rejected` → `fulfilled`; `cancelled` dall'autore | i passaggi oltre `open` solo da ufficiali |
| `history` | lista di `{status, by, time}` | |

Le richieste chiuse si cancellano dopo 60 giorni.
