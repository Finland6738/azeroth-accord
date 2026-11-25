# SPEC-14: Calendario, raid e roster della season

Specifica della milestone M10 ([roadmap](../roadmap/M10-calendar-raids.md)): il **roster della season** (ogni raider dichiara una volta per season che cosa gioca), gli **eventi e le iscrizioni sul calendario del gioco**, l'**importazione degli eventi di Raid-Helper** da Discord, la **panchina e la composizione**, la **mappa della disponibilità** e i **raduni PvP e nel mondo**. Tutto funziona **insieme** agli addon di raid e di loot che la gilda usa già, mai contro di loro ([ADR 0022](../adr/0022-integrations-with-raid-and-loot-addons.md)). Ogni sezione dice il passo che la realizza. Le scelte che spettano al proprietario sono in [SPEC-10](SPEC-10-risks-open-questions.md) (Q20–Q25): finché non risponde, il codice applica la proposta scritta lì.

Nomi di codice, campi e testi dell'interfaccia in inglese (con la traduzione italiana in `itIT.lua`, [ADR 0015](../adr/0015-interface-and-documentation-languages.md)). Le ore dei record sono ore del server in secondi (`Compat.ServerTime()`); le date degli eventi sono quelle del calendario del gioco (ora del reame).

## 1. Principi

