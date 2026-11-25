# SPEC-11: Fiducia nei dati

Specifica della milestone M7 ([roadmap](../roadmap/M7-data-trust.md)): ogni valore dice da dove viene e quanto è vecchio, gli alt fuori dalla gilda mostrano la loro gilda, e arrivano la modalità demo, il backup personale, il pannello "cosa condivido" e i limiti contro i client malevoli e le gilde molto grandi. Ogni sezione dice il passo che la realizza; i passi M7.2–M7.7 non hanno scelte di progetto da fare oltre a queste.

Nomi di codice, campi e testi dell'interfaccia in inglese (con la traduzione italiana nel file di lingua `itIT.lua`, [ADR 0015](../adr/0015-interface-and-documentation-languages.md)).

## 1. Etichette di provenienza (M7.2)

### 1.1 Fonti

Ogni valore mostrato porta una **fonte** e, quando la fonte la conosce, l'ora in cui il valore è stato osservato (`observedAt`, ora del server in secondi). Le quattro fonti sono quelle che `Data/Roster.lua` già dà alle professioni ([SPEC-05 §1](SPEC-05-roster-alts-contacts.md#1-tabella-dei-membri)), più le note:

| Fonte | Significato | `observedAt` | Esempi |
|---|---|---|---|
| `native` | letto adesso da un'API del gioco ([ADR 0010](../adr/0010-native-data-first-shared-data-as-fallback.md)) | nessuno: il valore è attuale | roster, professioni e Discord del club, ricette native (lì `observedAt` = l'ora della risposta del server) |
| `shared` | da un record di un altro giocatore ricevuto dalla sincronizzazione | `time` del record (l'ora in cui il client dell'autore ha scritto quella versione) | professioni e ricette condivise, contatti, elenco degli alt, foto della banca, like |
| `own` | letto dal personaggio del giocatore, su questo computer | `time` del record proprio, oppure l'ora della lettura | le proprie professioni e ricette, i propri alt |
| `note` | dedotto dalla nota pubblica di un membro (ACC-05) | nessuno | "declared in the note" |

Regole:

