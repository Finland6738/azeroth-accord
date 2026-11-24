# SPEC-12: Strumenti per ufficiali

Specifica della milestone M8 ([roadmap](../roadmap/M8-officer-tools.md)): gli ufficiali vedono cosa è successo nel roster nel tempo, quali **account** sono inattivi (contando gli alt) e preparano una lista di azioni da fare **a mano** nella finestra del gioco. L'addon non promuove, non degrada, non espelle e non cambia note: osserva e suggerisce ([ADR 0023](../adr/0023-officer-tools-observe-and-suggest-officer-data-stays-among-officers.md)). Ogni sezione dice il passo che la realizza; i passi M8.2–M8.6 non hanno scelte di progetto da fare oltre a queste.

Nomi di codice, campi e testi dell'interfaccia in inglese (con la traduzione italiana nel file di lingua `itIT.lua`, [ADR 0015](../adr/0015-interface-and-documentation-languages.md)). Le ore sono ore del server in secondi (`Compat.ServerTime()`); un **giorno** è il giorno UTC, scritto come numero `AAAAMMGG` (lo stesso formato degli id del co-play).

## 1. Chi vede cosa e dove vanno i dati degli ufficiali

### 1.1 Ruoli

"Ufficiale" ha lo stesso significato di oggi ([SPEC-00 §5](SPEC-00-vision-scope.md#5-ruoli)): per il proprio personaggio `Role:IsOfficer()` (ufficiale o GM), per gli altri il grado nel roster con "ascolta la chat ufficiali" (`Compat.Guild.RankIsOfficer`, regola NET-11). Il GM è un ufficiale; nessuna funzione di M8 è solo del GM.

| Dato | Ufficiali e GM | Membri | Dove si salva |
|---|---|---|---|
| Cronologia del roster (§2) | sì: pagina Timeline e scheda del membro | no | archivio della gilda, insieme `timeline` |
| Inattività per account (§3), fasce | sì: pagina Inactive | no (neppure la propria) | calcolata, mai salvata; le fasce nell'insieme `ocfg` |
| Assenza dichiarata (§3.4) | sì, di tutti | solo la **propria** (quella dichiarata dal proprio account) | insieme `absence` |
| Revisione guidata e coda delle azioni manuali (§4) | sì, la **propria** coda | no | solo su questo computer (`GuildKey:Data().officer`) |
| Note estese (§5) | sì | no, mai | insieme `onotes` |
| Esportazioni (§6) | sì | no | nessuna: testo in una casella da copiare |

Le scelte di visibilità sono **proposte** in attesa della risposta del proprietario ([SPEC-10 Q13](SPEC-10-risks-open-questions.md#2-domande-aperte-per-il-proprietario)) e stanno in un punto solo, `Officer.VISIBLE_TO` (tabella `{ timeline, inactivity, absences, notes, export }` → `"officers"` o `"members"`), come `Social.OTHERS_VISIBLE_TO` per Q3.

### 1.2 Insiemi solo per ufficiali

M8 aggiunge quattro insiemi a `Store.SETS` (in coda a `Store.SET_ORDER`, nell'ordine `timeline`, `absence`, `onotes`, `ocfg`). Sono tutti **riservati** (`restricted` vero per ogni record, come le schede della banca lette da un ufficiale, BANK-02) e portano il nuovo campo di definizione `officerTool = true`:

| Insieme | Id | Contenuto | Autore ammesso | `maxBytes` | Conservazione |
|---|---|---|---|---|---|
| `timeline` | `<GUID osservatore>:<giorno>:<p>` (`p` = 1–4) | eventi osservati da un ufficiale in un giorno (§2.2) | l'osservatore stesso (`author == observer`), ufficiale | 8192 | 365 giorni dal `day` |
| `absence` | `<GUID personaggio>:self` oppure `<GUID personaggio>:off` | assenza con data di rientro (§3.4) | `:self` l'account del personaggio; `:off` un ufficiale | 256 | 30 giorni dopo `until` (o dopo `time` se `until = 0`) |
| `onotes` | `<GUID personaggio>` | nota estesa (§5) | un ufficiale | 1280 | la cancellazione (testo vuoto) scade dopo 60 giorni |
| `ocfg` | `tiers` | fasce dell'inattività (§3.3) | un ufficiale | 256 | nessuna |

Regole di fiducia (in aggiunta a [SPEC-02 §6](SPEC-02-network-protocol.md#6-fiducia-e-integrità)):

- **OFF-01** Un client che non è di un ufficiale rifiuta ogni record di questi insiemi da chiunque arrivi (`restricted`), tranne i **propri** `absence` `:self` che scrive lui stesso (§3.4).
- **OFF-02** Un ufficiale accetta un record di questi insiemi solo se il **mittente** è ufficiale nel proprio roster; l'autore deve essere stato ufficiale quando l'ha scritto ma non serve che lo sia ancora (`authorAny = true`: la storia osservata, una nota e la scelta delle fasce restano valide dopo la retrocessione del loro autore). Unica eccezione: un `absence` `:self` si accetta anche di prima mano, da un mittente dell'account del personaggio (NET-10), solo in `WHISPER`.
- **OFF-03** La regola del proprietario di ogni insieme controlla forma e campi (§2.2, §3.3, §3.4, §5.1); un record che non la rispetta si rifiuta (`owner`).
- Un client precedente ignora un insieme che non conosce (SPEC-02 §6): non tiene questi record e non li conta come rifiutati.

### 1.3 Dove viaggiano

- **OFF-04** I record di questi insiemi viaggiano **solo** su `OFFICER` o in `WHISPER` a un personaggio che è ufficiale nel roster di chi invia. Mai su `GUILD`, mai in `WHISPER` a un membro. Unica eccezione: l'`absence` `:self` di un membro va in `WHISPER` dal suo account a un ufficiale (§3.4): sono dati del membro stesso, non degli ufficiali.
- **OFF-05** Il controllo si fa due volte: quando `Sync` prepara il messaggio e quando `Transport` lo manda davvero (opzione `officerOnly = true`): se in quel momento la distribuzione è `GUILD`, o il destinatario del whisper non è ufficiale nel roster (per esempio è stato retrocesso mentre il messaggio aspettava in coda), il messaggio si scarta e si conta come `officerOnly` in `/accord debug`. Un messaggio `officerOnly` non si salva nella coda di uscita alla disconnessione (`AzerothAccordCharDB.outbox`): la sincronizzazione lo ripara alla prossima sessione.
- **OFF-06** Questi record **non entrano** nel riepilogo `HELLO`/`BHELLO` su `GUILD` né nel riepilogo `s` di `OHELLO` (che resta quello delle schede riservate della banca, così un ufficiale con un client precedente non vede differenze che non capisce). Hanno un riepilogo proprio, il campo nuovo **`m`** di `OHELLO` (§1.4).
- I backup personali (M7.5) non li contengono mai; il pannello "Cosa condivido" (M7.6) li elenca (§7).

### 1.4 Il canale degli ufficiali non ancora provato (S5)

Il canale `OFFICER` è **provato** quando il client, in questa sessione, ha visto un messaggio addon arrivare su `OFFICER` (la propria eco o quello di un altro): la capacità `officerAddonChannel` di `Compat` è `available` ([SPEC-02 §5](SPEC-02-network-protocol.md#5-coda-e-lockdown)). La prova vale per la sessione: a ogni accesso si rifà (il primo `OHELLO` dell'ufficiale, 10–130 s dopo l'accesso, la dà con la sua eco).

- **OFF-07** Finché il canale non è provato, i dati di questi insiemi **restano su questo computer**: si scrivono nell'archivio della gilda (`AzerothAccordDB`, quindi li vedono anche gli altri personaggi ufficiali dello stesso account) e non partono. **Nessun ripiego** su `WHISPER` tra ufficiali (a differenza del salt dei like, [SPEC-07 §2.1](SPEC-07-reputation-social.md#21-il-segreto-e-il-notaio-datanotarylua-m41)) e mai su `GUILD`. Unica eccezione: l'`absence` `:self` che un membro manda a un ufficiale in whisper (§3.4), che non dipende da S5.
- **OFF-08** Il riepilogo `m` parte comunque in ogni `OHELLO` (è un riepilogo di hash, non contiene dati); i record partono solo da un client con il canale provato. Chi riceve un `OHELLO` lo ha ricevuto su `OFFICER`, quindi ha il canale provato: può rispondere in whisper con i record che mancano al mittente (§1.5).
- **OFF-09** Le modifiche locali fatte prima della prova **non** si rimandano tutte alla prova: entrano nel riepilogo `m` e arrivano agli altri ufficiali con il confronto dei riepiloghi (§1.5), come ogni altra differenza.
- Il testo dell'interfaccia, accanto a ogni dato di questi insiemi scritto da questo client: `Only on this computer until the officer channel works.` / `Solo su questo computer finché il canale degli ufficiali non funziona.` La pagina Inactive e la scheda del membro mostrano lo stato del canale (`Officer channel: working` / `not proven yet`).

### 1.5 Sincronizzazione tra ufficiali

Gli ufficiali possono passarsi ogni record di questi insiemi (NET-11), quindi il riepilogo `m` non è per autore ma per **gruppo**:

| Insieme | Gruppo | Gruppi al massimo |
|---|---|---|
| `timeline` | `timeline:<AAAAMM>` (il mese del `day` del record) | 13 |
| `onotes` | `onotes:<n>`, `n` = `Hash.Fast(GUID del personaggio) % 32` | 32 |
| `absence` | `absence` | 1 |
| `ocfg` | `ocfg` | 1 |

- Ogni gruppo è una voce di 11 byte come quelle del riepilogo per autore ([SPEC-02 §4](SPEC-02-network-protocol.md#4-sincronizzazione)): chiave = hash a 32 bit del nome del gruppo, digest dei suoi record (insieme, id, `rev`, `time`) e ora del record più recente. Al massimo 47 voci, circa 520 B: l'`OHELLO` resta piccolo. `Sync:Groups` tiene una terza classe di gruppi accanto a `[false]` e `[true]`, aggiornata record per record come le altre (M7.7).
- Un ufficiale che riceve un `OHELLO` con `m` ed è **più avanti** in un gruppo manda in `WHISPER` al mittente tutti i record di quel gruppo, solo se è l'**ufficiale designato** per quel mittente (la regola di oggi: il più piccolo hash di GUID dell'ufficiale e GUID del mittente tra gli ufficiali sentiti di recente), dopo 0,5–3 s, chiave di coda `O|<mittente>`, `officerOnly`. I record si dividono in `REC` di al massimo circa 2,5 KB (`Sync.REC_BYTES`; un record di `timeline` più grande va da solo, sotto i 16 KB del codec).
- Un `OHELLO` senza `m` (client precedente) non riceve mai record di questi insiemi.
- Le modifiche locali di un ufficiale con il canale provato escono come `REC` su `OFFICER`: `onotes`, `absence` e `ocfg` dopo i 5 s di sempre (`Sync.BATCH`); `timeline` al massimo **una volta ogni 10 minuti** (`Timeline.PUBLISH_EVERY = 600`), perché il record del giorno cresce a ogni evento e si rimanda intero.
- **Budget** (aggiunto al simulatore in M8.2, `Tests/test_sync_sim.lua` con 5 ufficiali che osservano 30 eventi al giorno): il traffico di questi insiemi resta sotto **150 B/min in media per ufficiale** e il client più carico resta entro i 2 KB/min di SPEC-02 §4; nessun record di questi insiemi passa su `GUILD` o in whisper a un membro (il simulatore lo controlla su ogni messaggio).

### 1.6 Un ufficiale retrocesso

- **OFF-10** I dati degli ufficiali sono dell'**account** (l'archivio della gilda in `AzerothAccordDB`). Si cancellano quando **nessun** personaggio dell'account nella gilda è più ufficiale: al cambio di ruolo (`ROLE_CHANGED` da ufficiale a membro) e a ogni accesso, dopo che il roster è arrivato completo, il client guarda i personaggi dell'account presenti nel roster (`Accounts:OwnChars()` con `inGuild`); se per ognuno `RankIsOfficer` dice `false` (non `nil`: grado non leggibile vuol dire aspettare), cancella i record di `timeline`, `onotes`, `ocfg`, gli `absence` `:off` e quelli `:self` di altri account, la fotografia del roster e la coda (§2.1, §4). Restano solo gli `absence` `:self` del proprio account. Una riga nella chat, una volta: `You are no longer an officer: Accord removed the officer data from this computer.` / `Non sei più ufficiale: Accord ha tolto i dati degli ufficiali da questo computer.`
- Un personaggio non ufficiale di un account che ha ancora un ufficiale nella gilda **non vede** questi dati (le viste controllano il ruolo del personaggio connesso) ma non li cancella.
- Un ufficiale retrocesso e poi promosso di nuovo riparte da zero: la fotografia del roster ricomincia (§2.1) e il resto torna dagli altri ufficiali con la sincronizzazione, se il canale è provato.
- Cambio di gilda: nulla da cancellare, i dati sono per gilda (`GuildKey`).

## 2. Cronologia osservata (M8.2)

### 2.1 Osservazione

Solo i client degli **ufficiali** osservano (un membro non salva nulla). Ogni account ufficiale tiene una **fotografia** del roster in `GuildKey:Data().officer.snap`:

```
snap = { at = <ora dell'ultima lettura completa>, m = { [GUID] = { n = nome, r = rankIndex, rn = nome del grado, l = livello, p = nota pubblica } } },
gone = { [GUID] = <ora della prima lettura completa senza quel personaggio> }   -- tenuto 400 giorni
```

- **TL-01** Una lettura del roster è **completa** quando `Compat.Guild.RosterCount()` dice un totale uguale al numero di righe lette e ogni riga ha un GUID. Si osserva a ogni `ROSTER_UPDATED` (il roster si ricostruisce già con il suo ritardo, ROS-03); una lettura incompleta non cambia nulla.
- **TL-02** La prima lettura completa di un account (nessuna `snap`) è la **base**: non produce eventi. Così l'installazione dell'addon non "fa entrare" tutta la gilda.
- **TL-03** Ogni lettura completa successiva si confronta con la fotografia: per ogni differenza nasce un evento con `a` = `snap.at` (l'ultima volta che il client ha visto il valore vecchio) e `b` = l'ora di questa lettura (la prima volta che vede il nuovo). Poi la fotografia si aggiorna.
- **TL-04** **Cambi di massa**: se una lettura farebbe uscire più di 10 personaggi **e** più del 25% della fotografia, la lettura non si applica e la fotografia resta; si applica solo se una seconda lettura completa, almeno 120 s dopo, dà lo stesso insieme di uscite (difesa contro un roster caricato a metà dal server). Lo stesso vale per i cambi di grado oltre le stesse soglie (un grado cancellato sposta molti membri).
- Si osserva solo un personaggio ufficiale connesso, fuori dalla demo. Gli eventi non si scrivono subito: aspettano **60–300 s casuali** (`Timeline.WAIT`), poi si scartano se un evento uguale (§2.3) è già nell'archivio da un altro osservatore (il primo che scrive vince, gli altri contano solo una conferma locale, `confirmed`). Così, con il canale provato, due ufficiali online insieme scrivono di solito un solo evento.
- Un cambio di nome di un personaggio (stesso GUID) non è un evento: la fotografia prende il nome nuovo e la cronologia mostra il nome attuale.

### 2.2 Eventi e record

| `k` | Quando | Campi in più |
|---|---|---|
| `join` | un GUID nella lettura che la fotografia non ha | `r`, `rn`, `l` al momento dell'osservazione |
| `leave` | un GUID della fotografia assente dalla lettura (uscito o espulso: il client non sa distinguere) | `rn`, `l` dalla fotografia |
| `rank` | `rankIndex` diverso | `f`, `t` = indici vecchio e nuovo; `fn`, `tn` = nomi dei gradi |
| `level` | livello diverso | `f`, `t` = livelli vecchio e nuovo |
| `note` | nota pubblica diversa | `f`, `t` = testi vecchio e nuovo (`""` = vuota) |

Ogni evento: `{ k, g = GUID del personaggio, n = nome (con `-Reame` se di un altro reame), a, b, ...campi in più }`. Limiti di forma: `n` 1–48 caratteri, `rn`/`fn`/`tn` fino a 32, i testi delle note fino a 64 byte (si tagliano), `a ≤ b`, `b` nel giorno del record, livelli 1–200, indici di grado 0–19.

- **TL-05** Un osservatore scrive i suoi eventi in record propri dell'insieme `timeline`: `id = "<GUID osservatore>:<giorno>:<p>"`, campi `{ observer, day, ev = { evento, ... } }`, `author = observer`. Un record tiene al massimo **60 eventi** e 8192 B stimati (`Config.EstimateSize`); quando è pieno si apre la parte successiva (`p` da 1 a 4). Oltre la quarta parte gli eventi del giorno si perdono e si contano (`dropped`, `/accord debug`): 240 eventi al giorno per osservatore bastano anche per una grande pulizia, e un altro ufficiale può osservarli.
- **TL-06** **Livelli raggruppati**: un osservatore ha al più un evento `level` per personaggio e giorno. Un nuovo cambio di livello dello stesso personaggio nello stesso giorno aggiorna quell'evento (`t` e `b` nuovi; `f` e `a` restano). Così un personaggio che sale da 20 a 27 in una sera è un evento solo.
- **TL-07** **Conservazione**: un record si cancella quando il suo `day` ha più di **365 giorni** (`expires` sul `day`, non sul `time`, così ogni client cancella lo stesso giorno). `gone` si pulisce dopo 400 giorni.
- **Dimensione** (stima da provare in M8.2): una gilda di 200 membri con 15 eventi al giorno tiene circa 1,8 KB al giorno, circa 650 KB in un anno, con un solo osservatore per evento. Il test di M8.2 misura 1000 membri, 365 giorni e 40 eventi al giorno e scrive il numero in [SPEC-10 R6](SPEC-10-risks-open-questions.md#1-rischi).

### 2.3 Due osservatori dello stesso cambio

Due ufficiali vedono lo stesso cambio in momenti diversi: chi era online quando è successo ha un intervallo `[a, b]` stretto, chi entra il giorno dopo uno largo. Il cambio vero sta dentro **entrambi** gli intervalli.

- **TL-08** **Identità**: due eventi sono lo stesso cambio quando hanno lo stesso `k`, lo stesso `g`, gli stessi valori (`join`/`leave`: nessuno; `rank`: `f` e `t`; `note`: `f` e `t`; `level`: solo `t`, perché un osservatore assente può aver visto 20→27 dove un altro ha visto 22→27) **e** i loro intervalli, allargati di **τ = 300 s** per parte (`Timeline.TOLERANCE`), si sovrappongono.
- **TL-09** **Unione** (alla lettura, `Timeline:Events(guid)`): gli eventi uguali diventano uno, con `a` = il massimo degli `a`, `b` = il minimo dei `b` (se per la tolleranza `a > b`, allora `a = b`), gli osservatori = l'unione (nell'ordine del `b` più vecchio), e per `level` `f` = il minimo. Se un evento è uguale a più eventi diversi (un osservatore assente a lungo ha un intervallo che ne copre molti), si unisce a quello con il `b` più vicino al proprio.
- Si scrive anche al momento della scrittura: un evento che, dopo l'attesa di §2.1, è uguale a uno già nell'archivio non si scrive.

### 2.4 Interfaccia

- **Scheda del membro** (solo ufficiali): sezione `Timeline` / `Cronologia` con gli eventi di **tutti i personaggi dell'account** nella gilda (dal più recente, con il nome del personaggio), le ultime 10 righe e `Show all` che apre la pagina Timeline filtrata. La riga `Member since <data>` / `Membro dal <data>` usa il `join` più vecchio noto, altrimenti `Member since: unknown`.
- **Pagina Timeline** della scheda `Officers` (§8): tutti gli eventi della gilda, filtri per tipo e periodo (7, 30, 90, 365 giorni; predefinito 30), ricerca per nome.
- Testo di una riga: la data di `b` (`2026-11-24 21:10`); se `b - a` supera 24 ore, `between <data a> and <data b>` / `tra il <data a> e il <data b>`. Testi: `joined the guild` / `è entrato nella gilda`, `left the guild` / `è uscito dalla gilda`, `rank Member → Veteran`, `level 20 → 27`, `public note: "x" → "y"`. Il tooltip dice gli osservatori (nomi dal roster o `a former officer` / `un ex ufficiale`, mai il GUID) con la provenienza (M7.2, fonte `shared` o `own`).
- I testi delle note e i nomi passano per la pulizia dei contatti (niente caratteri di controllo, `|` raddoppiato).

Test (`Tests/test_timeline.lua`): base senza eventi; ogni tipo; due osservatori con intervalli stretto e largo danno un evento; livelli raggruppati; lettura incompleta e cambio di massa non confermato non producono eventi; 60 eventi per parte e 4 parti; conservazione al giorno 365 e 366; un membro rifiuta ogni record; nulla su `GUILD`.

## 3. Inattività per account (M8.3)

### 3.1 Ultimo accesso di un personaggio

Per ogni personaggio, la fonte più recente tra queste (tutte, non la prima che risponde):

| Fonte | Per chi | Valore | Etichetta (M7.2) |
|---|---|---|---|
| roster: online adesso | personaggi nella gilda | adesso | `native` |
| roster: `lastOnlineHours` (`GetGuildRosterLastOnline` **[verificare]**, o il campo del club) | personaggi nella gilda, offline | `ServerTime() - ore × 3600` (mesi di 30 giorni, anni di 365, come `Compat.LastOnlineHours`) | `native` |
| `seen` del record `accounts` (M7.3) | personaggi fuori dalla gilda elencati da un account con l'addon | l'inizio del giorno `seen` (`Accounts.AltGuildOf`, la voce con il `seen` più alto) | `shared` |
| `AzerothAccordDB.chars[reame][GUID].seen` | i personaggi del proprio account | `seen` | `own` |

Un personaggio senza nessuna di queste è **sconosciuto**.

### 3.2 Account

- **INA-01** L'account è il gruppo di `Accounts:GroupOf(guid)` (elenco reciproco, personaggi fuori gilda elencati, e i personaggi uniti da una nota pubblica `main:`/`alt:`, ACC-05). Un membro senza gruppo è un account da solo. Le unioni da nota contano (riducono i falsi inattivi) ma la riga lo dice (`grouped by a note` / `unito da una nota`), perché nessuno le verifica.
- **INA-02** **Ultimo accesso dell'account** = il più recente dei suoi personaggi; i giorni di inattività sono `floor((ServerTime() - ultimo) / 86400)`. Un personaggio online rende l'account attivo (0 giorni). L'account è **sconosciuto** se tutti i suoi personaggi lo sono.
- Un account compare una volta, con il nome del **main** (`Accounts:MainOf`) e il personaggio che ha dato l'ultimo accesso (`last seen on <alt>`). Il calcolo si ripete in modo pigro dopo `ROSTER_UPDATED` e `ACCOUNTS_UPDATED`, una passata per tutta la gilda (1000 membri: entro 20 ms offline, misurato in M8.3).

### 3.3 Fasce

- **INA-03** Quattro soglie in giorni, crescenti, ognuna da 1 a 365: predefinite **14 / 30 / 60 / 90**. Un account con `d` giorni è nella fascia più alta la cui soglia è ≤ `d`; sotto la prima è attivo.

| Fascia | Predefinita | Testo |
|---|---|---|
| 1 | 14–29 giorni | `14+ days` / `14+ giorni` |
| 2 | 30–59 | `30+ days` |
| 3 | 60–89 | `60+ days` |
| 4 | 90 e oltre | `90+ days` |

- **INA-04** Le fasce le sceglie **un ufficiale** (o il GM), nella pagina Inactive (`Tiers…`), e valgono per tutti gli ufficiali: un record dell'insieme `ocfg`, id `tiers`, `{ tiers = { n1, n2, n3, n4 } }` (regola del proprietario: quattro interi crescenti da 1 a 365). Vince la scrittura più recente (`rev`). Senza record valgono le predefinite. Finché il canale non è provato la scelta resta su questo computer (OFF-07). `Reset to defaults` scrive il record con i valori predefiniti.

### 3.4 Assenze dichiarate

- **INA-05** Un'assenza è `{ char = GUID, from = giorno, until = giorno }` nell'insieme `absence`. Due id per personaggio, così membro e ufficiale non si scavalcano le revisioni: `<GUID>:self` scritto dall'account del personaggio, `<GUID>:off` scritto da un ufficiale. `until = 0` cancella l'assenza. Regola del proprietario: `from` è oggi o un giorno passato al momento della scrittura, `until` da `from` a `from` + **180 giorni**. Nessun motivo e nessun testo libero.
- **INA-06** Per un account vale il record `absence` **scritto più di recente** (`time`) tra quelli dei suoi personaggi. Un account con un'assenza valida (`until` ≥ oggi) **non è inattivo**: la pagina Inactive lo nasconde (con il filtro `Show away` / `Mostra assenti` lo mostra come `Away until <data>` / `Assente fino al <data>`) e la revisione guidata non lo propone. Dal giorno dopo `until` torna a contare normalmente, con la riga `away until <data>` per 14 giorni.
- **Il membro** la dichiara nella card **Absence** / **Assenza** delle Settings (data di rientro, `Save`, `Clear`) o con `/accord away <AAAA-MM-GG>` e `/accord away off`. La card mostra solo l'assenza del proprio account (`:self`); quella scritta da un ufficiale il membro non la vede.
- **Invio del membro**: a ogni scrittura, e una volta per accesso 60–120 s dopo il primo `HELLO` finché c'è un'assenza valida, il client manda i propri record `:self` in `WHISPER` (`REC`, `officerOnly`) a **fino a due ufficiali online** scelti per hash come in `Sync:RequestSet` (`Sync.ASK_OFFICERS`). Se nessun ufficiale è online non manda nulla e riprova al prossimo accesso. Gli ufficiali poi se lo passano su `OFFICER` (§1.5).
- **L'ufficiale** la imposta dalla scheda del membro o dalla pagina Inactive (`Set absence…`) per qualunque personaggio della gilda: record `:off`.
- **Conservazione**: un record si cancella 30 giorni dopo `until` (o 30 giorni dopo `time` se `until = 0`).

### 3.5 Pagina Inactive

Una riga per account inattivo o sconosciuto (gli attivi no), ordinata per giorni decrescenti: main, numero di personaggi nella gilda, grado più alto tra i suoi personaggi, giorni e fascia, ultimo accesso con il personaggio e la provenienza, assenza, nota estesa (un'icona con il testo nel tooltip). Filtri: fascia minima (predefinita 1), `Show away`, `Show unknown`. Gli account con un personaggio ufficiale hanno il segno `officer` e non sono mai proposti dalla revisione guidata (§4.1), ma restano nella lista. Pulsanti: `Review…` (§4), `Tiers…`, `Export` (§6).

Test (`Tests/test_inactivity.lua`): un giocatore attivo solo su un alt nella gilda o fuori dalla gilda (`seen`) non è inattivo; un account con tutti i personaggi sconosciuti è sconosciuto; i bordi di ogni fascia; fasce personalizzate e record non valido; un'assenza nasconde fino al giorno di rientro compreso; il record più recente tra `:self` e `:off` vince; un membro non vede la pagina.

## 4. Revisione guidata e coda delle azioni manuali (M8.4)

### 4.1 Revisione guidata

- **OPS-01** **Nessuna azione protetta**: l'addon non chiama mai le funzioni che cambiano il roster, né direttamente né con una macro o un comando scritto nella chat: `GuildPromote`, `GuildDemote`, `GuildUninvite`, `GuildSetLeader`, `SetGuildMemberRank`, `GuildRosterSetPublicNote`, `GuildRosterSetOfficerNote`, `C_GuildInfo.Promote`, `C_GuildInfo.Demote`, `C_GuildInfo.Uninvite`, `C_GuildInfo.RemoveFromGuild`, `C_GuildInfo.SetNote`, `C_GuildInfo.SetLeader`, `C_GuildInfo.SetGuildRankOrder`, `RunMacroText`, `ChatEdit_SendText`. Un test statico (`Tests/test_officer_ops.lua`) cerca questi nomi in `AzerothAccord/**/*.lua` e fallisce se ne trova uno fuori dall'elenco stesso. Si possono **leggere** i permessi (`CanGuildPromote`, `CanGuildDemote`, `CanGuildRemove`, `C_GuildInfo.CanEditOfficerNote`, `CanEditPublicNote`, **[verificare]**) per disabilitare un'azione che l'ufficiale non potrebbe fare.
- **Passo 1, scelta**: la fascia minima (predefinita la 4) e due caselle: `Include accounts reviewed in the last 30 days` (spenta) e `Include unknown` (spenta). Gli account assenti (§3.4) e quelli con un personaggio ufficiale non entrano mai.
- **Passo 2, revisione**: un account per riga (main, personaggi nella gilda con grado, livello e ultimo accesso, la nota estesa, gli ultimi 3 eventi della cronologia). Per ogni account si sceglie un'azione: `Keep` / `Tieni` (predefinita), `Remove` / `Rimuovi`, `Demote` / `Retrocedi`, `Promote` / `Promuovi`, `Edit note` / `Cambia nota`. L'azione vale per **tutti** i personaggi dell'account nella gilda; un menu per personaggio permette di cambiarla. `Promote` e `Demote` propongono il grado sopra o sotto e lasciano scegliere un grado tra quelli **sotto** il proprio; `Edit note` chiede quale nota (`public` / `officer`) e il testo nuovo (al massimo 31 caratteri, il limite della finestra del gioco **[verificare]**).
- **Passo 3, riepilogo**: `Add <N> actions to the queue` / `Aggiungi <N> azioni alla coda`. Nient'altro succede. `Keep` segna l'account come **rivisto** per 30 giorni (`officer.reviewed[<chiave dell'account>] = ora`, solo locale, la chiave è `Accounts:AccountKey`).

### 4.2 La coda

La coda è **di questo account ufficiale** e resta su questo computer (`GuildKey:Data().officer.queue`); non si sincronizza con gli altri ufficiali (un'azione fatta da un altro ufficiale si spunta comunque, perché si spunta dal roster). Una voce:

```
{ n = numero, g = GUID, name, op = "promote" | "demote" | "remove" | "note",
  fromRank, toRank, noteKind = "public" | "officer", text,
  created, by = GUID dell'ufficiale, status = "open" | "done" | "gone" | "expired" | "cancelled", closed }
```

- Al massimo **200** voci aperte; una nuova voce per lo stesso personaggio e lo stesso `op` sostituisce quella aperta.
- Ogni voce aperta mostra cosa fare a mano: il nome (selezionabile, da copiare) e, per `remove`, `promote` e `demote`, il comando del gioco da scrivere, `/gremove <nome>`, `/gpromote <nome>`, `/gdemote <nome>` **[verificare]** che esistano su Forever, in una casella di sola lettura; per `note`, il testo da incollare nella finestra del gioco. Un pulsante apre la finestra della gilda (come fa già la scheda Accord). Il comando **non** si esegue: lo scrive l'ufficiale.
- **OPS-02** **Spunta dal roster**: a ogni lettura completa (§2.1, TL-01), per ogni voce aperta:

| `op` | Spuntata (`done`) quando | Altri esiti |
|---|---|---|
| `promote`, `demote` | il `rankIndex` del personaggio è `toRank` | il personaggio non è più nel roster → `gone` |
| `remove` | il GUID non è nella lettura completa (uscito o espulso: per la coda è fatto) | — |
| `note` `public` | la nota pubblica è uguale a `text` (spazi agli estremi tolti) | non più nel roster → `gone` |
| `note` `officer` | la nota ufficiale (`officerNote`) è uguale a `text`; si controlla solo se `CanViewOfficerNote()` | senza quel permesso la voce si chiude solo a mano (`Mark done` / `Segna fatta`) |

  La spunta non dipende dalla cronologia (funziona anche se l'evento è stato scartato come doppio) e vale anche per un'azione fatta da un altro ufficiale; il cambio di massa di TL-04 non blocca la spunta.
- **OPS-03** **Scadenza**: una voce aperta da **14 giorni** diventa `expired`. Le voci chiuse (`done`, `gone`, `expired`, `cancelled`) restano visibili, attenuate, per **7 giorni** dalla chiusura, poi si cancellano. `Cancel` / `Annulla` chiude una voce a mano.
- La pagina Queue della scheda `Officers` mostra le voci aperte (le più vecchie prima) e le chiuse sotto; il titolo della scheda mostra il numero delle aperte.

Test: nessun nome di OPS-01 nel codice; ogni `op` spuntato dal roster simulato; `gone`, scadenza a 14 giorni, pulizia a 7; sostituzione della voce aperta; 200 voci; l'azione fatta "da un altro" (il roster cambia senza la coda) si spunta.

## 5. Note estese (M8.5)

### 5.1 Formato

- **ONT-01** Una nota per **personaggio**: record `onotes` con `id` = GUID del personaggio, campi `{ char = GUID, text }`, `author` = l'ufficiale che l'ha scritta per ultimo. Vince la `rev` più alta (due ufficiali che scrivono insieme: vince il `time` più recente, regola di sempre); l'interfaccia mostra chi ha scritto l'ultima versione e quando.
- **ONT-02** **Limite**: al massimo **500 caratteri** e **1000 byte** UTF-8, al massimo **20 righe**; niente caratteri di controllo tranne l'a capo. La casella del gioco ferma la scrittura al limite (`maxLetters` 500, i byte controllati al salvataggio con il messaggio `Too long: <n> / 1000 bytes.`). Il `|` si raddoppia nella visualizzazione.
- **Cancellazione**: `Delete` scrive `text = ""` (una revisione nuova, così la cancellazione arriva a tutti gli ufficiali); il record vuoto scade dopo **60 giorni**.
- **Ex membri**: un client di ufficiale che vede un personaggio fuori dal roster da **365 giorni** (`gone`, §2.1) scrive la cancellazione della sua nota. È una scrittura normale, quindi tutti gli ufficiali la ricevono; due ufficiali che la scrivono insieme danno la stessa cosa. (Proposta in attesa del proprietario, [SPEC-10 Q14](SPEC-10-risks-open-questions.md#2-domande-aperte-per-il-proprietario).)

### 5.2 Dove si vede e dove viaggia

- Nella scheda del membro, solo per gli ufficiali: sezione `Officer notes` / `Note degli ufficiali` con la nota del personaggio (modificabile) e sotto, in sola lettura, le note degli altri personaggi dell'account (con il nome del personaggio). Etichetta di provenienza (M7.2): l'autore e l'età. Un'icona nella riga della pagina Inactive e nella revisione guidata.
- **ONT-03** Viaggiano **solo su `OFFICER`** (e in whisper tra ufficiali come risposta a un `OHELLO`, §1.5) e solo con il canale provato; finché non lo è restano su questo computer (OFF-07). Mai su `GUILD`, mai in whisper a un non ufficiale (OFF-04, OFF-05): il test di M8.5 manda una nota da un ufficiale con il canale provato e con quello non provato e controlla ogni messaggio del simulatore.
- **ONT-04** Un ufficiale retrocesso le perde (OFF-10); un membro non le riceve mai (OFF-01) e un client precedente le ignora.
- Le note estese non sono la nota ufficiale del gioco (31 caratteri, letta con `CanViewOfficerNote`): Accord non la cambia (OPS-01) e la mostra a parte, come oggi.

## 6. Esportazioni (M8.6)

### 6.1 Cosa e come

Tre esportazioni, ognuna in **CSV** o in **testo per Discord**: `Roster`, `Inactive accounts` / `Account inattivi`, `Timeline` / `Cronologia`. Il pulsante `Export` delle pagine Inactive e Timeline e della vista Roster (solo per ufficiali) apre una casella a più righe di sola lettura con il testo già selezionato (la casella del backup di M7.5, `UI/CopyBox`), con un selettore `CSV · Discord`. Esporta ciò che la pagina mostra con i suoi filtri. Sopra la casella: `This text leaves the game: share it only with your officers.` / `Questo testo esce dal gioco: condividilo solo con gli ufficiali.`

- **EXP-01** **Mai** il token dell'account, **mai** un GUID (nemmeno come chiave dell'account: un account si identifica con il nome del suo main), mai la chiave della gilda, mai le note ufficiali (quella del gioco e quelle estese, proposta [SPEC-10 Q15](SPEC-10-risks-open-questions.md#2-domande-aperte-per-il-proprietario)). Il test cerca in ogni esportazione di una gilda demo piena `Player-`, ogni token tenuto dal client e ogni testo di nota estesa.
- **Limite**: 256 KB come il backup; oltre, si tengono solo righe intere e la casella dice `<n> rows left out: narrow the filters.` / `<n> righe escluse: restringi i filtri.` (fuori dal testo esportato).

### 6.2 Colonne CSV

Intestazione in inglese, fissa (non tradotta, per chi legge il file con un programma). Date in UTC: `AAAA-MM-GG` (`_date`) o `AAAA-MM-GG HH:MM` (`_utc`).

| Esportazione | Colonne, in ordine |
|---|---|
| `Roster` (una riga per personaggio nella gilda) | `name`, `realm`, `main`, `class`, `level`, `rank`, `last_seen_date`, `days_inactive`, `account_days_inactive`, `tier`, `away_until`, `public_note`, `has_addon` |
| `Inactive accounts` (una riga per account) | `main`, `realm`, `characters`, `highest_rank`, `days_inactive`, `tier`, `last_seen_date`, `last_seen_character`, `last_seen_source`, `grouped_by_note`, `away_until` |
| `Timeline` (una riga per evento unito, §2.3) | `date_utc`, `since_utc`, `event`, `name`, `realm`, `from`, `to`, `observers` |

Valori: `class` il nome della classe in inglese (`classFile`); `rank` il nome del grado; `main` vuoto se il personaggio è il main o non ha gruppo; `tier` 0–4 (0 = attivo) o vuoto se sconosciuto; `days_inactive` vuoto se sconosciuto; `has_addon` e `grouped_by_note` `yes`/`no`; `characters` i nomi dei personaggi nella gilda separati da `; `; `last_seen_source` `game`, `shared` o `you`; `event` `join`, `leave`, `rank`, `level`, `note`; `from`/`to` i nomi dei gradi, i livelli o i testi delle note (vuoti per `join`/`leave`); `observers` il numero di osservatori. `realm` vuoto per il reame del giocatore.

### 6.3 Escape CSV

- **EXP-02** RFC 4180 con il separatore `,` e righe separate da `\n` (la casella del gioco non tiene `\r`): un valore che contiene `,`, `"`, un a capo, o spazi agli estremi va tra virgolette, con ogni `"` raddoppiato. UTF-8, senza BOM.
- **EXP-03** **Formule**: un valore di testo che comincia con `=`, `+`, `-`, `@`, tabulazione o `\r` prende davanti un apostrofo `'` (prima delle virgolette), così un foglio di calcolo non lo esegue come formula. I numeri non si toccano.
- **EXP-04** Il `|` (il carattere di escape dei testi del gioco) si scrive `||` nella casella, che lo mostra e lo copia come uno solo **[verificare]**; i test leggono il testo logico, prima di questo passo.
- Test (`Tests/test_export.lua`): ogni esportazione fa andata e ritorno con un lettore CSV RFC 4180 dei test (`Tests/lib/csv.lua`): stesse righe, stesse colonne, stessi valori, anche con virgole, virgolette, a capo, `=`, `-`, `@`, accenti e nomi con lo spazio; nessun token, GUID o nota estesa.

### 6.4 Testo per Discord

- **EXP-05** Un blocco di codice (tre apici inversi) con una riga di titolo (`Inactive accounts · <gilda> · 2026-11-24`) e le colonne allineate con spazi: dentro un blocco di codice Discord non interpreta il markdown e non manda menzioni (`@everyone` resta testo). Gli apici inversi nei valori diventano `'`; i valori lunghi si tagliano con `…` (nome 24 caratteri, nota 30).
- Colonne: Roster `Name, Lvl, Class, Rank, Last seen, Days`; Inactive `Main, Chars, Rank, Days, Tier, Last seen, Away`; Timeline `Date, Name, Event` (con `from → to`).
- **Parti**: Discord accetta 2000 caratteri per messaggio; il testo si divide in parti di al massimo **1900** caratteri, ognuna un blocco di codice completo con `(1/3)` nel titolo, senza spezzare una riga. Una riga vuota separa le parti nella casella.

## 7. "Cosa condivido" e diagnostica

- Il pannello di M7.6 aggiunge con `ShareModel.Add`: `Absence` / `Assenza` (a chi: `officers only`, il contenuto: la data di rientro, nessun interruttore: la si cancella con `Clear`) per tutti; per gli ufficiali `Officer tools` / `Strumenti per ufficiali` (cronologia osservata da questo personaggio: eventi per mese; note estese scritte; fasce), a chi: `officers, on the officer channel` e, finché il canale non è provato, `only on this computer`.
- `/accord debug`, sezione `Officer tools`: stato del canale, numero di record per insieme, eventi in attesa, `confirmed`, `dropped`, `officerOnly` scartati, voci della coda per stato, dimensione stimata. Mai nomi, GUID o testi (SPEC-09 §6).
- **Demo** (M7.4): la gilda inventata riceve 60 giorni di cronologia osservata da due ufficiali inventati (con eventi uniti), 3 assenze, 5 note estese, fasce predefinite e una coda di 4 voci; ogni passo di M8 aggiunge la sua parte a `Data/Demo.lua`. Nella demo nulla si osserva né si invia (§2.1, M7.4).

## 8. Interfaccia: la scheda Officers

Una scheda `Officers` / `Ufficiali` dopo le altre viste, visibile solo quando `Role:IsOfficer()` (e nella demo), con tre pagine nel selettore: `Inactive · Queue · Timeline`. Le pagine seguono lo stile di [`ui-style.md`](ui-style.md) (tabelle, filtri, pulsanti come le altre viste). Le sezioni degli ufficiali nella scheda del membro (cronologia, note estese, assenza) compaiono solo per gli ufficiali. Un membro non vede la scheda né le sezioni; vede solo la card Absence nelle Settings.

## 9. Cosa resta da verificare nel client

- `GetGuildRosterLastOnline` sui server di Forever e la sua precisione (ore, giorni) per un membro offline da mesi (M8.3); senza, un membro senza addon è sconosciuto ([SPEC-10 R11](SPEC-10-risks-open-questions.md#1-rischi)).
- Che un roster caricato del tutto dia sempre `GetNumGuildMembers()` uguale alle righe lette, e quanto spesso arriva un roster a metà dopo l'accesso (TL-01, TL-04).
- S5: che un membro semplice **non** riceva i messaggi addon su `OFFICER` ([SPEC-09 S5](SPEC-09-quality-release.md#1-spike-tecnico-m0)); Accord rifiuta comunque i record (OFF-01).
- I comandi `/gremove`, `/gpromote`, `/gdemote` su Forever, il limite di 31 caratteri delle note del gioco, e i permessi `CanGuildPromote`, `CanGuildDemote`, `CanGuildRemove`, `CanEditPublicNote`, `C_GuildInfo.CanEditOfficerNote` (M8.4).
- Il copia e incolla di `|` dalla casella dell'esportazione (EXP-04) e di un testo di 1900 caratteri in Discord (M8.6).