Le regole di integrazione del proprietario (2026-11-24, [M10](../roadmap/M10-calendar-raids.md#integration-rules-owner-2026-11-24)) valgono per ogni passo:

| # | Regola | Che cosa vuol dire qui |
|---|---|---|
| RAID-01 | **Una sola fonte per dato** | il roster della season, la formazione e la panchina (`raid`) appartengono ad Accord **oppure** a FDCP, secondo il record `sources` di `guildcfg` scelto dagli ufficiali (§3); mai un'ipotesi di ogni client |
| RAID-02 | **Il calendario del gioco è il terreno comune** | eventi e risposte si leggono e si scrivono nel calendario del gioco (§5); un evento solo dell'addon esiste solo senza calendario e lo dice |
| RAID-03 | **Integrazioni in sola lettura** | Accord legge un altro addon solo dalla sua API pubblica con versione (livello 1); non scrive mai i suoi dati né legge le sue SavedVariables; livello 2 mai |
| RAID-04 | **Nessun motore del loot** | nessun punteggio, priorità o assegnazione degli oggetti (SPEC-10 Q6) |
| RAID-05 | **Nessuna presenza** | Accord non registra né manda chi era a un raid; la mappa della disponibilità (§8) conta solo la presenza online |
| RAID-06 | **Solo addon di loot e di roster del raid** | nessun altro gestore di gilda è riconosciuto o letto |
| RAID-07 | **Discord solo incollando** | nessuna connessione a Discord o a un bot: l'evento di Raid-Helper entra come testo incollato da un ufficiale e torna come testo da incollare (§6) |
| RAID-08 | **Traffico condiviso** | Accord e gli altri addon mandano sugli stessi canali con gli stessi limiti del server ([SPEC-09 §7](SPEC-09-quality-release.md#7-budget-di-traffico-condiviso-m10)); silenzio durante i boss (§10) |

## 2. Moduli, interruttore, dati locali

### 2.1 Interruttore

Tutto M10 sta dietro l'interruttore esistente `raid` di [`Core/Features.lua`](../../AzerothAccord/Core/Features.lua), **spento** finché M10 e M11 non sono completi (decisione del proprietario, 2026-11-25). Spento vuol dire, oltre a quanto già scritto in ADR 0022 punto 10: nessuna vista *Season*, *Events* o *Availability*, nessun comando nuovo, gli insiemi `season`, `raidev`, `avail` e `rally` non si accettano né si mandano (`feature = "raid"` nella definizione di `Net/Store.lua`), nessuna chiamata a `C_Calendar`, nessun raduno. Come per gli altri interruttori, i moduli chiedono `Features.On("raid")` quando agiscono, i test lo accendono e `Tests/test_features.lua` controlla che spento non si veda e non si mandi nulla.

### 2.2 File nuovi

| File | Contenuto | Passo |
|---|---|---|
| `Data/Specs.lua` | la tabella delle classi e delle specializzazioni del gioco base, con il ruolo predefinito (§4.3) | M10.3 |
| `Data/Season.lua` | season e dichiarazioni, il fornitore `OWN` di `Integrations` (§4) | M10.3 |
| `UI/Season.lua` | la vista *Season*: la propria dichiarazione, l'elenco, i conteggi per gli ufficiali, l'esportazione (§4.6) | M10.3, M10.4 |
| `Data/Calendar.lua` | lettura degli eventi di gilda e delle risposte, la propria risposta, gli eventi solo dell'addon (§5) | M10.5 |
| `Data/RaidHelper.lua` | lettura del testo incollato, abbinamento, copia nel calendario (§6) | M10.6 |
| `Data/Composition.lua` | formazione e panchina, composizione obiettivo (§7) | M10.7 |
| `UI/Events.lua` | la vista *Events*: elenco, dettaglio, iscrizione, importazione, composizione | M10.5–M10.7 |
| `Data/Availability.lua`, `UI/Availability.lua` | la mappa della disponibilità (§8) | M10.8 |
| `Data/Rallies.lua` | i raduni (§9), mostrati nella vista *Events* e nel Centro azioni | M10.9 |

La vista **Raid** di M11.7 (`UI/Raid.lua`) resta il posto della scelta delle fonti e della lettura di FDCP; *Season* ed *Events* la affiancano. `Config.VIEWS` aggiunge `season`, `events`, `availability`. Comandi: `/accord season`, `/accord events`, `/accord availability` (con l'interruttore spento rispondono come un comando sconosciuto).

### 2.3 Eventi del Bus

`SEASON_CHANGED()` (season aperta o chiusa, dichiarazione arrivata o scritta, fonte cambiata), `CALENDAR_CHANGED()` (eventi o risposte del calendario riletti), `EVENT_CHANGED(key)` (un evento: risposte, ruoli, importazione, composizione), `AVAILABILITY_CHANGED()`, `RALLY_CHANGED(id)`. Si aggiungono all'intestazione di `Core/Bus.lua`.

### 2.4 Impostazioni

Nessuna migrazione di schema: le chiavi nuove si aggiungono dove mancano, con il loro predefinito, al primo uso.

| Chiave | Tipo e predefinito | Sezione |
|---|---|---|
| `account.settings.shareAvailability` | booleano, `true` (SPEC-10 Q23) | §8.3 |
| `GuildKey:Data().raidHelper` | `{ manual = { [nome normalizzato] = GUID }, imports = { [id] = { unmatched = { nomi }, at } } }`, solo sul computer dell'ufficiale (SPEC-10 Q22) | §6.4 |
| `AzerothAccordDB.avail` | `{ weeks = { [settimana] = { [ora della settimana] = minuti } } }` per account, 8 settimane | §8.1 |

## 3. La fonte e i fornitori (M10.2, M10.3)

### 3.1 La fonte

La fonte è il record `sources` di `guildcfg` ([SPEC-03 §8](SPEC-03-data-model.md#8-impostazioni-della-gilda-guildcfg)), già fatto in M10.2: `raid` = `accord` | `fdcp`, `loot` = `none` | `fdcp`, scritto solo dagli ufficiali, uguale per tutti. M10 non cambia i suoi valori. Che cosa dipende dalla fonte `raid`:

| Dato | Con `accord` | Con `fdcp` |
|---|---|---|
| Season e dichiarazioni (MS1, MS2, OS, nota) | insieme `season` di Accord (§4) | `GetSeason()` e `GetPool()` di FDCP (livello 1) o il pulsante *Open FDCP* (livello 0); Accord non chiede e non accetta dichiarazioni proprie |
| Formazione e panchina di una serata | record `C:` di `raidev` (§7) | `GetNight()` di FDCP, in sola lettura; sul client di un membro FDCP non dà la serata (§3.3) |
| Composizione obiettivo | record `target` di `guildcfg` (§7.1) | idem: è un'impostazione di Accord, serve solo a confrontare |

Non dipendono dalla fonte: **eventi e risposte** (sempre il calendario del gioco, §5), l'**importazione di Raid-Helper** (§6, che scrive nel calendario), la **mappa della disponibilità** (§8) e i **raduni** (§9). FDCP non ha nessuno di questi dati in proprio: legge le risposte dal calendario come Accord.

**Cambio di fonte.** Passare da `accord` a `fdcp` nasconde le dichiarazioni e le composizioni di Accord ma non le cancella: tornando ad `accord` ricompaiono, con la season che era aperta. Durante una season il cambio è possibile (decide l'ufficiale), e la vista *Raid* lo dice con un avviso: "Season declarations kept in Accord stay hidden while FDCP is the source".

### 3.2 L'interfaccia dei fornitori

`Integrations:Provider("raid")` dà `Integrations.OWN` (riempito da `Data/Season.lua` in M10.3) o `ns.FDCP`. Entrambi rispondono alle stesse funzioni; `nil` vuol dire "non su questo client", mai "vuoto":

| Funzione | Risultato |
|---|---|
| `Level()` | `1` (legge), `0` (solo riconosciuto), `nil` (assente); `OWN` è sempre `1` |
| `Season()` | `{ id, name, state = "OPEN" \| "CLOSED", start }` |
| `Entries()` | `{ { name, guid?, class, role, ms1, ms2?, os?, note?, unsure?, alts? } }`: la season corrente |
| `Entry(name)` | una voce; un alt dà la voce del suo main (`viaAlt`) |
| `Lineup(eventKey)` | `{ raid = { nomi }, bench = { nomi } }` della serata legata all'evento, o `nil` |
| `CanDeclare()` | `true` solo per `OWN` con una season aperta; FDCP sempre `false` |
| `Gaps()` | che cosa manca al fornitore su questo client: `{ "ms2", "os", "avail", "night" }` (il client di un membro con FDCP) |

`UI/Season.lua` e `UI/Events.lua` leggono solo questa interfaccia. Le lacune di `Gaps()` si dicono in una riga ("FDCP shows MS2 and OS to officers only"), mai come una colonna vuota.

### 3.3 FDCP come fonte

Con `raid = fdcp` e FDCP al livello 1 (`API_VERSION == 1`): la season è quella di `GetSeason()`, il roster è `GetPool()` (mains con `ms1`, `ms2`, `os`, `role`, `status`, `alts`, `avail`; sul client di un membro solo mains attivi, senza `ms2`, `os`, `avail`), la serata è `GetNight()` (solo sul client di un ufficiale). Al livello 0 Accord mostra solo il pulsante *Open FDCP* e il nome della season se c'è. Accord non apre, chiude né cambia una season di FDCP. Che cosa servirebbe di più a FDCP è nella [richiesta all'API di FDCP](../integrations/FDCP-API-requests.md) (SPEC-10 Q10).

## 4. Il roster della season (M10.3, M10.4)

Il modello del proprietario (2026-11-19): il roster della season **non è un'iscrizione e non è un registro delle presenze**. Dice che cosa gioca ogni raider per tutta la season: **MS1** obbligatoria (specializzazione principale con il suo ruolo), **MS2** facoltativa (una seconda accettata per tutta la season, se il raid ne ha bisogno), **OS** facoltativa (una che il giocatore vorrebbe giocare, che il raid non chiederà), **una nota libera** (per esempio la disponibilità); "not sure yet" è una risposta valida. La dichiarazione vale per la season, perché il loot segue la specializzazione dichiarata. Dichiarare è facoltativo.

### 4.1 L'insieme `season`

Un insieme sincronizzato su `GUILD` come gli altri, con due tipi di record:

| Record | Id | Campi | Chi scrive |
|---|---|---|---|
| Season | `S:<n>` (`n` intero da 1, crescente) | `kind = "season"`, `n`, `name` (1–32 caratteri), `start` (giorno, `AAAAMMGG`), `closed` (ora, facoltativo) | solo ufficiali e Guild Master (NET-12, `authorAny`: resta valida se l'ufficiale perde il grado) |
| Dichiarazione | `E:<n>:<GUID>` (`GUID` = il personaggio dichiarato) | `kind = "entry"`, `n`, `class` (`classFile`), `ms1 = { spec, role }`, `ms2 = { spec, role }` (facoltativa), `os = { spec, role }` (facoltativa), `note` (0–80 caratteri), `unsure` (booleano), `first` (ora della prima scrittura) | solo l'account del personaggio (§4.2) |

Dimensione massima di un record 512 byte. Nessun altro tipo di record si accetta (`owner`).

**La season corrente** è il record `S:<n>` con `n` più alto e senza `closed`. **Aprire una season** (un ufficiale, M10.3) scrive `S:<n+1>` e chiude la precedente (`closed` = adesso) nella stessa operazione; due ufficiali che aprono insieme scrivono lo stesso id e vince la versione più recente (§3 di SPEC-02). Una season appena aperta è **vuota**: nessuna dichiarazione si copia dalla precedente. Le season chiuse restano **leggibili** (si scelgono in un menu della vista) con le loro dichiarazioni.

**Conservazione**: si tengono la season corrente e le 3 precedenti (con le loro dichiarazioni); una season più vecchia si cancella 30 giorni dopo che ne è stata aperta una quarta successiva. È la proposta di SPEC-10 Q20.

### 4.2 Regole di fiducia (SEA-01…SEA-06)

- **SEA-01 Solo la propria voce.** Una dichiarazione `E:<n>:<GUID>` si accetta solo se il suo autore è `GUID` o un personaggio dello **stesso account** con l'elenco reciproco (NET-10, [SPEC-02 §6](SPEC-02-network-protocol.md#6-fiducia-e-integrità)); con la ritrasmissione di un ufficiale (NET-11) se l'autore non è online, ma il contenuto deve comunque essere dell'autore (la `rev` e il `time` non cambiano). Una voce falsa, cioè scritta da chi non è dell'account del personaggio, si rifiuta con il motivo `owner`, e una voce di un ufficiale per un altro membro pure: **nessuno scrive la voce di un altro**, ufficiali compresi (roadmap M10.3).
- **SEA-02 Bloccata per la season.** Dopo la prima scrittura, `ms1`, `ms2`, `os`, `class` non cambiano più finché la season `n` resta la corrente: una versione con `rev` più alta che li cambia si rifiuta (`locked`), come il contenuto delle richieste in banca ([SPEC-03 §7](SPEC-03-data-model.md#7-richieste-in-banca-bankreq)). Eccezioni, proposte in SPEC-10 Q20: la voce si può correggere liberamente per **30 minuti** dopo `first` (errori di battitura; il controllo usa il `time` della versione nuova meno `first`, entrambi dell'autore, quindi è solo una regola dell'interfaccia contro gli errori, non contro un client malevolo che mente sull'ora, che resta nel limite di un'ora nel futuro di SPEC-02 §6); una voce `unsure = true` può diventare **una volta** una dichiarazione vera (allora `first` riparte); la **nota** si può cambiare sempre. `first` non cambia mai dopo, salvo il passaggio da `unsure`.
- **SEA-03 Season esistente e aperta.** Una dichiarazione per una season che non esiste ancora su questo client si tiene in attesa (fino a 10 minuti, poi si scarta; arriverà di nuovo con la sincronizzazione); per una season chiusa si accetta solo se il suo `first` è precedente a `closed` (una voce scritta prima della chiusura che arriva tardi).
- **SEA-04 Contenuto valido.** `class` del personaggio come la dà il roster; `spec` dalla tabella di `Data/Specs.lua` per quella classe; `role` uno di `tank`, `healer`, `melee`, `ranged`, ammesso per quella specializzazione (§4.3); `ms2` e `os` diverse da `ms1`; `note` senza caratteri di controllo né `|`; `unsure = true` vuol dire nessuna specializzazione obbligatoria. Altrimenti `owner`.
- **SEA-05 Una voce per account.** Un account può dichiarare un solo personaggio per season: se arrivano voci di due personaggi dello stesso account, la vista mostra quella con il `first` più vecchio (a parità, il GUID minore) e segnala l'altra all'autore, senza rifiutarla (così tutti i client mostrano la stessa, qualunque sia l'ordine di arrivo).
- **SEA-06 Con FDCP come fonte** nessuna voce si scrive (`Season:Declare` risponde `false, "source"`); le voci ricevute si accettano e si tengono (servono se si torna ad `accord`) ma non si mostrano.

### 4.3 Specializzazioni e ruoli

`Data/Specs.lua` elenca per ogni classe del gioco base i tre rami di talento con il nome in inglese (`Arms`, `Fury`, `Protection`…) e i ruoli ammessi, il primo predefinito: per esempio `Druid` `Feral` = `tank` o `melee`, `Shaman` `Enhancement` = `melee` (o `tank`, se la gilda lo vuole), `Priest` `Shadow` = `ranged`. Il ruolo si sceglie sempre nella dichiarazione, perché nel gioco base un ramo non decide il ruolo. La classe viene dal roster, non si sceglie. Le classi assenti su Forever (per esempio quelle di espansioni successive) non compaiono; una classe nuova del client che la tabella non conosce si può dichiarare solo con `unsure`. I nomi dei rami si confermano nel client in M10.10.

### 4.4 La propria dichiarazione

Nella vista *Season*, con una season aperta e `raid = accord`: classe (dal roster), MS1 con il ruolo, MS2, OS, nota, oppure *Not sure yet*. Sotto, il testo: "Your declaration holds for the whole season: loot follows the declared spec." Prima del salvataggio una conferma ripete il blocco. Dopo i 30 minuti di correzione la voce si mostra bloccata, con la data. Senza una season aperta la vista dice che gli ufficiali non ne hanno aperta una.

### 4.5 Conteggi per gli ufficiali (M10.4)

Dalla fonte scelta, per la season corrente:

- per ruolo (tank, healer, melee, ranged) i raider con quel ruolo in **MS1**; accanto, quanti ne **aggiungerebbe MS2** (raider con MS2 in quel ruolo e MS1 in un altro);
- le **mancanze** rispetto alla composizione obiettivo (§7.1): per ogni ruolo `obiettivo − MS1`, e quante ne coprirebbe MS2;
- i membri **senza dichiarazione** (con l'addon o no) in un elenco a parte, mai contati come mancanza; i *Not sure yet* a parte anche loro.

Tutti i membri vedono l'elenco delle dichiarazioni (nome, classe, MS1, MS2, OS, nota). I conteggi e le mancanze li vedono tutti: sono numeri del roster, non dati riservati.

### 4.6 Esportazione

Un testo pronto per Discord (con le parti di [SPEC-12 §6](SPEC-12-officer-tools.md#6-esportazioni-m86): blocchi sotto il limite di un messaggio), e un CSV con colonne `name`, `realm`, `class`, `role`, `ms1`, `ms2`, `os`, `unsure`, `note`, `declared_date`, nella casella di copia (`UI/ExportBox.lua`). Come le esportazioni di M8, sopra la casella c'è l'avviso che il testo esce dal gioco.

## 5. Eventi e iscrizioni sul calendario del gioco (M10.5)

### 5.1 Che cosa dice il dump

Verificato il 2026-11-25 sul dump di Forever `1.60.1` (build 70170, `../WoW-Addons/docs/api.json`, solo consultato). `C_Calendar` c'è, completo:

| Uso | Funzioni ed eventi |
|---|---|
| Caricare | `C_Calendar.OpenCalendar()`; evento `CALENDAR_UPDATE_EVENT_LIST` |
| Eventi di gilda | `GetNumGuildEvents()`, `GetGuildEventInfo(i)` → `CalendarGuildEventInfo` (`eventID`, `year`, `month`, `monthDay`, `hour`, `minute`, `eventType`, `title`, `calendarType`, `inviteStatus`, `clubID`); `CALENDAR_UPDATE_GUILD_EVENTS` |
| Un giorno | `GetMonthInfo(offset)`, `GetNumDayEvents(offset, day)`, `GetDayEvent(offset, day, i)` → `CalendarDayEvent` (anche `inviteType`, `modStatus`, `isLocked`); `GetEventIndexInfo(eventID, monthOffset, monthDay)` |
| Aprire un evento | `OpenEvent(offset, day, i)` → `success`; `GetEventInfo()` → `CalendarEventInfo` (`title`, `description`, `creator`, `eventType`, `time`, `isLocked`, `inviteStatus`, `inviteType`, `calendarType`); `CloseEvent()`; eventi `CALENDAR_OPEN_EVENT`, `CALENDAR_CLOSE_EVENT`, `CALENDAR_UPDATE_EVENT` |
| Risposte | `GetNumInvites()`, `EventGetInvite(i)` → `CalendarEventInviteInfo` (`name`, `classFilename`, `inviteStatus`, `modStatus`, `inviteIsMine`, `type`, `guid`); `CALENDAR_UPDATE_INVITE_LIST(hasCompleteList)` |
| Rispondere | `EventSignUp()` (evento di iscrizione), `EventAvailable()` (accetta un invito), `EventTentative()`, `EventDecline()`; `EventGetStatusOptions(i)` |
| Creare e cambiare (ufficiali, §6.5) | `CanAddEvent()`, `CreateGuildSignUpEvent()`, `EventSetTitle`, `EventSetDescription`, `EventSetDate(month, day, year)`, `EventSetTime(hour, minute)`, `EventSetType`, `AddEvent()`, `EventCanEdit()`, `UpdateEvent()`, `CanSendInvite()`, `EventInvite(name)`, `EventSetInviteStatus(i, status)`, `EventRemoveInviteByGuid(guid)`, `CanEditGuildEvent()` (globale) |
| Stato e errori | `IsActionPending()`, `CALENDAR_ACTION_PENDING(pending)`, `CALENDAR_UPDATE_ERROR(errorReason)`, `…_WITH_COUNT`, `…_WITH_PLAYER_NAME` |

I valori di `Enum.CalendarStatus` **non sono nel dump** (solo il nome del tipo). Si usano quelli del client moderno, gli stessi che legge FDCP: 0 invitato, 1 disponibile, 2 rifiutato, 3 confermato, 4 fuori, 5 riserva, 6 iscritto, 7 non iscritto, 8 forse **[verificare]**. Accord li riduce a tre risposte come FDCP: **sì** = 1, 3, 6; **forse** = 5, 8; **no** = 2, 4; 0 e 7 = nessuna risposta. Anche `CalendarEventType` (raid = 0) è un valore del client moderno **[verificare]**.

### 5.2 Leggere

- Al primo `PLAYER_ENTERING_WORLD` con l'interruttore acceso, `OpenCalendar()` (una volta: lo fa anche FDCP e l'interfaccia del gioco); a ogni `CALENDAR_UPDATE_EVENT_LIST` e `CALENDAR_UPDATE_GUILD_EVENTS` si rilegge l'elenco degli **eventi di gilda dei prossimi 14 giorni** e dei 7 passati, chiunque li abbia creati, con `GetGuildEventInfo`.
- Le **risposte** di un evento si leggono aprendolo (`OpenEvent` → `GetNumInvites` → `EventGetInvite` → `CloseEvent`) solo quando la vista *Events* mostra quell'evento o un ufficiale lo confronta (§6.3), mai per tutti gli eventi in sottofondo.
- **L'evento aperto è uno solo per il client**, condiviso con la finestra del calendario del gioco e con gli altri addon. Accord non apre un evento mentre la finestra del calendario è visibile (`CalendarFrame:IsShown()`) o `IsActionPending()` è vero, e richiude sempre l'evento che ha aperto; se la finestra del gioco si apre a metà, Accord smette e riprova dopo.
- Niente si legge in combattimento o durante un boss (§10).
- Un evento si identifica con la chiave `c<eventID>`; il titolo e le risposte non si salvano né si mandano: si rileggono dal calendario.

### 5.3 Rispondere da Accord

Dalla vista *Events*, un clic del giocatore su **Sign up**, **Tentative** o **Decline**: Accord apre l'evento, chiama `EventSignUp()` (evento di iscrizione di gilda) oppure `EventAvailable()` (invito), `EventTentative()` o `EventDecline()`, aspetta `CALENDAR_UPDATE_INVITE_LIST` o `CALENDAR_UPDATE_ERROR`, richiude e mostra l'esito. Così **la stessa risposta** è nel calendario del gioco, in FDCP e negli altri client. Una risposta data nella finestra del gioco compare in Accord alla rilettura. Le chiamate partono solo da un clic **[verificare]**: se il client le rifiuta da un addon (azione protetta), il pulsante apre la finestra del calendario del gioco su quell'evento e lo dice.

**Il ruolo** non ha un posto nel calendario del gioco (nessuna funzione scrive la nota di un invito). Accord lo tiene in un record suo (`R:`, §5.5), preselezionato da MS1 o, se MS1 è già coperta e un ruolo manca, da MS2; il giocatore lo cambia. Un membro senza dichiarazione può iscriversi lo stesso (ruolo dalla classe).

### 5.4 Il ripiego solo nell'addon

**Solo** quando il client non ha un calendario usabile (capacità `calendar` di Compat: `C_Calendar` assente, oppure nessun `CALENDAR_UPDATE_EVENT_LIST` entro 60 s da `OpenCalendar`), un ufficiale può creare un evento nell'addon, e i membri rispondono nell'addon. Questi eventi sono sempre segnati **"Not in the game calendar"**, anche sui client che il calendario ce l'hanno. Con `loot = fdcp`, l'evento mostra in più: "FDCP reads sign-ups from the game calendar only: answers here do not count for FDCP". Quando il calendario torna usabile, Accord non crea più eventi propri e suggerisce all'ufficiale di creare l'evento nel gioco (§6.5 lo fa per un'importazione).

### 5.5 L'insieme `raidev`

Gli eventi del calendario non si copiano: `raidev` tiene solo ciò che il calendario non può tenere.

| Record | Id | Campi | Chi scrive | Scadenza |
|---|---|---|---|---|
| Ruolo per un evento | `R:<chiave>:<GUID>` | `role`, `spec` (`ms1` \| `ms2` \| `class`) | l'account del personaggio | 2 giorni dopo l'evento |
| Evento solo dell'addon (§5.4) | `F:<GUID>:<n>` | `title` (1–48), `start` (ora del server), `size` (5–40), `note` (0–120) | solo ufficiali | 2 giorni dopo l'inizio |
| Risposta a un evento solo dell'addon | `A:<chiave>:<GUID>` | `answer` = `yes` \| `maybe` \| `no`, `role` | l'account del personaggio | come l'evento |
| Importazione di Raid-Helper (§6) | `H:<id dell'evento Discord>` | `title`, `start`, `at` (ora dell'importazione), `s` = `{ { g = GUID, st, role, class, spec } }` (al massimo 80) | solo ufficiali | 2 giorni dopo `start` |
| Composizione (§7) | `C:<chiave>` | `raid = { GUID }`, `bench = { GUID }` (al massimo 40 + 40) | solo ufficiali | 2 giorni dopo l'evento |

La chiave di un evento è `c<eventID>` (calendario) o `f<GUID>:<n>` (solo addon). Fiducia: `R:` e `A:` come SEA-01 (prima mano o ritrasmissione di un ufficiale, mai la voce di un altro); `F:`, `H:` e `C:` NET-12 con `authorAny`. Dimensione massima 2 KB (`H:` con 80 iscritti). Nessuno di questi record dice chi c'era a un raid (RAID-05): una composizione è un piano, non una presenza, e scade con l'evento.

## 6. Gli eventi di Raid-Helper da Discord (M10.6)

La gilda del proprietario raccoglie le iscrizioni ai raid con il bot Raid-Helper in un canale forum di Discord (2026-11-24). Accord non contatta mai Discord né Raid-Helper (RAID-07, [ADR 0001](../adr/0001-client-only-addon-guild-only-data.md)): un ufficiale copia l'esportazione dell'evento e la incolla in una casella di Accord.

### 6.1 I formati

**JSON.** Dalla documentazione pubblica dell'API di Raid-Helper (letta il 2026-11-25): l'indirizzo `https://raid-helper.xyz/api/v4/events/<id>` dà i dati completi di un evento **senza autorizzazione**, quindi un ufficiale lo apre nel browser e copia il testo. Campi dell'evento: `id`, `serverId`, `leaderId`, `leaderName`, `channelId`, `channelName`, `title`, `description`, `startTime`, `endTime`, `closingTime` (ore Unix), `date`, `time` (testo), `classes`, `roles`, `signUps`, `lastUpdated`. I campi di **ogni iscrizione** non sono descritti nella pagina pubblica; da esportazioni note sono `name` (il nome mostrato sul server Discord), `userId`, `className`, `specName`, `roleName`, `status`, `entryTime`, `position`, e gli stati speciali sono classi finte: `className` = `Tentative`, `Late`, `Bench`, `Absence` **[verificare]** con un'esportazione vera all'inizio di M10.6. Si accetta anche la forma precedente (`/api/v2/events/<id>`) se ha gli stessi campi.

**CSV.** Il sito di Raid-Helper esporta un evento anche in CSV; le colonne si riconoscono **dall'intestazione** (maiuscole e spazi ignorati): servono un nome (`name`, `discord name`, `user`) e almeno uno tra classe, ruolo o stato; le colonne sconosciute si ignorano **[verificare]** con un'esportazione vera.

**Regole del lettore** (`Data/RaidHelper.lua`): un lettore JSON e CSV scritto per Accord, che **non esegue mai nulla** del testo (nessun `loadstring`); testo al massimo 200 KB, profondità JSON al massimo 8, al massimo 200 iscrizioni, ogni testo tagliato a 64 caratteri e ripulito (nessun carattere di controllo, `|` raddoppiato); campi sconosciuti ignorati. Un testo che non capisce si rifiuta con un messaggio chiaro ("This is not a Raid-Helper event export: …") e nulla si salva.

| Stato di Raid-Helper | Risposta in Accord |
|---|---|
| iscritto con una classe vera (`primary`) | **sì** |
| `Late` | **sì**, segnato *late* |
| `Bench` | **sì**, segnato *bench* (un'indicazione: la panchina la decide la composizione, §7) |
| `Tentative` | **forse** |
| `Absence` | **no** |

### 6.2 Chi importa

Solo ufficiali e Guild Master (SPEC-10 Q21, `Raid.WRITERS = "officers"`, un solo punto). L'importazione è legata a un giorno e un'ora (da `startTime`); un'importazione nuova dello stesso evento Discord (`id`) sostituisce la precedente.

### 6.3 Abbinamento per nome Discord

Ogni iscrizione si abbina a un **account** della gilda, nell'ordine:

1. un abbinamento a mano già fatto da questo ufficiale per quel nome (§6.4);
2. il nome Discord dei contatti di M2.5 (il nome scritto dal giocatore o il campo `discordInfo` del gioco, [SPEC-05](SPEC-05-roster-alts-contacts.md)), confrontato senza maiuscole, spazi esterni, `@` iniziale e discriminatore `#0000`;
3. il nome di un personaggio della gilda uguale al nome Discord (molti usano il nome del main come soprannome).

Raid-Helper mostra il **soprannome sul server**, che può essere diverso dal nome utente scritto in Accord: per questo il punto 1 conta più degli altri. Un nome che abbina più account non si abbina (va a mano). Gli account si raggruppano con gli alt ([SPEC-05](SPEC-05-roster-alts-contacts.md)): l'iscrizione va al personaggio dell'account con la classe dell'iscrizione, poi a quello della dichiarazione della season, poi al main. I nomi che non abbinano nessuno vanno in un elenco che l'ufficiale abbina a mano.

### 6.4 Che cosa resta e dove

- Il record `H:` (sincronizzato su `GUILD`) contiene **solo i membri abbinati** (GUID, stato, ruolo, classe, specializzazione) e l'ora dell'importazione. Ogni membro vede il proprio stato su Discord.
- I **nomi non abbinati** e gli **abbinamenti a mano** restano sul computer dell'ufficiale che importa (`GuildKey:Data().raidHelper`), mai mandati: i primi si cancellano quando l'evento è passato da 2 giorni, i secondi restano per gli eventi seguenti finché il nome non abbina più un membro della gilda (SPEC-10 Q22). Così Accord non tiene dati di persone fuori dalla gilda oltre a quei nomi, e solo per la durata dell'evento.

Gli ufficiali vedono, accanto all'importazione: la composizione per ruolo accanto al roster della season; **chi è iscritto su Discord ma non nel calendario del gioco**; **chi è iscritto nel calendario ma non su Discord**.

### 6.5 Nel calendario del gioco

Con **una conferma** dell'ufficiale ("Create the event in the game calendar and invite N members?"), Accord:

1. se l'evento del giorno non c'è, lo crea: `CreateGuildSignUpEvent()`, `EventSetTitle`, `EventSetDescription` (il testo "Imported from Raid-Helper"), `EventSetDate`, `EventSetTime`, `EventSetType` (raid), `AddEvent()`; se c'è (stesso giorno e ora, creato dall'ufficiale o modificabile, `EventCanEdit()`), lo usa;
2. per i membri abbinati che non hanno risposto nel calendario: `EventInvite(nome)` se l'evento è a invito, e `EventSetInviteStatus(i, stato)` (**sì** → confermato 3, **forse** → forse 8, **no** → rifiutato 2) **solo** dove il client lo permette a quell'ufficiale (`CanEditGuildEvent()`, `EventCanEdit()`, `EventGetStatusOptions(i)` che contiene lo stato) **[verificare]**;
3. **non cambia mai una risposta che il membro ha già dato nel calendario**: la risposta del gioco vince e la differenza si mostra (SPEC-10 Q25);
4. una chiamata alla volta, aspettando `CALENDAR_ACTION_PENDING(false)` o un errore, al massimo 40 inviti per conferma; un errore ferma la serie e la vista dice chi è rimasto fuori.

Se il client non permette di scrivere lo stato degli altri, Accord crea l'evento e manda gli inviti, e i membri abbinati trovano nel **Centro azioni** una riga "Sign up in the game calendar for <evento>" (fornitore di M9.2), che apre la vista sull'evento. FDCP collega a una serata il **primo evento raid del giorno**, quelli di gilda prima: se il giorno ha già un altro evento raid, la conferma lo dice ("FDCP links the first raid event of the day").

### 6.6 Ritorno a Discord

La composizione decisa nel gioco (§7) si esporta come testo da incollare su Discord, con l'esportazione di §4.6.

## 7. Panchina e composizione (M10.7)

### 7.1 Composizione obiettivo

Un secondo record di `guildcfg`, id `target`: `size` (10, 20, 25 o 40), `tank`, `healer`, `melee`, `ranged` (interi, somma ≤ `size`). Lo scrivono solo gli ufficiali (come `sources`), vale per tutta la gilda; senza record nessuna mancanza si calcola. `Integrations.ValidRecord` accetta `sources` **o** `target`, ciascuno con i suoi campi.

### 7.2 Con Accord come fonte

Per un evento, un ufficiale mette gli iscritti (**sì** e **forse** del calendario, più gli abbinati di un'importazione) nel **raid** o in **panchina**. Accanto, la composizione per ruolo (dai ruoli del record `R:`, altrimenti MS1) contro l'obiettivo; quando un ruolo manca, la vista propone chi ha **MS2** in quel ruolo. Solo gli ufficiali cambiano la composizione (record `C:`, NET-12); ogni membro vede dove è stato messo. Facoltativo, con una conferma come §6.5: scrivere nel calendario **confermato** (3) per il raid e **riserva** (5) per la panchina, così FDCP vede la stessa formazione (FDCP conta la riserva come "forse").

### 7.3 Con FDCP come fonte

La formazione e la panchina della serata sono di FDCP (`GetNight()`, sola lettura, già fatto in M11.7); Accord non offre una panchina sua e non accetta record `C:` scritti in quel periodo (`source`). Sul client di un membro FDCP non dà la serata: la vista lo dice e rimanda a FDCP.

## 8. Mappa della disponibilità (M10.8)

### 8.1 Che cosa si misura

**Solo la presenza online** del proprio account: ogni client conta i minuti in cui un personaggio dell'account è connesso, per ora della settimana (168 caselle, ora del reame), nelle ultime **8 settimane** (`AzerothAccordDB.avail`, per account e non per gilda). Nient'altro: non dove si trova il giocatore, non che cosa fa, non se era a un raid (RAID-05). I personaggi di altre gilde contano, perché dicono quando la persona gioca.

### 8.2 L'insieme `avail`

Un record per personaggio che scrive (`id` = il suo GUID), con `p` = le 168 caselle ridotte a 4 livelli (0: mai; 1: meno di una settimana su quattro; 2: fino a metà; 3: più della metà), in 42 byte codificati, e `w` = il numero di settimane misurate. Si pubblica al più una volta al giorno e solo se `p` è cambiato; conservazione 30 giorni. La vista unisce per account (il record più recente). Prima mano o ritrasmissione di un ufficiale; un record di un altro account si rifiuta (`owner`). Costo: circa 70 byte per account al giorno.

### 8.3 Chi condivide e chi vede

Proposta in SPEC-10 Q23: condivisione **accesa di default**, con l'interruttore *Share when I usually play* nelle Impostazioni e in *What I share* (M7.6); spenta, il client manda un record vuoto che ritira quello vecchio e non pubblica più (il conteggio locale continua, per mostrarlo al giocatore). Tutti vedono la mappa della gilda come **conteggi per casella** ("12 members usually online"); il dettaglio per membro (chi c'è in una casella) lo vedono gli ufficiali e il Guild Master, e ognuno il proprio (`Availability.NAMES_VISIBLE_TO = "officers"`, un solo punto). Con FDCP come fonte, gli ufficiali vedono in più i giorni dichiarati in FDCP (`avail`), etichettati come dichiarazione, non come misura.

## 9. Raduni PvP e nel mondo (M10.9)

Una chiamata veloce: "PvP at the crossroads in 15 minutes", con le risposte **coming** / **not coming**.

- **L'insieme `rally`**, **volatile** e **solo di prima mano** come `groups` ([SPEC-13 §6.2](SPEC-13-action-center-notices.md#62-linsieme-groups)): fuori dai riepiloghi della sincronizzazione, mai ritrasmesso da un ufficiale. Record `<GUID>:<n>` del chiamante: `kind` = `pvp` | `world`, `text` (il punto d'incontro **in parole**, 1–60 caratteri), `start` (da adesso a 2 ore), `until` (`start` + da 15 minuti a 2 ore). Risposte: record `<id del raduno>:<GUID>` del giocatore che risponde, con `answer` = `yes` | `no`. Chi arriva dopo chiede i raduni aperti con un `GASK` dello stesso tipo di M9.6 (`k = "rally"`).
- **Scade da solo**: ogni client lo chiude a `until` e lo cancella 10 minuti dopo, senza bisogno di un messaggio; il chiamante può chiuderlo prima.
- **Nessuna coordinata**: Accord non legge mai la posizione del giocatore (nessuna chiamata a `C_Map.GetPlayerMapPosition` o simili) e non manda mai coordinate né mappe; il punto d'incontro è solo il testo che il chiamante scrive.
- Chi può: ogni membro con l'addon (SPEC-10 Q24); un raduno aperto per personaggio, al massimo 4 all'ora; solo il chiamante lo cambia o lo chiude.
- Un avviso (modulo `rally` di [SPEC-13 §3.2](SPEC-13-action-center-notices.md#32-moduli-tipi-e-interruttori), acceso di default solo come riga in chat) e una riga nel Centro azioni finché è aperto; si rispetta il silenzio di §10 e le ore di quiete.

## 10. Silenzio durante i boss

Come FDCP, Accord **non manda nulla** durante un incontro con un boss: da `ENCOUNTER_START` a `ENCOUNTER_END` (entrambi nel dump), o finché `C_InstanceEncounter.IsEncounterInProgress()` (o la globale `IsEncounterInProgress`) è vero, la coda di `Transport` trattiene i messaggi `NORMAL` e `BULK`; restano solo le risposte `ALERT` brevi già previste (NET-05). Le chiamate a `C_Calendar` e la lettura delle risposte aspettano la fine del combattimento. La regola vale per tutto il traffico di Accord, non solo per M10; si aggiunge in M10.5 alla capacità `Encounter` già presente in `Compat.RESTRICTION_KINDS`.

## 11. Traffico

Stima per una gilda di 50 client (lo scenario di [SPEC-02 §4](SPEC-02-network-protocol.md#4-sincronizzazione)): dichiarazioni una volta per season (circa 200 byte ciascuna); ruoli per evento circa 60 byte a iscritto; un'importazione al massimo 2 KB per evento; disponibilità circa 70 byte per account al giorno; raduni come gli annunci di gruppo. In media meno di **20 B/min** per client oltre al traffico di oggi, da misurare nel simulatore in M10.3 (season), M10.5 (eventi) e M10.8 (disponibilità). Il budget condiviso è in [SPEC-09 §7](SPEC-09-quality-release.md#7-budget-di-traffico-condiviso-m10).

## 12. Test per passo

| Passo | File | Casi |
|---|---|---|
| M10.3 | `Tests/test_season.lua` | aprire una season (solo ufficiali) chiude la precedente; una nuova season è vuota e la vecchia resta leggibile; una voce non cambia dopo i 30 minuti (`locked`), la nota sì, `unsure` diventa dichiarazione una volta; una voce falsa di un altro account o di un ufficiale per un altro membro si rifiuta (`owner`); contenuto non valido; due personaggi dello stesso account (SEA-05); con FDCP come fonte nessuna voce si scrive; conservazione delle 4 season; interruttore spento |
| M10.4 | `Tests/test_season_view.lua` | conteggi per ruolo da MS1, copertura di MS2, mancanze contro l'obiettivo; chi non ha dichiarato è a parte; stessi conteggi dalla fonte FDCP (client finto di FDCP); esportazione CSV e Discord |
| M10.5 | `Tests/test_calendar.lua` | client finto di `C_Calendar`: eventi di gilda letti chiunque li abbia creati; la risposta da Accord è la stessa nel calendario; una risposta data nel gioco compare; nessuna apertura con la finestra del calendario visibile o un'azione in corso; ripiego solo senza calendario e segnato; un membro senza dichiarazione si iscrive; silenzio durante un boss |
| M10.6 | `Tests/test_raid_helper.lua` | campioni JSON e CSV con nomi inventati; ogni stato; campi sconosciuti ignorati; testo rotto, troppo lungo o troppo profondo rifiutato; abbinamento per nome Discord tra alt; abbinamento a mano ricordato; nomi non abbinati mai mandati; chiamate al calendario con e senza permesso, una risposta già data non cambiata |
| M10.7 | `Tests/test_composition.lua` | solo ufficiali scrivono la composizione; ogni membro vede dove è; proposta di MS2; con FDCP come fonte nessuna composizione si scrive |
| M10.8 | `Tests/test_availability.lua` | solo minuti online; 8 settimane; livelli; interruttore spento ritira; nessun dato di presenza ai raid in nessun record |
| M10.9 | `Tests/test_rallies.lua` | scadenza da soli; nessuna coordinata nei messaggi; limiti per personaggio; volatile e solo prima mano |

## 13. Cosa resta da verificare nel client

Nella prova di M10.10 (`docs/checklists/M10.md`), con una gilda che ha FDCP e una senza:

- i valori di `Enum.CalendarStatus` e `CalendarEventType`, che il dump non ha;
- se `EventSignUp`, `EventAvailable`, `EventTentative`, `EventDecline` funzionano chiamati da un addon (dal clic) o sono protetti;
- se un ufficiale può creare un evento di iscrizione di gilda e scrivere lo stato di un altro membro (`EventSetInviteStatus`) su Forever;
- se gli eventi di gilda si caricano senza aprire la finestra del calendario;
- il formato attuale dell'esportazione JSON e CSV di Raid-Helper (campi di un'iscrizione, stati speciali);
- i nomi dei rami di talento di ogni classe su Forever;
- che FDCP veda come iscrizione la risposta data da Accord, e la formazione confermata o in riserva.