- Il **valore nativo vince** sempre (ADR 0010): l'etichetta è quella della fonte che ha dato il valore mostrato, non di tutte quelle che lo conoscono.
- Un valore `shared` tiene anche l'**autore** del record (`author`, GUID). Il mittente che l'ha ripassato (un ufficiale, NET-11) non si salva e non si mostra.
- Un record `shared` si riscrive solo quando cambia (nessuna `rev` nuova per un record identico, [SPEC-05 §3](SPEC-05-roster-alts-contacts.md#3-personaggi-dello-stesso-account)): la sua età è quindi "da quanto il valore non cambia", non "da quanto nessuno lo controlla". I testi lo dicono così ("updated 40 d ago", "aggiornato 40 g fa").

### 1.2 L'età

`age = max(0, ServerTime() - observedAt)`: un `time` fino a un'ora nel futuro è ammesso dalla forma ([SPEC-02 §6](SPEC-02-network-protocol.md#6-fiducia-e-integrità)) e vale come età zero. Il testo riusa le chiavi `AGO_*` che già esistono e la stessa scala di `RosterModel.LastOnlineText`, spostata in una funzione unica `Provenance.AgeText(seconds)` che anche `Shell.Ago` usa:

| Età | Testo (inglese / italiano) |
|---|---|
| meno di 60 s | `just now` / `adesso` |
| meno di 1 h | `%d min ago` |
| meno di 24 h | `%d h ago` |
| meno di 60 giorni | `%d d ago` |
| meno di 730 giorni | `%d mo ago` (mesi di 30 giorni) |
| oltre | `%d y ago` |

### 1.3 Il widget

Un solo widget per tutte le viste: `Widgets.Provenance(parent)` con `SetSource(info)`, dove `info = { source, observedAt, author, set }` (gli ultimi due solo per `shared`). È un testo piccolo (`text-3`, dimensione `small` di [`ui-style.md`](ui-style.md)) accanto al valore, senza colori scritti nel file:

| Fonte | Etichetta | Tooltip (prima riga) |
|---|---|---|
| `native` | `game` / `gioco` | `From the game, read now.` |
| `shared` | l'età (`3 d ago`) | `Shared by <autore>, updated <età>.` |
| `own` | `you` / `tu` | `Read from your own character, <età>.` |
| `note` | `note` / `nota` | `Declared in <membro>'s public note. Accord cannot check it.` |

Il **nome dell'autore** nel tooltip è, nell'ordine: il nome nel roster (`Store:MemberByGUID`), il nome che l'autore dà a se stesso nel proprio record `accounts`, altrimenti `a former guild member` / `un ex membro della gilda`. Mai il GUID. Il nome passa per la stessa pulizia dei contatti (il carattere `|` raddoppiato, [SPEC-05 §4](SPEC-05-roster-alts-contacts.md#4-contatti)).

Dove compare (criterio di M7.2): celle delle professioni nella tabella del Roster (solo nel tooltip della cella, per non allargare la colonna), scheda del membro (ogni professione, ogni contatto, ogni alt, la versione dell'addon), intestazione dell'elenco ricette, totale dei like (fonte `shared`, età della voce più recente del libro che riguarda l'account) e foto della banca (per scheda, accanto al nome di chi l'ha letta).

### 1.4 Attenuazione dei valori condivisi vecchi

Un valore `shared` più vecchio della soglia del suo tipo si mostra **attenuato** (valore ed etichetta in `text-3`) e il tooltip aggiunge una seconda riga: `Not updated for <N> days: it may be out of date.` I valori `native`, `own` e `note` non si attenuano mai.

| Dato | Soglia | Perché |
|---|---|---|
| foto di una scheda della banca, denaro | **7 giorni** | la banca cambia ogni giorno; una richiesta fatta su una scorta di una settimana fa sbaglia spesso. Chi apre la banca riscrive la foto, quindi una gilda attiva non vede quasi mai l'attenuazione |
| professioni e ricette condivise | **60 giorni** | una lista di ricette cambia poco: si riscrive solo quando il membro apre la professione e qualcosa è cambiato (PRO-06). Due mesi sono più di una fase di livellamento e meno della conservazione del co-play (90 giorni): oltre, il membro probabilmente non usa più quella professione |
| altra gilda di un alt (§2) | **30 giorni** dal `seen` | la gilda è quella dell'ultimo accesso dell'alt: dopo un mese può essere cambiata senza che nessuno lo sappia |
| versione dell'addon (`addonVersion`) | **30 giorni** | un rilascio per milestone ([ADR 0020](../adr/0020-one-version-per-milestone.md)): una versione più vecchia di un mese è probabilmente superata |
| BattleTag, Discord | **180 giorni** | cambiano raramente e il client dell'autore li rilegge a ogni accesso: un valore così vecchio viene da un membro che non entra da mesi |
| registri della banca, like, co-play | **nessuna** | sono storia (voci che non cambiano) o somme, non foto di uno stato |

Le soglie stanno in una tabella sola, `Provenance.DIM_DAYS = { bank = 7, recipes = 60, altGuild = 30, addonVersion = 30, contacts = 180 }`, così un cambio tocca una riga. Test (`Tests/test_provenance.lua`): testo dell'età ai bordi della scala, un'ora nel futuro, ogni fonte nel widget, ogni soglia un secondo prima e un secondo dopo, il nome dell'autore nei tre casi, l'italiano.

## 2. La gilda degli alt fuori dalla gilda (M7.3)

Decisione del proprietario del 2026-11-20 ([ADR 0006](../adr/0006-account-token-and-always-shared-character-list.md), nota di M7.1): la gilda di ogni personaggio elencato si condivide, insieme al giorno del suo ultimo accesso con l'addon. Come l'elenco, è sempre condivisa (D3) e non ha interruttori.

### 2.1 Dato locale

`AzerothAccordDB.chars[<reame>][<GUID>]` ha già `guild` (la chiave di gilda `<reame>/<gilda>`) e `seen`. M7.3 cambia la lettura a ogni accesso del personaggio (`Accounts:RegisterSelf`):

| Situazione al login | `guild` locale | nuovo campo `guildAt` |
|---|---|---|
| in una gilda e il nome è noto (`GuildKey:Current()`) | la chiave di gilda | ora della lettura |
| `Compat.Guild.InGuild()` dice `false` | `""` (nessuna gilda) | ora della lettura |
| in una gilda ma il nome non è ancora arrivato | invariato | invariato |

Oggi un personaggio uscito da una gilda tiene la chiave vecchia (si passa `nil` e il valore resta): per questo una voce **senza `guildAt`** (scritta prima di M7.3) non condivide nessuna gilda finché quel personaggio non entra una volta con la M7.3.

### 2.2 Campi del record `accounts`

Ogni voce di `chars` ([SPEC-03 §1](SPEC-03-data-model.md#1-account-e-personaggi-accounts)) può avere due campi nuovi, **solo per i personaggi fuori dalla gilda del record** (`inGuild = false`):

| Campo | Valore | Assente |
|---|---|---|
| `guild` | il nome della gilda (la parte dopo `/` della chiave, massimo 24 caratteri come nel gioco; più lungo si taglia) oppure `""` = nessuna gilda | gilda sconosciuta (voce vecchia, o client precedente) |
| `seen` | il giorno dell'ultimo accesso con l'addon, come ora del server arrotondata all'inizio del giorno UTC (`seen - seen % 86400`) | sconosciuto |

- I personaggi nel roster (`inGuild = true`) non li portano: la loro gilda è questa e il loro ultimo accesso lo dice il gioco (`GetGuildRosterLastOnline`, nativo).
- `seen` è arrotondato al giorno per non condividere l'ora esatta dei collegamenti di un alt, e perché "visto 3 giorni fa" basta: così un record cambia al massimo una volta al giorno per alt.
- Un cambio di `guild` o `seen` è un cambio del record: il confronto che evita le `rev` inutili (`sameChars`) li considera.

### 2.3 Dimensione

Il record deve restare entro il limite dell'insieme che hanno **anche i client precedenti** (`Store.SETS.accounts.maxBytes` = 4096 B stimati con `Config.EstimateSize`): un client vecchio rifiuta un record più grande (`size`), quindi il limite non si alza. La lista `chars` resta entro `Accounts.MAX_BYTES` = 3600 B (il resto del record ne usa circa 210).

Stima per voce (GUID di 20 caratteri, nome di 12, reame di 10): oggi circa 151 B; fuori gilda con la gilda (fino a 24 caratteri) e `seen` fino a 206 B; nel roster resta 151 B. Una lista di 23 personaggi nel roster sta nel limite, una tipica (8 nel roster e 10 fuori) ne usa circa 3,3 KB.

Se la lista non ci sta, l'ordine dice chi resta:

1. il personaggio stesso (sempre, è la regola del proprietario);
2. i personaggi nel roster della gilda, per livello e poi nome (servono all'**elenco reciproco**: toglierne uno spezzerebbe l'account);
3. i personaggi fuori dalla gilda, per `seen` più recente, poi livello e nome.

Si tolgono voci intere dalla fine finché la lista non sta (come oggi); il massimo di 40 voci resta. Test: un account di 40 personaggi con nomi e gilde lunghi produce un record ≤ 4096 B che un client della versione precedente (il `Store` di oggi) accetta.

### 2.4 Lettura e interfaccia

- Un personaggio fuori gilda elencato da più record dello stesso account prende `guild` e `seen` dalla voce con il **`seen` più alto** (l'alt che ha giocato più di recente sa la cosa più nuova). A parità, il record con il `time` più recente.
- Testi (scheda del membro, righe degli alt nel Roster raggruppato, al posto di `not in guild`):

| Dato | Testo inglese | Testo italiano |
|---|---|---|
| `guild` = nome | `Other guild: <name> · seen <age>` | `Altra gilda: <nome> · visto <età>` |
| `guild` = `""` | `No guild · seen <age>` | `Nessuna gilda · visto <età>` |
| `guild` assente | `Not in guild` (come oggi) | `Non in gilda` |
| `seen` assente | la stessa riga senza `· seen <age>` | |

  `<age>` con la scala di §1.2, a giorni (`today` / `oggi` per il giorno in corso). La riga ha l'etichetta `shared` con l'autore del record scelto, e si attenua dopo 30 giorni (§1.4).
- I personaggi noti **solo da una nota pubblica** (ACC-05, `hint = true`) non mostrano nessuna gilda, solo `declared in the note`.
- Il nome della gilda è un testo altrui: passa per la pulizia dei contatti (niente caratteri di controllo, `|` raddoppiato) e non è mai un link.
- Il cambio di gilda di un alt si vede dopo che quell'alt è entrato (aggiorna `AzerothAccordDB.chars`) **e** un personaggio dell'account che è in questa gilda ha pubblicato di nuovo il proprio record (al suo accesso, o subito se è lui stesso in gilda). Il wiki lo spiega: l'informazione è vecchia quanto l'ultimo accesso dell'alt, e la gilda dell'alt non vede nulla dei dati di Accord di questa gilda.
- **Client precedenti**: ignorano `guild` e `seen` (`Accounts.Rebuild` legge solo i campi che conosce) e continuano a mostrare `not in guild`.

## 3. Modalità demo (M7.4)

`/accord demo` riempie ogni vista con una **gilda inventata**. Serve per provare l'addon senza gilda, per mostrarlo, per i test e per le immagini.

### 3.1 Comportamento

- `/accord demo` entra; di nuovo `/accord demo` (o `/accord demo off`, o il pulsante della striscia) esce. Si entra anche senza gilda e senza rete. Un `/reload` o un'uscita dal gioco chiudono la demo: non resta mai accesa.
- Una **striscia** in cima al pannello (finestra autonoma e tab della finestra Gilda), sopra le schede, con il colore `warning` del tema: `Demo: invented guild. Nothing is sent or saved.` / `Demo: gilda inventata. Non si invia né si salva nulla.` e il pulsante `Exit demo` / `Esci dalla demo`. La barra del titolo e la riga dello stato di sincronizzazione dicono `Demo` invece del numero di compagni.
- **Non si invia nulla**: `Transport:Send` rifiuta ogni messaggio con il motivo `demo` e la coda resta com'era (i messaggi in attesa partono dopo l'uscita); i messaggi che arrivano si scartano (contati come `demo` in `/accord debug`). Sync ferma i timer come a un cambio di gilda. Ciò che si perde nel frattempo lo ripara la sincronizzazione dopo l'uscita (il primo `HELLO` parte 10–30 s dopo, come all'accesso).
- **Non si salva nulla**: all'ingresso `Config.db.account` e `Config.db.char` puntano a **copie** profonde delle tabelle salvate; le variabili globali `AzerothAccordDB` e `AzerothAccordCharDB` (quelle che il gioco scrive) non si toccano. Tutto ciò che si fa nella demo (un like, una richiesta alla banca, un main, il tema) va nelle copie, che all'uscita si buttano. `GuildKey:Data()` per la gilda della demo dà una tabella in memoria che non entra mai in `guilds`.
- I dati del giocatore non si vedono: anche il personaggio del giocatore è inventato (§3.2).
- All'uscita tornano le tabelle vere, la gilda vera (evento `GUILD_CHANGED` con la chiave vera: le viste si ridisegnano come a un cambio di gilda) e la sincronizzazione riparte.

### 3.2 Il livello sopra Compat

Le viste leggono il gioco solo da `Compat`. M7.4 aggiunge `Compat:SetOverlay(overlay)` / `Compat:ClearOverlay()`: finché un overlay è attivo, le funzioni di `Compat.Player` (GUID, nome, reame, classe, livello) e `Compat.Guild` (roster, `InGuild`, `GuildName`, `GuildRealm`, `PlayerRank`, `RankIsOfficer`, `RequestRoster` che non fa nulla) rispondono dall'overlay e non chiamano il gioco. Le fonti native facoltative (professioni e Discord del club, ricette native della gilda, banca, BattleTag) rispondono "non disponibile", così le viste usano i dati condivisi della demo come quando il server non li dà. Le capacità (`Compat:Feature`) non cambiano durante la demo. Solo `Core/Demo.lua` usa l'overlay.

### 3.3 La gilda inventata

`Data/Demo.lua` costruisce i dati con un generatore deterministico (seme fisso: due ingressi danno gli stessi dati) e **senza chiamate al client**, così si carica anche fuori dal gioco. Contenuto minimo, perché ogni vista abbia qualcosa:

| Dato | Contenuto |
|---|---|
| gilda | nome `Demo Guild`, reame `Demo`; 5 gradi (Guild Master, Officer, Veteran, Member, Initiate), i primi due ufficiali |
| roster | 60 membri con nomi **inventati** da un elenco fisso nel file (nessun nome di giocatore reale, [ADR 0019](../adr/0019-design-previews-original-art-invented-data.md)), tutte le classi, livelli da 10 al massimo, zone, 15 online, ultimi accessi fino a 90 giorni; due nomi con lo spazio (nome e cognome, §6.6) |
| il giocatore | un membro della demo, ufficiale, con tre personaggi: così si vedono anche le viste degli ufficiali |
| account | 20 account con l'addon, 1–4 personaggi ciascuno; tra gli alt uno in un'altra gilda (`Wandering Stars`, visto 3 giorni fa), uno senza gilda, uno visto 45 giorni fa (attenuato), e un membro con `alt: <nome>` nella nota |
| contatti | BattleTag nella forma `Name#1234` e nomi Discord inventati |
| ricette | 3 professioni con liste di spellID veri del gioco (i nomi li dà il client), una con `observedAt` di 70 giorni fa (attenuata) |
| co-play | 30 giorni di osservazioni tra i membri con l'addon, con almeno due gruppetti visibili nella mappa |
| like | 40 voci del libro |
| banca | 3 schede (una solo per ufficiali) con itemID veri, denaro, registri di 30 giorni, 6 richieste in ogni stato |
| impostazioni della gilda | `guildcfg` predefinito (raid `accord`, loot `none`) |

I record della demo rispettano le regole di forma e del proprietario di `Store` (i test li fanno passare da `Store:Check`). Gli strumenti delle anteprime di [ADR 0019](../adr/0019-design-previews-original-art-invented-data.md) (`tools/make_mockups.py`) possono caricare `Data/Demo.lua` con lupa e prendere nomi e valori da lì invece di averne di propri; M7.4 non lo richiede.

Test (`Tests/test_demo.lua`): ogni vista, la scheda, la pagina Settings e `/accord debug` si aprono nella demo senza gilda e senza rete e senza errori; dopo azioni che scriverebbero (like, richiesta, main, tema, nome Discord) l'uscita lascia `AzerothAccordDB` e `AzerothAccordCharDB` identici a prima (confronto della serializzazione) e il contatore degli invii di `Transport` invariato; un messaggio ricevuto durante la demo non entra in nessuno dei due archivi.

## 4. Backup personale (M7.5)

Un testo da copiare che porta i dati **propri** del giocatore su un altro computer.

### 4.1 Formato

```
AZACCORD1:<checksum>:<corpo>
```

- `AZACCORD` è l'intestazione fissa, `1` la **versione del formato** (un intero; cresce quando il contenuto cambia in modo che un addon vecchio non capirebbe).
- `<corpo>` = Base64 (lo stesso di `Codec`, alfabeto `A–Z a–z 0–9 + /`, con `=`) di un byte di formato seguito dal CBOR del contenuto, compresso con Deflate quando accorcia (byte `1`) o no (byte `0`): la stessa codifica dei messaggi di rete ([SPEC-02 §2](SPEC-02-network-protocol.md#2-formato)), con le stesse librerie.
- `<checksum>` = le prime **8 cifre esadecimali minuscole** dello SHA-256 (`Hash`) del testo `<corpo>`. Non è una protezione contro chi falsifica (chiunque può ricalcolarla): serve a riconoscere un testo tagliato o cambiato nella copia.
- Il testo è su una sola riga; all'importazione spazi e a capo si tolgono prima di leggerlo. Lunghezza massima **256 KB** (262 144 caratteri) sia in uscita sia in entrata.

### 4.2 Contenuto

Il CBOR è una tabella `{ v = 1, made = <ora del server>, addon = <versione>, account = {...}, guilds = {...} }`:

| Parte | Cosa | Da dove |
|---|---|---|
| `account.token` | il token dell'account | `AzerothAccordDB.token` |
| `account.chars` | i personaggi dell'account, per reame, con i campi locali (`name`, `classID`, `level`, `guild`, `guildAt`, `seen`, `added`, `answered`) | `AzerothAccordDB.chars` |
| `account.mains` | il main scelto per ogni reame | `AzerothAccordDB.mains` |
| `account.settings` | le impostazioni dell'account (aspetto, notifiche, nome Discord) | `AzerothAccordDB.settings` |
| `guilds[<chiave>]` | per ogni gilda conosciuta: i **record propri** degli insiemi `accounts`, `contacts` e `recipes`, cioè quelli il cui `id` (o `char` per le ricette) è un personaggio dell'account | `GuildKey:Data(chiave).store` |

Non entrano **mai**: i record di altri giocatori (anche se l'autore è un ufficiale che ha ripassato i miei), co-play (sono osservazioni che nominano altri), foto e registri della banca (sono dati della gilda), richieste alla banca (portano decisioni degli ufficiali; tornano dalla sincronizzazione), il libro dei like e la coda e l'elenco dei like dati su questo computer (nominano altri; dopo il ripristino un secondo voto per lo stesso account viene rifiutato dal notaio come già dato, `dup`, perché il token ripristinato dà lo stesso pseudonimo), il salt dei like, le impostazioni della gilda, le impostazioni per personaggio (`AzerothAccordCharDB`: la posizione della finestra è del computer), la coda in uscita. Test: in un'esportazione da una gilda piena non compare nessun GUID e nessun nome che non sia di un personaggio dell'account.

L'esportazione dice, sopra la casella: `Keep this text private: it holds your account token. Someone who publishes your token blocks your likes until they stop.` (il rischio noto di [SPEC-07 §2](SPEC-07-reputation-social.md), `conflict`).

### 4.3 Interfaccia

Una card **Backup** nella pagina Settings con due pulsanti: **Export** apre una casella a più righe di sola lettura con il testo già selezionato (Ctrl+C); **Import** apre una casella vuota in cui incollare (Ctrl+V) e il pulsante **Check**. Anche `/accord backup` apre la card. Nella demo e con i dati in sola lettura (schema più nuovo, [ADR 0011](../adr/0011-embedded-ace3-savedvariables-and-schema-versions.md)) l'importazione non c'è e la card dice perché; l'esportazione nella demo non c'è.

### 4.4 Validazione

In questo ordine; al primo errore il testo si rifiuta **tutto**, nulla cambia, e la casella dice il motivo:

| # | Controllo | Messaggio (inglese) |
|---|---|---|
| 1 | vuoto, oltre 256 KB, o senza `AZACCORD<n>:<8 hex>:` | `This is not an Azeroth Accord backup.` |
| 2 | versione maggiore di quella che l'addon conosce | `This backup was made by a newer version of Azeroth Accord. Update the addon and try again.` |
| 3 | checksum diversa | `The backup is damaged or incomplete: copy the whole text again.` |
| 4 | Base64, Deflate o CBOR non leggibili, oltre 1 MB decompresso, `v` diverso dall'intestazione | stesso messaggio del 3 |
| 5 | forma: token come la regola di `Config` (24 caratteri Base64), reami e GUID validi (`Player-…`), nomi di 1–48 caratteri, impostazioni secondo `Config.rules` (un valore sconosciuto o sbagliato è un errore, non un ripristino del predefinito), ogni record con la forma e la regola del proprietario di `Store` e il suo personaggio nell'elenco del backup | `This backup contains data Accord cannot use (<parte>). Nothing was changed.` |
| 6 | **di un altro account**: il token è diverso da quello di questo computer **e** questo computer conosce almeno un personaggio, oltre a quello connesso, che il backup non elenca | `This backup belongs to another account. Nothing was changed.` |

Un computer nuovo (solo il personaggio connesso, token appena creato) accetta il backup del proprio account; se il personaggio connesso non è nel backup, l'anteprima lo dice e lo aggiunge.

### 4.5 Anteprima e applicazione

Un testo valido mostra prima un'**anteprima** delle differenze, poi **Import** / **Cancel**:

- token: `kept` o `replaced` (con la nota che i like continuano con lo pseudonimo del backup);
- personaggi: quelli aggiunti (nome e reame), quelli già presenti; per un personaggio presente vale la voce con `seen` più recente;
- main per reame: quello del backup, se diverso, con il nome vecchio e quello nuovo;
- impostazioni: ogni chiave diversa, `vecchio → nuovo`;
- record propri: per gilda, quanti si ripristinano (il backup ha una `rev` più alta, o il computer non li ha) e quanti restano (il computer ne ha uno più nuovo: `Store.Compare`). Un record non si ripristina mai con una versione più vecchia.

L'importazione scrive solo in `AzerothAccordDB` (mai nella coda di rete), poi ricalcola gli account (`ACCOUNTS_UPDATED`), ridisegna il tema e ripubblica il proprio record `accounts` e i contatti se sono cambiati: la `rev` riparte da quella ripristinata. Il risultato si dice in una riga (`Backup imported: 3 characters, 2 settings, 5 records.`). Nota di realizzazione (M7.5): il modulo è `Data/Backup.lua`, la casella `UI/BackupBox.lua`. Delle impostazioni si applicano solo le chiavi presenti nel backup (una chiave che il backup non ha, come un nome Discord tolto, resta com'è su questo computer). Un personaggio presente nei due posti prende la voce del backup solo se il suo `seen` è più recente. Test (`Tests/test_backup.lua`): andata e ritorno su un client vuoto danno gli stessi dati; ogni rifiuto della tabella con il suo messaggio; un testo con un carattere cambiato; un backup di un altro account; un'anteprima con `rev` più vecchie; nessun dato di altri nell'esportazione; l'italiano.

## 5. Pannello "Cosa condivido" (M7.6)

Una sotto-pagina di Settings (`SettingsView.AddPage("share", ...)`, selettore *Settings · What I share · Info*), titolo `What I share` / `Cosa condivido`. Per ogni insieme di dati che **questo personaggio** pubblica: chi lo riceve, quando parte, il contenuto attuale e se c'è un interruttore. Il contenuto viene dai record che il client tiene con `author` = questo personaggio, cioè gli stessi che ha mandato o che aspettano nella coda (ogni scrittura locale esce come `REC`, [SPEC-02 §4](SPEC-02-network-protocol.md#4-sincronizzazione)); per ognuno si mostrano `rev` e l'età (`updated 2 h ago`). Un modello senza frame, `ShareModel.Describe()`, dà le righe; il test confronta il modello con `Store` (`Tests/test_settings.lua`).

| Insieme | A chi | Contenuto mostrato | Interruttore |
|---|---|---|---|
| Personaggi dell'account (`accounts`) | tutta la gilda | il token (i primi 4 caratteri e `…`, con il tooltip: casuale, non legato all'account Battle.net), ogni personaggio con nome, reame, classe, livello e `In this guild` / `Other guild: X` / `No guild` / `Not in guild`, il giorno `seen`, il main, la versione dell'addon | no, sempre condiviso (D3) |
| Contatti (`contacts`) | tutta la gilda | BattleTag, nome Discord | no, sempre condiviso (D3) |
| Ricette (`recipes`) | tutta la gilda | per professione: nome, grado, numero di ricette | no: sono la funzione stessa (Q12) |
| Gioco di gruppo (`coplay`) | tutta la gilda | gli ultimi 7 giorni: per giorno quante coppie e quanti minuti; la riga dice che le coppie nominano i compagni (per GUID) | sì: `Record time played together` / `Registra il tempo giocato insieme` (Q12) |
| Foto della banca (`bank`) | tutta la gilda; le schede che solo gli ufficiali vedono solo agli ufficiali | le schede lette (nome, numero di oggetti), il denaro, i registri, con l'età | no: si scrivono solo aprendo la banca |
| Richieste alla banca (`bankreq`) | tutta la gilda | le proprie richieste aperte e chiuse (numero, le ultime 5, con la mancia) | no |
| Like | solo al notaio, in whisper | quanti like ha dato questo account (tenuto solo su questo computer); la gilda vede solo totali anonimi | no |
| Riepilogo della sincronizzazione (`HELLO`) | tutta la gilda | la versione dell'addon e un'impronta di quali record si hanno, mai il contenuto | no |
| Solo per ufficiali: voci del libro dei like scritte come notaio, impostazioni della gilda (`guildcfg`), il salt dei like | ufficiali (le voci del libro, che sono pseudonime, a tutta la gilda) | conteggi e la scelta delle fonti | no |

- Le righe dei personaggi degli **altri** personaggi dell'account non si mostrano come pubblicate da questo: una riga dice `Your other characters publish their own records when they log in.`
- Quando arriveranno altri insiemi (per esempio l'elenco degli addon di M9.9, con l'interruttore della risposta a Q11) si aggiungono con `ShareModel.Add(id, def)`, come le sezioni della scheda. *Fatto in M9.9*: la riga `addons` (*Loaded addons*, quarta, solo con l'interruttore `census` acceso: `def.feature`) con quanti addon e i primi 5, la nota sui nomi (Q17) e l'interruttore `Share my addon list`; i testi dell'interruttore e della nota "spento" sono ora della definizione (`switchLabel`, `switchTip`, `offNote`), con quelli del gioco di gruppo come predefiniti ([SPEC-13 §8](SPEC-13-action-center-notices.md#8-censimento-degli-addon-m99)).
- **Interruttori** (risposta del proprietario a Q12, 2026-11-24): c'è un solo interruttore, per il gioco di gruppo, `Record time played together` / `Registra il tempo giocato insieme`, chiave `account.settings.shareCoplay` (booleano, predefinito `true`; lo schema 3 lo aggiunge con una migrazione). Spento, questo client non osserva e non pubblica più co-play (`CoPlay:Tick` e `CoPlay:Publish` non fanno nulla) e non scrive record nuovi; i record già pubblicati restano fino alla loro scadenza (90 giorni); gli altri continuano a osservare i gruppi in cui c'è anche questo personaggio, e la riga lo dice. Ricette e foto della banca non hanno interruttore; D3 (alt, BattleTag, Discord) e le funzioni stesse restano sempre condivisi.

## 6. Limiti contro i client malevoli e le gilde grandi (M7.7)

Cosa esiste già: la forma dei messaggi (`Codec`: 16 KB decompressi al massimo, tipi e versioni sconosciuti ignorati), la forma e la fiducia dei record (`Store`: id, autore, `rev`, ora, dimensione per insieme, prima mano, ufficiali, regole del proprietario), i limiti di invio (`Transport`: coda di 200, intervalli per distribuzione) e delle richieste su misura (20 al minuto per mittente). M7.7 aggiunge i limiti sotto e li prova.

### 6.1 Dimensioni

| Limite | Valore | Dove |
|---|---|---|
| testo di un messaggio prima della decodifica | `Codec.MAX_TEXT` (circa 21,9 KB) | esiste |
| CBOR dopo la decompressione | 16 KB (`Codec.MAX_DECODED`) | esiste |
| record in un `REC` | **al massimo 100**; oltre, il messaggio si scarta intero (`count`) e conta come un record rifiutato (§6.3); chi invia divide a 100 | `Sync` (M7.7) |
| autori chiesti in un `REQ` | 500 (`*`) o 20 (un insieme) | esiste |
| voci in un riepilogo | 2000 | esiste |
| un record | `maxBytes` del suo insieme | esiste |
| profondità di una tabella decodificata | **8 livelli** (il messaggio è il livello 1); più profonda si scarta (`depth`) | `Codec` (M7.7) |

Il Deflate non si può fermare a metà: il limite vero contro una "bomba" è il testo in entrata (circa 16 KB compressi) più il budget per mittente di §6.3.

### 6.2 Messaggi malformati, autori falsi, revisioni ripetute

| Caso | Risposta attesa |
|---|---|
| testo non Base64, troncato, byte di formato sconosciuto, CBOR rotto, campo richiesto mancante o del tipo sbagliato | scartato da `Codec` con il motivo, nessun errore Lua |
| record di un altro autore da un membro non ufficiale (autore falso) | `relay` (NET-10/11) |
| un `accounts` che elenca un personaggio altrui | accettato come record del mittente, ma non unisce nulla (elenco reciproco) |
| record con `author` che non ha la forma di un GUID, `rev` non intera, `time` oltre un'ora nel futuro | `author`, `rev`, `future` |
| revisione ripetuta (la stessa `rev` e lo stesso contenuto) o più vecchia | `same` / `older`: nulla cambia, non è un errore |
| stessa `rev` dell'autore con contenuto diverso | vince il `time` più recente, poi l'autore; solo l'account dell'autore o un ufficiale può mandarla (fiducia) |
| `rev` = `Store.MAX_REV` da un client che vuole "bloccare" un id | accettata solo da chi può scrivere quell'id (il suo account): non tocca i record degli altri |
| un errore Lua in un gestore | preso dal `Bus` (pcall), registrato per `/accord debug`; il messaggio successivo si elabora |

Nessuno di questi casi blocca la coda in uscita: ricevere e inviare sono indipendenti.

### 6.3 Inondazioni

Contatori per mittente (nome dato dal server), azzerati a ogni cambio di gilda:

| Limite per mittente | Valore | Oltre |
|---|---|---|
| `HELLO` / `BHELLO` elaborati | 1 ogni 60 s (un client onesto ne manda 1 ogni 5 minuti, ma dopo un `/reload` o un nuovo accesso ne manda un altro entro il minuto) | contati `flood`; si tiene solo l'ultimo, elaborato allo scadere del minuto (M7.7: scartarlo faceva aspettare 15–20 minuti a chi rientra subito), gli altri si ignorano |
| `REQ` di tutti gli insiemi (`*`) | 10 al minuto | ignorati |
| `REQ` di un insieme | 20 al minuto | esiste |
| testo decodificato | **256 KB al minuto** (un client onesto, frenato da ChatThrottleLib a circa 800 B/s, ne manda meno di 50 KB di testo, che decompressi restano sotto 200 KB) | il mittente è **in quarantena** |
| record rifiutati (non `same`/`older`) | 50 in 10 minuti | il mittente è **in quarantena** |

**Quarantena**: per 10 minuti ogni messaggio di quel mittente si scarta prima della decodifica; `/accord debug` mostra quanti mittenti lo sono (mai i nomi, [SPEC-09 §6](SPEC-09-quality-release.md#6-diagnostica-e-segnalazioni-m64)). Alla fine la sincronizzazione ripara ciò che si è perso. Un ufficiale in quarantena resta ufficiale: la quarantena tocca solo i messaggi.

### 6.4 Riepilogo a blocchi per le gilde grandi

Il riepilogo per autore cresce di 11 B per autore ([SPEC-02 §4](SPEC-02-network-protocol.md#4-sincronizzazione)): con 1000 autori un `HELLO` sarebbe di 11 KB (45 pezzi) e 1000 accessi insieme ne manderebbero 11 MB sul canale. Per questo:

- **Soglia**: un client che tiene più di **200 autori** (non riservati) manda `BHELLO` invece di `HELLO`. Sotto la soglia nulla cambia.
- **`BHELLO`** (nuovo tipo su `GUILD`, registrato con `Codec:RegisterType("BHELLO", { b = "string" })`): `b` = **96 blocchi** da 3 byte (288 B), `n` = numero di autori, `av` = versione. Un autore sta nel blocco `floor(m / 2^32 × 96)`, dove `m` = (chiave × 2654435761) mod 2^32 (hash di Fibonacci, calcolato esatto a metà da 16 bit: `Sync.BlockOf`); il digest di un blocco è la somma modulo 2^24 di `Hash.Fast` di chiave, digest e ora di ogni suo autore (0 per un blocco vuoto). Un client precedente ignora il tipo (NET-01).
  - *Cambiato in M7.7* (§6.5 lo permette): la specifica diceva 128 blocchi presi dai 7 bit alti della chiave. Due misure del simulatore l'hanno smentita: (1) `Hash.Fast` dà quasi gli stessi bit alti a GUID che differiscono solo nelle ultime cifre, come i personaggi di uno stesso reame, quindi gli autori finivano in pochi blocchi (un `BHELLO` di 1000 autori si comprimeva a 69 B: quasi tutti i blocchi vuoti); (2) con 128 blocchi distribuiti davvero il `BHELLO` pesa 565 B, oltre il limite di 512 B di §6.5. Con 96 blocchi e l'hash di Fibonacci pesa circa 440 B (2 pezzi) e ogni blocco tiene circa 10 dei 1000 autori.
- **Risposta**: chi riceve un `BHELLO` calcola i propri blocchi. Se uno o più differiscono, rispondono solo (a) l'**ufficiale designato** per il mittente (la regola di oggi, punto 2 di SPEC-02 §4) con gli autori di quei blocchi, e (b) un personaggio dello stesso account del mittente che sia online, con i soli autori del proprio account (e il campo `o`, così il mittente confronta solo quelli). La risposta è un `DIGEST` (il tipo riservato) in `WHISPER`: `d = { [blocco] = riepilogo per autore di quel blocco }` (un blocco vuoto è la stringa vuota), priorità `NORMAL`, chiave di coda `DIGEST|<mittente>`. Chi risponde mette al massimo **1400 voci** (11 B ciascuna: il messaggio resta sotto i 16 KB di `Codec.MAX_DECODED`; i blocchi che non entrano aspettano il `BHELLO` successivo); chi riceve ne accetta al massimo 2000. Un `DIGEST` senza un proprio `BHELLO` negli ultimi 10 minuti, o il secondo dello stesso mittente per lo stesso `BHELLO`, si ignora (nessuno può farsi mandare record senza averli chiesti).
- **Dopo il `DIGEST`**: il mittente confronta autore per autore, come con un `HELLO` di oggi: chiede con `REQ` ciò in cui l'altro è più avanti, e se può consegnare (proprio account, o è ufficiale) manda in whisper ciò in cui è più avanti lui, compresi gli autori che l'altro non ha.
- **Compatibilità**: un client usa `BHELLO` solo se ogni ufficiale sentito negli ultimi 25 minuti ha mandato una versione (`av`) che lo conosce (dalla `v0.7.0`); altrimenti manda il `HELLO` per autore come oggi. Un client nuovo risponde sempre anche ai `HELLO` per autore.
  - *Precisato in M7.7*: conta solo un ufficiale di cui si è già sentito un `HELLO` o `BHELLO` (e quindi `av`). Un ufficiale sentito finora solo per altri messaggi (un `REC` con cui ha risposto prima del suo primo saluto, come dopo un riavvio del server) non conta ancora: altrimenti, nella prova dei 1000 accessi, quasi ogni membro tornava al `HELLO` per autore (11 KB, letto da tutti). Un client precedente manda `av` nel suo `HELLO`, quindi si riconosce al suo primo saluto (al più 20 minuti in cui un ufficiale vecchio non risponde a un `BHELLO`).
- **Accessi distribuiti**: il primo `HELLO` o `BHELLO` dopo l'accesso parte dopo `10 + random(0, 20 + autori / 10)` secondi (1000 autori: da 10 a 130 s), non più 10–30 s; il periodo resta 15–20 minuti. Un ufficiale manda al massimo un `DIGEST` ogni 2 s (gli altri aspettano in coda con la loro chiave, così due `BHELLO` dello stesso mittente danno una risposta sola).

### 6.5 La prova dei 1000 accessi

Il simulatore (`Tests/sim/sim.lua`) aggiunge uno scenario: **1000 membri**, tutti con l'addon (il caso peggiore), 10 ufficiali, tutti allineati prima di un riavvio del server, poi tutti entrano entro 60 secondi; nei primi 10 minuti 50 autori scrivono qualcosa; 1% di messaggi persi, latenza 0,05–0,5 s; si misurano i primi 30 minuti. Limiti (il budget di traffico di SPEC-02 §4, più quelli della raffica):

| Misura | Limite | Misurato (M7.7), Windows | Misurato (M7.7), CI Linux |
|---|---|---|---|
| un `BHELLO` sul filo | ≤ 512 B (3 pezzi) | 437 B, 2 pezzi | 437 B, 2 pezzi |
| invio medio per client nei 30 minuti | ≤ 400 B/min | 32 B/min | 32 B/min |
| client più carico (un ufficiale) | ≤ 3 KB/min | 965 B/min | 981 B/min |
| coda di `Transport` di ogni client | mai oltre 100 messaggi; nessun `BULK` scartato | al massimo 22; nulla scartato né scaduto | al massimo 14; nulla scartato né scaduto |
| convergenza dopo l'ultima scrittura | ≤ 25 minuti (1500 s) | 730 s (circa 12 minuti) | **1480 s** (circa 25 minuti) |
| tempo di CPU del simulatore per un `BHELLO` ricevuto (blocchi propri in cache) | ≤ 1 ms offline | 0,008 ms | 0,005 ms |

Nei giri misurati: 2000 `BHELLO` e 132 `DIGEST` (Windows), 2175 e 152 (Linux) in 30 minuti; circa 4 minuti e mezzo su Windows e un minuto e mezzo su Linux, 3–5 GB di memoria offline. Le due piattaforme fanno percorsi casuali diversi con lo stesso seme (le dimensioni dei pezzi compressi cambiano i tempi).

**Margine stretto sulla convergenza**: su Linux l'ultima scrittura si ripara 20 s prima del limite. È il caso previsto da [SPEC-02 §4](SPEC-02-network-protocol.md#4-sincronizzazione): un messaggio perso (1%) aspetta il `BHELLO` successivo di chi lo ha (15–20 minuti), e con i blocchi la riparazione passa dall'ufficiale designato, quindi a volte servono due periodi parziali. Il test non è cambiato; se un passo futuro lo fa fallire su questo punto, la scelta tra alzare il limite (con una nota in [SPEC-10](SPEC-10-risks-open-questions.md)) e accorciare la riparazione spetta al proprietario ([SPEC-10 R9](SPEC-10-risks-open-questions.md)).

Se lo scenario non sta nei limiti, M7.7 cambia i parametri di questa sezione (soglia, blocchi, ritardi) e lo scrive qui; un limite si alza solo con una nota in [SPEC-10](SPEC-10-risks-open-questions.md).

**Come gira (M7.7).** Lo scenario è in `Tests/test_hardening.lua` ("the 1000 logins"). Mille copie dell'addon in un solo processo non stanno in un test normale, per questo:

- i client del simulatore sono **leggeri** (opzione `lean` di `Sim.new`): caricano le librerie, `Core`, `GuildKey` e lo strato di rete, cioè tutto ciò che manda messaggi in questo scenario; le viste e gli altri moduli di dati non ci sono;
- i record allineati sono le stesse tabelle in ogni archivio (ognuno ha il proprio indice), le righe del roster del mock sono condivise, e le funzioni pure di decodifica del mock (Base64, Deflate, CBOR) memorizzano il risultato per lo stesso testo, che arriva a mille client; il roster non cambia durante la raffica, quindi la risposta del server a una richiesta del roster (`GUILD_ROSTER_UPDATE`) non c'è;
- un membro che non è ufficiale né dello stesso account del mittente non fa nulla di un `BHELLO` (§6.4: non risponde), e in questa gilda ogni personaggio è il proprio account: il simulatore non gli consegna i `BHELLO` degli altri membri (opzione `skip`, contati a parte), mentre quelli degli ufficiali arrivano a tutti (ne leggono la versione); quanto costa a un membro leggerne uno è la misura "tempo di CPU" sotto;
- anche così servono alcuni GB e qualche minuto: lo scenario gira con `Tests/run_tests.py --long` (o `AZACCORD_LONG=1`) e nel workflow **Long tests** (`.github/workflows/long-tests.yml`: a ogni pull request che tocca lo strato di rete, il simulatore o questi test, ogni lunedì e a richiesta), non nella suite di ogni passo.

Le misure portano a due cambi dell'addon, oltre ai parametri di §6.4: il riepilogo per autore si tiene aggiornato record per record (prima ogni record ricevuto faceva ricalcolare l'hash di tutti gli autori: con 1000 autori e mille client era il costo maggiore, e in gioco un lavoro inutile per ogni record), e un `BHELLO` uguale ai propri blocchi si riconosce confrontando una stringa.

### 6.6 Nomi con lo spazio

Su Forever un personaggio può avere un nome completo con uno spazio (`Name Surname`); il mittente arriva come `Name Surname` o `Name Surname-Realm`. Regole che M7.7 prova in ogni insieme di dati:

- Il nome si separa dal reame solo all'**ultimo** trattino che segue (`^(.-)%-([^%-]+)$`); un nome senza trattino è del reame del giocatore. Vale in `Store:Member`, `Transport.IsSelf`, `Roster` e nei bersagli dei whisper: una sola funzione, `Compat.SplitName`.
- **Whisper e inviti** del giocatore (i pulsanti del co-play, la richiesta di una ricetta): un nome con lo spazio è un nome valido (`Compat.PlainName`: niente `|`, caratteri di controllo, spazi agli estremi o doppi). Il whisper non passa da `/w Nome Cognome testo`, che il gioco leggerebbe come un whisper a `Nome`, ma da `ChatFrame_SendTellWithMessage` (o `ChatFrame_SendTell` senza testo), che prendono il nome intero; senza queste funzioni non si apre nulla.
- **Note pubbliche** (ACC-05): dopo `main:` o `alt:` si prova il prefisso di **3, poi 2, poi 1 parola** (separatori `, ; | /` e fine nota) che corrisponde a un nome del roster, senza maiuscole: `alt: Name Surname, tank` trova `Name Surname`.
- **Diagnostica**: `Diag.Redact` sostituisce il nome intero e poi ogni sua parola di almeno 3 caratteri.
- **Interfaccia**: i nomi lunghi si tagliano con i puntini nelle colonne, mai a capo; il tooltip ha il nome intero.
- **Dati**: i nomi con lo spazio fanno andata e ritorno in `accounts`, nei registri della banca (`tipo,nome,…`), nelle richieste, nel backup (§4), nella demo (§3.3) e nei suggerimenti del co-play.
- **[verificare]** in gioco il formato del mittente di `CHAT_MSG_ADDON` per un nome con lo spazio, un whisper addon verso un nome così, `ChatFrame_SendTellWithMessage` e `C_PartyInfo.InviteUnit` con un nome con lo spazio.

Test (`Tests/test_hardening.lua` e lo scenario del simulatore): ogni caso di §6.2 e §6.3 si rifiuta senza errori e senza fermare la coda; la raffica rispetta §6.5; i nomi con lo spazio fanno andata e ritorno.

## 7. Cosa resta da verificare nel client

- `GetGuildInfo("player")` di un alt in un'altra gilda al login, e la grafia di nomi di gilda con spazi e accenti (M7.3).
- Che le copie di `Config.db` della demo non arrivino mai nel file salvato dopo un `/logout` fatto nella demo (M7.4).
- Il copia e incolla di un testo di 256 KB in una casella del gioco, e il tempo che serve (M7.5).
- Il formato del mittente con nomi con lo spazio, il whisper e l'invito a un nome così, e la reale velocità di ChatThrottleLib su Forever per i limiti di §6.3 (M7.7).
