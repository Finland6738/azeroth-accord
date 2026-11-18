# SPEC-01: Piattaforma e architettura

## 1. Client

- WoW Forever `1.60.1`, `## Interface: 16001`, motore 12.0: finestra Gilda `CommunitiesFrame`, `C_Club`, `C_EncodingUtil`, restrizioni degli addon e chat lockdown ([ADR 0002](../adr/0002-wow-forever-target-and-api-dump.md)).
- Riferimento delle API: il dump di `WoW-Addons` (`../WoW-Addons/docs/api.json`), consultato e mai copiato.
- Lua 5.1, librerie Ace3 incorporate ([ADR 0011](../adr/0011-embedded-ace3-savedvariables-and-schema-versions.md)).

## 2. Architettura

Solo addon, dati solo dentro la gilda ([ADR 0001](../adr/0001-client-only-addon-guild-only-data.md)). Ogni client:

1. legge dal gioco ciò che può (roster, `C_Club`, professioni, gruppo, banca quando è aperta);
2. pubblica alla gilda i propri dati di prima mano (personaggi, contatti, ricette, osservazioni del gioco di gruppo, foto della banca);
3. riceve e unisce i dati degli altri secondo le regole di fiducia ([SPEC-02 §6](SPEC-02-network-protocol.md#6-fiducia-e-integrità));
4. calcola in locale le viste derivate (totali dei like, indice sociale, gruppi).

## 3. Moduli

| Cartella | Modulo | Responsabilità |
|---|---|---|
| `Core/` | `Init` | oggetto AceAddon, controllo Forever, comandi |
| | `Compat` | unica porta verso le API del gioco: `pcall`, capacità, valori segreti ([ADR 0018](../adr/0018-reuse-azeroth-guild-finder-foundations.md)) |
| | `Config` | AceDB, schemi e migrazioni |
| | `Bus` | eventi interni tra moduli |
| | `Role` | membro, ufficiale, GM |
| | `Hash` | SHA-256 e HMAC in Lua puro (con `bit`) per gli pseudonimi dei like |
| | `Diagnostics` | `/accord debug` |
| `Data/` | `GuildKey` | chiave `<reame>/<gilda>` dei dati |
| | `Roster` | unione di `GetGuildRosterInfo` e `C_Club.GetMemberInfo` |
| | `Accounts` | token dell'account, personaggi, main, unione degli alt |
| | `Contacts` | BattleTag, Discord |
| | `Professions`, `Recipes` | adattatori nativo/condiviso ([ADR 0010](../adr/0010-native-data-first-shared-data-as-fallback.md)) |
| | `CoPlay` | registro dei minuti di gioco in gruppo |
| | `Likes` | libro mastro dei like, notaio |
| | `Social` | indice sociale, gruppi, suggerimenti |
| | `Bank`, `BankRequests` | foto, registri, donazioni, richieste |
| `Net/` | `Codec` | CBOR, compressione, Base64 attraverso Compat |
| | `Transport` | AceComm, coda, throttle, lockdown, `GUILD`/`OFFICER`/`WHISPER` |
| | `Store` | archivio di record versionati per insieme di dati |
| | `Sync` | riassunti (digest) e richieste delle differenze |
| `UI/` | `GuildTab` | tab nella `CommunitiesFrame` ([ADR 0003](../adr/0003-accord-tab-in-the-guild-window.md)) |
| | `Shell` | pannello, navigazione, finestra autonoma |
| | `*Model` / viste | modello separato dalla vista per ogni schermata, così i modelli si testano offline |

I moduli si parlano solo attraverso `Bus` e le interfacce pubbliche; nessun modulo chiama direttamente il gioco senza passare da `Compat`.

## 4. SavedVariables

| Variabile | Ambito | Contenuto |
|---|---|---|
| `AzerothAccordDB` | account | `schemaVersion`, `token` (token dell'account, 16 byte casuali in Base64, creato una volta), `chars[<reame>][<GUID>]` (personaggi per reame), `guilds[<chiave>]` (dati per gilda: roster arricchito, record ricevuti, libro dei like, co-play, banca, richieste), `settings` |
| `AzerothAccordCharDB` | personaggio | `schemaVersion`, `ui`: ultima vista, colonne, ordinamento, posizione e dimensione della finestra |

La chiave di gilda è `<reame>/<nome della gilda>`, con il reame della gilda (sui reami connessi) senza spazi, trattini o apostrofi; i dati di una gilda si raggiungono solo con `GuildKey:Data()`, così due gilde non si mescolano mai e i dati di una gilda lasciata restano intatti. Ogni variabile ha un `schemaVersion`: le migrazioni girano all'`ADDON_LOADED`, i valori non validi tornano al predefinito (e `/accord debug` lo dice), una versione più nuova di quella dell'addon apre i dati in sola lettura ([ADR 0011](../adr/0011-embedded-ace3-savedvariables-and-schema-versions.md)).

Limiti di crescita (MUST): co-play conservato 90 giorni; registri della banca 365 giorni; ricette solo come ID numerici. `/accord debug` mostra le dimensioni stimate delle due variabili e dei dati della gilda corrente, per tabella.

## 5. Compat e capacità

All'accesso `Compat:Probe()` riempie due tabelle:

- **API**: per ogni funzione del gioco usata, `available`, `missing`, `restricted` (valore segreto o restrizione attiva) o `error`;
- **funzioni** (capacità): `guildTab`, `clubProfessions`, `clubDiscord`, `guildRecipesNative`, `ownRecipes`, `officerAddonChannel`, `groupGUIDs`, `battleTag`, `bankLogs`, ognuna `available`, `missing` o `unknown` (l'API c'è ma nessun dato ha ancora mostrato se il server la riempie). I moduli le precisano quando lo scoprono (`Compat:SetFeature`, evento `FEATURE_CHANGED` sul Bus): la tab quando si aggancia, il roster quando arrivano i membri, il trasporto quando torna un messaggio `OFFICER`, la banca quando si apre.

Ogni funzione si adatta alla capacità; le API **[verificare]** degradano senza errori (mancanti, in errore o con valori segreti: provato nei test offline per ognuna). `/accord debug` mostra entrambe le tabelle, mai nomi di giocatori, gilde, BattleTag o Discord.
