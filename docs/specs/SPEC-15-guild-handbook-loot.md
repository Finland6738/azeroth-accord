# SPEC-15: Manuale di gilda e loot

Specifica della milestone M11 ([roadmap](../roadmap/M11-loot-handbook.md)): il **manuale di gilda**, pagine di testo che gli scrittori della gilda (gli ufficiali, salvo scelta diversa) scrivono nel gioco e che ogni membro con l'addon legge anche offline; le **pagine predefinite** (informazioni, regolamento, FAQ, gestione dei raid, del roster e del loot); la **pagina del loot**, che dice quale sistema usa la gilda e con quale addon, mostra chi lo ha caricato e, con FDCP, il riassunto delle sue regole. Il loot è **descritto, non calcolato** (SPEC-10 Q6). Ogni sezione dice il passo che la realizza (M11.2–M11.6; M11.7 è già fatto, M11.8 è la prova e il rilascio `v0.11.0`). Le scelte che spettano al proprietario sono in [SPEC-10](SPEC-10-risks-open-questions.md) (Q27–Q33), con una proposta che il codice applica finché il proprietario non risponde. La decisione di architettura è [ADR 0025](../adr/0025-guild-handbook-pages-shared-on-guild-revisions-local.md).

Nomi di codice, campi e testi dell'interfaccia in inglese (con la traduzione italiana in `itIT.lua`, [ADR 0015](../adr/0015-interface-and-documentation-languages.md)). Le ore dei record sono ore del server in secondi (`Compat.ServerTime()`). Le lunghezze sono in **byte** UTF-8 (una lettera accentata italiana conta 2).

## 1. Principi

Le regole di integrazione del proprietario (2026-11-24, [M10](../roadmap/M10-calendar-raids.md#integration-rules-owner-2026-11-24), RAID-01…RAID-08 di [SPEC-14 §1](SPEC-14-calendar-raids-season.md#1-principi)) valgono anche qui. In più:

| # | Regola | Che cosa vuol dire qui |
|---|---|---|
| HB-01 | **Il loot si descrive, non si calcola** | nessun punteggio, priorità, asta o assegnazione; la pagina del loot è testo degli scrittori più due scelte (sistema e addon) e ciò che l'addon scelto pubblica (§8) |
| HB-02 | **Scrive chi la gilda sceglie** | solo i gradi scelti dagli ufficiali, ufficiali e Guild Master sempre (§3.3); una pagina di chi non è scrittore si rifiuta |
| HB-03 | **Nessun testo della gilda nell'addon** | i modelli delle pagine predefinite hanno solo titoli e intestazioni (§7); il suggerimento di FDCP è un testo della lingua dell'interfaccia, non un dato della gilda (§8.5) |
| HB-04 | **Si legge offline** | ogni pagina ricevuta resta sul client e si legge senza nessuno online (§5) |
| HB-05 | **Il traffico è condiviso** | i testi viaggiano su `GUILD` una volta per tutti quelli che li aspettano, mai in whisper a ciascuno (§3.6); le revisioni passate non viaggiano (§3.5); il budget di [SPEC-09 §7](SPEC-09-quality-release.md#7-budget-di-traffico-condiviso-m10) non sale (§3.7) |
| HB-06 | **Niente che esegua o porti fuori** | il testo non contiene codici del gioco (`|`), non si esegue, e un indirizzo web è solo testo da copiare (§4, §8.4) |

## 2. Moduli, interruttore, dati locali

### 2.1 L'interruttore `raid`

Tutto M11 è dietro l'interruttore **`raid`** di [`Core/Features.lua`](../../AzerothAccord/Core/Features.lua), oggi **spento**; `raid` acceso accende anche `season` (`Features.IMPLIES`). In M11 `raid` copre:

- quello che copre già da M11.7: la vista *Raid*, `/accord raid`, la scelta della fonte `loot`, *Loot (FDCP)* nella scheda del membro, il riassunto delle regole di FDCP, le callback di FDCP per la fonte `loot`;
- l'insieme `handbook` (M11.2): con `raid` spento non si scrive, non si accetta e non si manda (`feature = "raid"` nella definizione di `Net/Store.lua`), e il suo riepilogo a parte (§3.6) non entra nei `HELLO`;
- i record `handbook` e `loot` di `guildcfg` (§3.3, §8.1): con `raid` spento si rifiutano (`owner`) come oggi, mentre `sources` e `target` restano accettati (sono di `season`);
- la vista *Handbook* (M11.3, M11.4), `/accord handbook`, i modelli delle pagine predefinite (M11.5) e la pagina del loot (M11.6), con il loro avviso e la riga del Centro azioni (§3.5).

M11.8 accende `raid` quando M11 è completa nel codice, per `v0.11.0`. Fino ad allora i test lo accendono e lo spengono, e `Tests/test_features.lua` e `Tests/test_handbook.lua` controllano che spento non si veda e non si mandi nulla. Come gli altri interruttori, i moduli chiedono `Features.On("raid")` quando agiscono.

### 2.2 File nuovi

| File | Contenuto | Passo |
|---|---|---|
| `Data/Handbook.lua` | l'insieme `handbook`, gli scrittori, le revisioni locali, i conflitti, il segno "letto"; i limiti prima del salvataggio, l'ordine, la bozza | M11.2, M11.4 |
| `Data/HandbookText.lua` | il lettore del testo (§4): blocchi, collegamenti, ricerca, pulizia | M11.3 |
| `UI/Handbook.lua` | la vista *Handbook*: elenco, lettore, ricerca | M11.3 |
| `UI/HandbookEditor.lua` | quello che vede in più uno scrittore: editor, anteprima, revisioni, pagine eliminate, *New page*, *Writers*, frecce | M11.4 |
| `Data/HandbookDefaults.lua` | i modelli delle pagine predefinite e la loro semina una volta (§7) | M11.5 |
| `Data/Loot.lua` | il record `loot` di `guildcfg`, chi ha l'addon scelto, l'indirizzo di download (§8) | M11.6 |
| `UI/LootPage.lua` | la parte fissa della pagina del loot nel lettore (§8) | M11.6 |

`Config.VIEWS` aggiunge `handbook` (dopo `raid`). Comando: `/accord handbook [pagina]` (con l'interruttore spento risponde come un comando sconosciuto).

### 2.3 Eventi del Bus

`HANDBOOK_CHANGED(id)` (una pagina arrivata, scritta, cancellata o seminata; `id` nil = più pagine), `HANDBOOK_CONFLICT(id)` (la propria modifica è stata sostituita, §3.5), `HANDBOOK_READ(id)`, `LOOT_CHANGED()` (record `loot` cambiato, o chi ha l'addon). Si aggiungono all'intestazione di `Core/Bus.lua`.

### 2.4 Dati locali

Nessuna migrazione di schema: le chiavi nuove si aggiungono dove mancano, al primo uso.

| Chiave | Contenuto | Sezione |
|---|---|---|
| `GuildKey:Data().handbook.revs` | `{ [id] = { { rev, author, time, title, body, lost? } } }`, le ultime `Handbook.KEEP_REVISIONS` (5) versioni viste da questo client per ogni pagina | §3.5 |
| `GuildKey:Data().handbook.read` | `{ [id] = rev }`: l'ultima versione letta da questo **account** | §5.4 |
| `GuildKey:Data().handbook.draft` | `{ id, base, title, body, at }`: la bozza non salvata dell'editor, una sola | §6 |

Niente di questo si manda. Le revisioni locali e le bozze non entrano nei backup (M7.5); le pagine sì, come gli altri insiemi.

## 3. L'insieme `handbook` (M11.2)

### 3.1 I record

Un insieme sincronizzato su `GUILD`, con un tipo di record:

| Campo | Valori | Note |
|---|---|---|
| id | `P:<slug>` | `slug` di 1–24 caratteri `a-z`, `0-9`, `-`; le pagine predefinite hanno slug fissi (§7): `info`, `rules`, `faq`, `raid`, `roster`, `loot`; una pagina nuova prende lo slug dal titolo (lettere senza accenti, spazi in `-`), con un numero se c'è già |
| `title` | 1–40 byte | senza `|`, a capo né caratteri di controllo |
| `body` | 0–`Handbook.BODY_MAX` (4000) byte | il testo nel formato di §4 |
| `order` | intero 1–99 | la posizione nell'elenco; a parità, il titolo |
| `tpl` | `true` o assente | pagina predefinita ancora come il modello (§7): nessun membro la vede finché uno scrittore non la salva |
| `del` | `true` | pagina cancellata: nessun altro campo; il record resta per sempre (circa 60 byte) così la pagina non torna (§7.2) |

`id`, `author`, `rev` e `time` sono quelli di ogni record ([SPEC-02 §3](SPEC-02-network-protocol.md#3-insiemi-di-dati)): `rev` è la **revisione della pagina** (`Store:Put` scrive la `rev` tenuta più uno, chiunque sia l'autore della precedente), e vince la `rev` più alta, poi il `time`, poi l'autore (`Store.Compare`). Un record con altri campi si rifiuta (`owner`). Dimensione massima stimata di un record 6 KB (`maxBytes = 6144`: il corpo più i campi e il margine della stima).

### 3.2 Limiti

| Limite | Valore | Costante |
|---|---|---|
| Corpo di una pagina | 4000 byte | `Handbook.BODY_MAX` |
| Titolo | 40 byte | `Handbook.TITLE_MAX` |
| Pagine vive (non cancellate) | 20 | `Handbook.MAX_PAGES` |
| Tutti i corpi insieme | 32 000 byte | `Handbook.TOTAL_MAX` |
| Revisioni tenute su ogni client per pagina | 5 | `Handbook.KEEP_REVISIONS` |
| Scritture di un account | al massimo 30 all'ora | `Handbook.WRITES_PER_HOUR` |

Una scrittura che supera un limite non parte (`Handbook:Save` risponde `nil, "size"` o `"pages"`), e l'editor lo dice prima (§6). Chi riceve una pagina oltre `BODY_MAX` o `TITLE_MAX` la rifiuta (`size`); oltre `MAX_PAGES` o `TOTAL_MAX` la tiene (lo stato deve convergere su tutti i client), ma la vista mostra solo le prime 20 per `order` e lo dice agli scrittori ("The handbook is over its limit: N pages are hidden"). Sono i valori di SPEC-10 Q29.

### 3.3 Chi scrive

Gli **scrittori** sono: il **Guild Master**, gli **ufficiali** (il grado con l'ascolto della chat degli ufficiali, `Compat.Guild.RankIsOfficer`, lo stesso `officer` del roster che usa NET-12) e i **gradi scelti** dalla gilda. La scelta è un terzo record di `guildcfg` ([SPEC-03 §8](SPEC-03-data-model.md#8-impostazioni-della-gilda-guildcfg)):

| Record | Campi | Chi scrive |
|---|---|---|
| `handbook` | `ranks = { { i = indice del grado 1–9, n = nome del grado 1–32 byte } }` (al massimo 9) | solo ufficiali e Guild Master (NET-12, `authorAny`, come `sources`) |

Senza record valgono gli ufficiali e il Guild Master: è il predefinito, in **una sola costante**, `Handbook.WRITERS = "officers"` (SPEC-10 Q27). Un grado vale solo se nel roster di chi riceve l'indice `i` ha ancora il nome `n`: se la gilda rinomina o riordina i gradi, il grado scelto non vale più finché un ufficiale non lo sceglie di nuovo (la vista *Handbook* lo dice agli ufficiali). `Handbook.IsWriter(member)` è l'unico punto che decide, e lo usano sia l'editor sia le regole di fiducia. La scelta dei gradi è in fondo alla vista *Handbook*, solo per gli ufficiali.

### 3.4 Regole di fiducia (HBK-01…HBK-06)

- **HBK-01 Solo scrittori.** Una pagina si accetta se l'autore è uno scrittore secondo il roster di chi riceve e arriva di prima mano (il suo account, NET-10), oppure se la ritrasmette un ufficiale (NET-11). L'autore può aver perso il grado dopo (`authorAny`): la pagina resta valida, ma una sua revisione nuova arriva di prima mano da un non scrittore e si rifiuta (`authority`). Una pagina di un non scrittore si rifiuta con il motivo `authority`, anche se dice di essere una revisione di una pagina valida.
- **HBK-02 Forma.** Id, campi e limiti di §3.1 e §3.2; il titolo e il corpo passano la pulizia di §4.4 (un corpo con `|` o caratteri di controllo si rifiuta, `owner`: il client che scrive lo pulisce prima, quindi solo un client scorretto lo manda).
- **HBK-03 Cancellazione.** `del = true` si accetta come ogni revisione (HBK-01). Dopo una cancellazione una pagina con lo stesso id ritorna solo con una `rev` più alta scritta da uno scrittore, cioè solo se qualcuno la riscrive di proposito (*Restore* di §6.3); la semina dei modelli non lo fa mai (§7.2).
- **HBK-04 Ordine dei record.** Vince `Store.Compare` (§3.1). Due modifiche della **stessa revisione** (stessa `rev`, autori diversi) tengono **la più recente** (`time`; a parità l'autore maggiore), così tutti i client tengono la stessa; la perdente resta come revisione locale (§3.5) e il suo autore è avvisato.
- **HBK-05 Ritmo.** Al più `WRITES_PER_HOUR` revisioni all'ora per autore sono accettate da chi riceve; le altre si scartano (`rate`), come i limiti di SPEC-11 §6.3.
- **HBK-06 Nessun'altra fonte.** Nessuna pagina arriva da fuori del gioco: niente importazioni di testo da altri addon, niente lettura di SavedVariables altrui (ADR 0022 punto 2). Uno scrittore può incollare un testo nell'editor, che passa dalla pulizia come ogni testo scritto.

Il motivo di rifiuto (`authority`, `owner`, `size`, `rate`) arriva al contatore di `/accord debug` attraverso `Net/Store.lua`, come per `season`.

Come è fatto (M11.2): la definizione dell'insieme in `Net/Store.lua` ha tre regole proprie, `writer` (HBK-01, controllata di prima mano dopo la regola del rilancio: `Handbook.IsWriter` sulla voce del roster dell'**autore**), `rate` (HBK-05: conta solo le revisioni con un `time` dell'ultima ora, così le pagine vecchie di una prima sincronizzazione non contano; il contatore è in memoria, per sessione) e `replaced` (il record sostituito passa a `Data/Handbook.lua` prima di essere sovrascritto: revisioni locali e conflitti, §3.5), più `keepDeleted` (la pulizia dei 60 giorni non toglie i `del` di `handbook`). Il record `handbook` di `guildcfg` è accettato da `Integrations.ValidRecord` solo con `raid` acceso; per lui `guildcfg` passa da 256 a 768 byte stimati per record (9 gradi con un nome di 32 byte).

### 3.5 Revisioni e conflitti

**Le revisioni passate non viaggiano** (SPEC-10 Q28): ogni client, quando una pagina che tiene è sostituita da una revisione nuova, mette la vecchia (`rev`, autore, ora, titolo, corpo) in `GuildKey:Data().handbook.revs[id]` e tiene le ultime `KEEP_REVISIONS` (5). Così la storia non costa traffico, e la cronologia di una pagina è quella che **questo** client ha visto: chi era offline durante due modifiche ne ha solo l'ultima. L'editor lo dice ("Revisions seen on this computer"). La revisione corrente è sempre la prima della lista.

**Modifica sopra una revisione che è cambiata.** L'editor ricorda la `rev` da cui è partito (`base`). Al salvataggio, se la pagina tenuta ha ora una `rev` diversa da `base` (un altro scrittore ha salvato nel frattempo), l'editor non scrive: mostra "This page changed while you were editing (by <nome>, <ora>)", con il testo nuovo in anteprima e due scelte, **Keep mine** (scrive la propria versione sopra, `rev` = quella tenuta + 1) o **Discard mine** (la propria resta come revisione locale segnata `lost`). Nessuna scrittura sostituisce in silenzio una revisione già arrivata.

**Conflitto vero.** Due scrittori salvano dalla stessa `base` prima di vedere l'uno la modifica dell'altro: entrambi scrivono la stessa `rev`. Tutti i client tengono la più recente (HBK-04). Il client dell'autore della **perdente**, quando la sua versione è sostituita da una con la stessa `rev` di un altro autore:

1. mette la propria versione tra le revisioni locali, segnata `lost`, così non si perde;
2. manda `HANDBOOK_CONFLICT(id)`, un avviso (modulo `handbook`, tipo `conflict`, livello `alert` di [SPEC-13 §3.2](SPEC-13-action-center-notices.md#32-moduli-tipi-e-interruttori)): "Your edit of <titolo> was replaced by <nome>'s edit of the same revision. Your text is kept in the page's revisions on this computer.";
3. aggiunge una riga nel Centro azioni (fornitore `handbook`, urgenza 2) che apre le **revisioni** della pagina (§6) sulla propria versione persa, finché lo scrittore non sceglie *Restore* (una revisione nuova) o *Dismiss*.

Solo l'autore della perdente è avvisato; il vincitore e i lettori no. Se il client dell'autore era offline quando è arrivata la vincitrice, il confronto si fa quando arriva (la propria versione è ancora in `revs` o nel record tenuto).

### 3.6 Sincronizzazione

Le pagine sono record come gli altri, ma tre regole tengono basso il traffico e non disturbano i client che non conoscono l'insieme (SPEC-10 R18, [ADR 0025](../adr/0025-guild-handbook-pages-shared-on-guild-revisions-local.md)):

1. **Riepilogo a parte.** I record di `handbook` non entrano nel riepilogo per autore di [SPEC-02 §4](SPEC-02-network-protocol.md#4-sincronizzazione), né in quello del censimento, ma in una voce propria per autore (chiave di `"#" .. GUID`), mandata nel campo `hb` del `HELLO`, `hbb` del `BHELLO` (un solo blocco di 3 byte: gli scrittori sono pochi; con 12 blocchi come `cb` il `BHELLO` di una gilda di 1000 autori misurava 533 B, oltre i 512 di [SPEC-11 §6.5](SPEC-11-data-trust.md), e così il `DIGEST` di risposta porta tutte le voci delle pagine) e `hb` del `DIGEST`. Un client `v0.10` non conosce i campi e li ignora: i suoi riepiloghi non cambiano e non chiede nulla all'infinito. Costo: 11 byte nel `HELLO` per ogni scrittore che ha scritto pagine.
2. **Mai in whisper a ciascuno.** Chi è più avanti **non** manda le pagine in whisper a chi manda un `HELLO` (il punto 2 di SPEC-02 §4 non vale per `handbook`). È chi è indietro che chiede, con un `REQ` con `s = "handbook"` e la chiave dell'autore (punto 3), a chi può consegnare (l'account dell'autore o un ufficiale), dopo 5–20 s casuali; la risposta va su **`GUILD`** con la chiave di coda per autore e insieme, così la stessa richiesta di più client parte una volta e **tutti** quelli che aspettano le stesse pagine le prendono dallo stesso invio. Chi risponde ignora per 60 s un'altra richiesta dello stesso autore e insieme dopo averla servita; un client che vede passare su `GUILD` le pagine che stava per chiedere non chiede più.
3. **Testi lunghi in parti.** Un `REC` di `handbook` porta **una pagina** se la pagina supera 1 KB, altrimenti più pagine fino ai 2,5 KB di SPEC-02 §4; il messaggio è compresso (formato `1` di SPEC-02 §2) e AceComm lo divide in parti di al massimo 255 byte, mandate in `BULK` attraverso ChatThrottleLib. Una parte persa fa perdere quel messaggio: la pagina mancante si richiede al prossimo `HELLO` di chi ce l'ha (al più 25 minuti). Una pagina di 4000 byte di testo italiano compresso pesa circa 2,7 KB sul filo, cioè circa 11 parti.

Il `REQ` delle pagine porta `g = 1` (risposta su `GUILD`); senza `g` è la richiesta su misura di `Sync:RequestSet`, con la risposta in whisper. Nel `HELLO` il campo `hb` c'è solo se il client tiene pagine (una voce per scrittore); nel `BHELLO` `hbb` c'è sempre con l'interruttore acceso (`Sync.HB_BLOCKS = 1`); il `DIGEST` di risposta a un `BHELLO` porta in `hb` le voci dei blocchi diversi, e anche lì chi è indietro chiede invece di ricevere. Costanti in `Net/Sync.lua`: `HB_REQ_DELAY` (5–20 s), `HB_REQ_AFTER` (600 s, §3.7), `HB_SERVED` (60 s). Le modifiche locali escono come `REC` su `GUILD`, accumulate per 5 s come le altre. Una pagina scritta mentre il silenzio dei boss è attivo ([SPEC-14 §10](SPEC-14-calendar-raids-season.md#10-silenzio-durante-i-boss)) aspetta la fine dell'incontro. Le pagine entrano nelle richieste su misura (`Sync:RequestSet("handbook", autore)`, SPEC-02 §4 punto 7) quando la vista apre una pagina che l'indice dice esistere ma che il client non ha ancora, con la risposta in whisper solo a chi chiede.

### 3.7 Traffico

Stima per la gilda di 50 client di SPEC-02 §4: un manuale tipico di 6 pagine da circa 1,5 KB (9 KB di testo, circa 6 KB sul filo); il manuale massimo (32 KB di testo) circa 22 KB sul filo.

| Situazione | Stima |
|---|---|
| Gilda allineata, una decina di modifiche a settimana | ogni modifica si manda una volta su `GUILD` (al più 2,7 KB); meno di **1 B/min** per client in media |
| Il giorno in cui si accende `raid` (primo scambio): nessuno ha pagine | ogni pagina va su `GUILD` una volta per ondata di richieste (regola 2): circa 6 KB per il manuale tipico, 22 KB per il massimo, per **tutta la gilda**, più una copia per ogni ondata di arrivi successivi; nei 45 minuti dello scenario di SPEC-02 §4 meno di **20 B/min** per client in media con il manuale tipico, meno di 60 con il massimo |
| Un membro nuovo | il manuale intero una volta: 6–22 KB sul filo, a pagine, in `BULK` |
| Il `HELLO` | 11 byte in più per scrittore |

Il limite di [SPEC-09 §7](SPEC-09-quality-release.md#7-budget-di-traffico-condiviso-m10) **non sale per M11**: la media resta al massimo 450 B/min a gilda in movimento, e circa 550 B/min solo nel primo scambio delle mappe della disponibilità accettato dal proprietario (SPEC-10 Q26, R17); il client più carico al massimo 2 KB/min. M11.2 misura nel simulatore (`Tests/test_handbook.lua`, con `raid` acceso, lo scenario di M10.8 con e senza il manuale massimo): se il primo scambio del manuale si somma a quello delle mappe oltre i 550 B/min, prima si riduce (il primo `REQ` di `handbook` parte solo 10 minuti dopo l'accesso, dopo il primo scambio delle mappe), poi si chiede al proprietario.

**Misurato in M11.2** (`Tests/test_handbook.lua`, 50 client, 45 minuti di ingressi e uscite, metà gilda mai entrata, le mappe della disponibilità al primo scambio, il manuale massimo di 20 pagine da 1600 byte scritto da un ufficiale all'inizio): senza attesa il manuale lasciava la media a 529 B/min ma portava il client più carico (lo scrittore, che risponde alle richieste) da 2353 a circa 2940 B/min. Con l'attesa di 10 minuti (`Sync.HB_REQ_AFTER = 600`, quindi applicata) la media è **531 B/min** (530 senza il manuale) e il client più carico **1842 B/min**: dentro il limite di SPEC-10 Q26. Il testo del simulatore si comprime meglio dell'italiano vero (circa il 65% di §3.6): in gioco i byte delle pagine saranno di più, da guardare nella prova di M11.8.

## 4. Il formato del testo (M11.3)

Un testo semplice, scritto a mano nell'editor, pensato per essere letto anche nella casella dell'editor così com'è. `Data/HandbookText.lua` lo divide in **blocchi**, riga per riga:

| Riga | Blocco |
|---|---|
| `# Titolo` | intestazione di livello 1 |
| `## Titolo` | intestazione di livello 2 (non ci sono altri livelli: `###` è testo) |
| `- testo` o `* testo` | voce di elenco puntato; due spazi prima del segno = secondo livello (massimo 2) |
| `1. testo` | voce di elenco numerato (il numero si scrive com'è) |
| riga vuota | fine del paragrafo |
| altro | testo del paragrafo; le righe consecutive si uniscono |

Dentro un blocco:

- **Collegamenti tra pagine**: `[[slug]]` (il testo è il titolo della pagina) o `[[slug|testo]]` (nel testo salvato il separatore è `¦`: lo scrittore digita `|`, che non si salva mai, e la pulizia di §4.4 lo scrive `¦`; il lettore riconosce quello). Un collegamento a una pagina che non c'è, è cancellata o è ancora un modello si mostra come testo grigio, non cliccabile.
- **Sezione di una pagina**: `[[slug#titolo]]` apre la pagina e scorre all'intestazione con quel testo (senza maiuscole).
- **Collegamento alla pagina della season**: `[[season]]` apre la vista *Season* di M10 (o, con FDCP come fonte, mostra la riga di §8.6); `[[loot]]` è la pagina del loot. Nessun'altra vista si apre da un collegamento.
- **Indirizzi web**: restano testo. Il lettore li mostra come testo selezionabile e, cliccandoli, li mette in una casella di copia (`UI/CopyBox.lua`), come la pagina *About*; il gioco non apre il browser.

### 4.1 Niente codici del gioco

Il carattere `|` introduce nel gioco colori, icone e link (`|c`, `|T`, `|H`): un testo con codici potrebbe fingere un link o un'icona. Il testo salvato **non contiene mai `|`** né caratteri di controllo (tranne l'a capo): l'editor, al salvataggio, toglie i link agli oggetti e le icone lasciando il nome tra parentesi quadre (`[Thunderfury]`), toglie i colori e scrive un `|` rimasto come `¦`. Chi riceve rifiuta un corpo con `|` (HBK-02), quindi il lettore non deve raddoppiare nulla.

### 4.2 Come si mostra

Il lettore mette **un `SimpleHTML` per blocco**, uno sotto l'altro (`SimpleHTMLAPI` è nel dump di Forever `1.60.1`, solo consultato): così conosce l'altezza di ogni blocco (`GetContentHeight`, con una stima finché il gioco non la dà) e può scorrere a un'intestazione o a una riga. Ogni blocco è `<h1>`, `<h2>` o `<p>`; le voci di elenco sono `<p>` con `•` o il numero, il secondo livello rientrato. I collegamenti che si possono seguire sono `<a href="acc:<n>">` (il numero indica la destinazione nel blocco) con `OnHyperlinkClick`; gli altri sono testo grigio. Il testo passa dall'escape HTML (`&`, `<`, `>`) prima della conversione: nessun tag scritto dallo scrittore arriva al gioco. I caratteri e i colori sono quelli del tema ([ui-style](ui-style.md)) con `SetFontObject` per ogni tipo di testo. **[verificare]** nel client che SimpleHTML mostri i caratteri dell'addon, i collegamenti e l'altezza del testo; se non va, si ripiega su un `FontString` per blocco e pulsanti trasparenti per i collegamenti, con lo stesso formato del testo (M11.8).

### 4.3 Ricerca

`HandbookText.Search(query)`: almeno 2 caratteri, senza maiuscole e senza accenti (le vocali accentate italiane valgono la vocale), su titoli e corpi delle pagine che il giocatore vede (§5.1). Risultati: la pagina, l'intestazione più vicina sopra la riga trovata e la riga, al massimo 50; un clic apre la pagina a quella riga. Si cerca anche nella parte fissa della pagina del loot (§8): il nome del sistema e dell'addon.

### 4.4 Pulizia

Ogni testo che entra (scritto, incollato, ricevuto da uno scrittore) passa da `HandbookText.Clean`: toglie i codici di §4.1, i caratteri di controllo tranne `\n`, gli spazi in fondo alle righe, più di due righe vuote di fila, e normalizza `\r\n` in `\n`. Un titolo perde anche gli a capo. Il risultato deve stare nei limiti di §3.2 **dopo** la pulizia.

## 5. Il lettore (M11.3)

### 5.1 Chi vede che cosa

Ogni membro con l'addon vede tutte le pagine vive e non `tpl`, anche offline, dall'ultima sincronizzazione (HB-04). Gli scrittori vedono in più le pagine `tpl` (segnate *Template, not yet published*) e i pulsanti dell'editor. Non ci sono pagine per soli ufficiali: il manuale è della gilda, e i record arrivano a tutti (una pagina riservata sarebbe solo una regola dell'interfaccia, come in SPEC-10 Q17); chi vuole tenere un testo fra ufficiali usa le note estese di M8.

### 5.2 La vista *Handbook*

- **A sinistra, l'elenco** delle pagine per `order`, poi titolo: il titolo, il segno *Updated* (§5.4) e, per gli scrittori, *Template* o *Over the limit*. La casella di ricerca è quella del pannello, a destra delle schede, come nelle altre viste ([SPEC-04 §2](SPEC-04-ui-guild-tab-shell.md#2-il-pannello)); con almeno 2 caratteri i risultati prendono il posto dell'elenco; in fondo, per gli scrittori, *New page* e, per gli ufficiali, *Writers* (§3.3). Le frecce su e giù accanto a una pagina (scrittori) cambiano `order` scrivendo una revisione della pagina.
- **A destra, il lettore**: il titolo, sotto "Updated <data> by <nome>", poi il testo (§4.2), in un'area che scorre. Per gli scrittori *Edit*, *Revisions*, *Delete* (con un secondo clic **Confirm**: "Delete this page for the whole guild?").
- **Senza pagine**: "No handbook pages yet." per i membri; per gli scrittori anche *Create the default pages* (§7.1), finché la semina non è avvenuta.
- **La pagina del loot** (`P:loot`) ha sopra il testo la parte fissa di §8.
- `/accord handbook <slug>` apre la vista su una pagina; `/accord handbook` sull'ultima letta o sulla prima.
- **Fatto in M11.3**: elenco, ricerca, segni, *Mark all as read*, il lettore con *Back*, il comando.
- **Fatto in M11.4**: *New page* e *Writers* sotto l'elenco; le frecce sono sulla pagina **scelta**, al posto del suo segno; *Edit*, *Revisions* e *Delete* sono sotto il testo. Una pagina nuova va dopo l'ultima (`order` + 5). Spostare scrive di norma **una** revisione (della pagina o della vicina, con un `order` che la mette al suo posto); solo se gli `order` uguali non lasciano posto le pagine si rinumerano (`Handbook:MovePlan`). *Writers* è un menu dei gradi 1–9: quelli degli ufficiali si leggono ma non si tolgono.
- *Create the default pages* arriva con M11.5, la parte fissa della pagina del loot con M11.6.

### 5.3 Storia della navigazione

*Back* torna alla pagina precedente aperta da un collegamento (al massimo 20 passi, solo in memoria).

### 5.4 Il segno "aggiornata"

Una pagina è **aggiornata** quando la sua `rev` è più alta di `handbook.read[id]` dell'account e l'ultima revisione non è stata scritta da un personaggio dell'account stesso. Si toglie quando la pagina resta aperta nel lettore per 2 secondi (non con un passaggio veloce nell'elenco) o con *Mark all as read*. Al primo uso (nessun `read`) tutte le pagine sono aggiornate: un membro nuovo vede che c'è da leggere. Il numero delle pagine aggiornate compare sul pulsante della vista e, se l'interruttore `actions` è acceso, come una riga del Centro azioni (fornitore `handbook`, urgenza 1: "N handbook pages updated"); nessun avviso in chat per una pagina aggiornata. È il criterio di uscita di M11: un ufficiale cambia il regolamento, un membro che entra dopo lo legge segnato come aggiornato.

## 6. L'editor (M11.4)

Solo per gli scrittori (`Handbook.IsWriter`), dentro la vista *Handbook* (`UI/HandbookEditor.lua`, M11.4). L'editor prende tutta la vista finché è aperto; chi smette di essere scrittore lo perde subito (la bozza resta).

- **Titolo** (una riga) e **testo** (casella a più righe che scorre, `EditBox` con `SetMultiLine`). Le caselle **non** hanno `SetMaxBytes` né `SetMaxLetters`: taglierebbero in silenzio un testo incollato, anche uno che dopo la pulizia ci sta (un link a un oggetto è molto più lungo del suo nome). Il limite si vede dal conteggio e da **Save** spento.
- **Lunghezza contro il limite**, sempre visibile e dopo la pulizia di §4.4: "3 120 / 4 000 bytes", e il totale del manuale "21 400 / 32 000". Oltre il limite il numero diventa del colore di errore e **Save** è spento, con il motivo ("Too long by 120 bytes"). Spengono **Save** anche il titolo vuoto o oltre `TITLE_MAX`, il totale del manuale e le 20 pagine (`Handbook:Check`).
- **Preview**: un pulsante alterna la casella e l'anteprima del lettore (§4.2), con i collegamenti a pagine mancanti segnati.
- **Save** scrive la revisione (§3.5 per la modifica sopra una revisione cambiata; anche una cancellazione arrivata nel frattempo si mostra così). Senza modifiche non scrive nulla, salvo pubblicare un modello. **Keep mine** scrive sopra la revisione mostrata: se ne arriva un'altra prima del clic, si mostra quella. **Cancel** chiede conferma (un secondo clic) se il testo è cambiato. La **bozza** si tiene in `handbook.draft` a ogni cambio (una sola, per account; id `new` per una pagina nuova): se il gioco si chiude, all'apertura dell'editor sulla stessa pagina c'è *Restore draft*; una bozza offerta e non ripresa resta anche se si annulla una modifica fatta nel frattempo.
- **Revisions**: l'elenco delle revisioni viste da questo client (§3.5): numero, autore, data, lunghezza, *lost* per quelle perse in un conflitto. Scegliendone una si vede l'anteprima; **Restore** la scrive come **revisione nuova** (`rev` = quella tenuta + 1), mai riportando indietro il numero: tutti i client la ricevono come una modifica qualsiasi.
- Una pagina cancellata non compare nell'elenco, ma se il client ne ha le revisioni gli scrittori la trovano in *Deleted pages* (in fondo all'elenco), con *Restore*.
- L'editor non si apre in combattimento; il salvataggio è sempre un clic.

## 7. Le pagine predefinite (M11.5)

### 7.1 I modelli

Sei pagine, con slug, `order` e titolo fissi; il corpo ha **solo intestazioni** e, sotto ognuna, una riga vuota (HB-03). I testi sono in `Data/HandbookDefaults.lua`, nella lingua dell'interfaccia dello scrittore che semina (inglese o italiano, da `Locale`); nessuna parola della gilda del proprietario.

| Slug | `order` | Titolo (en / it) | Intestazioni (en) |
|---|---|---|---|
| `info` | 10 | Guild info / Informazioni sulla gilda | About us; Schedule; Communication; Officers |
| `rules` | 20 | Rules / Regolamento | General; Chat; Raids and dungeons; Guild bank; Sanctions |
| `faq` | 30 | FAQ / Domande frequenti | (una sola intestazione) Questions |
| `raid` | 40 | Raid management / Gestione dei raid | Schedule; Sign-ups; Composition and bench; Preparation; During the raid |
| `roster` | 50 | Roster management / Gestione del roster | The season roster; Ranks; Alts; Inactivity |
| `loot` | 60 | Loot management / Gestione del loot | Loot system; Rules; Questions |

La pagina `roster`, sotto *The season roster*, ha una riga fissa del modello: `[[season]]`, il collegamento alla vista della season di M10 che, secondo la fonte `raid` scelta dagli ufficiali, mostra il roster di Accord o quello di FDCP (§8.6). La pagina `loot`, sotto *Loot system*, ha `[[season]]` con il testo "Loot follows the declared spec" / "Il loot segue la specializzazione dichiarata" (roadmap M11.6). Sono le uniche righe non vuote dei modelli: collegamenti, non testo della gilda.

### 7.2 Una volta sola

- **Chi semina**: uno scrittore, con un clic su *Create the default pages* nella vista vuota (non in automatico all'accesso: due scrittori che entrano insieme non scrivono due volte, e una gilda che non vuole i modelli non li riceve). Il clic scrive le sei pagine con `tpl = true` e il record `seeded` (§7.3).
- **Mai più**: il pulsante c'è solo se il client non vede né il record `seeded` né nessuna pagina (viva o cancellata). Una pagina predefinita cancellata resta un record `del` per sempre (§3.1), con una `rev` di almeno 2. Una semina tardiva (un client che non aveva ancora ricevuto né `seeded` né il `del`) scrive i modelli con `rev` 1, che perdono contro il `del` su ogni client che lo tiene, e il `del` arriva anche a lei con la sincronizzazione: la pagina non torna. Due semine contemporanee scrivono gli stessi id con `rev` 1 e vince la più recente, senza doppioni. M11.5 lo prova nel simulatore.
- **Un modello diventa pagina** al primo salvataggio di uno scrittore, che toglie `tpl`. Un modello non salvato non si mostra ai membri e non conta nei limiti delle pagine vive per i membri (conta per `MAX_PAGES` e `TOTAL_MAX`).

### 7.3 Il record `seeded`

Nell'insieme `handbook`, id `seeded`: `{ at = ora della semina, by = versione dell'addon }`, scritto da uno scrittore, mai cancellato, stesse regole di HBK-01. Serve a chi non ha ancora ricevuto le pagine (riepilogo per autore) a non proporre la semina; il pulsante aspetta anche che il primo `HELLO` della sessione abbia avuto risposta (2 minuti dopo l'accesso), per non seminare prima della sincronizzazione.

## 8. La pagina del loot (M11.6)

La pagina `P:loot` è una pagina come le altre (testo degli scrittori, modello di §7.1) con, sopra il testo, una **parte fissa** costruita da `UI/LootPage.lua` con i dati di `guildcfg` e del riconoscimento degli addon. Se la pagina `loot` è stata cancellata, la parte fissa resta raggiungibile dalla vista *Raid* (sezione *Loot*), così le scelte degli ufficiali non si perdono.

### 8.1 Il record `loot` di `guildcfg`

Un quarto record di `guildcfg`, scritto solo da ufficiali e Guild Master (NET-12, `authorAny`), dietro `raid`:

| Campo | Valori | Note |
|---|---|---|
| `system` | `rolls` \| `softres` \| `council` \| `dkp` \| `credits` \| `other` \| `none` | il **sistema di loot** della gilda; predefinito `none` (non detto) |
| `systemName` | 1–32 byte | solo con `system = other` |
| `addon` | un id di `Integrations.KNOWN` di tipo `loot` o `both` \| `other` \| `none` | l'**addon del loot**; predefinito `none` |
| `addonName` | 1–32 byte | solo con `addon = other` |
| `addonFolder` | 1–64 byte, lettere, cifre, `_`, `-` e `.` | solo con `addon = other`: la cartella dell'addon, per il riconoscimento (§8.3) |
| `url` | indirizzo CurseForge, 1–120 byte | solo con `addon = other` (§8.4) |

Un record con altri campi o valori si rifiuta (`owner`). Senza record vale `none` e `none`. I nomi dei sistemi nell'interfaccia: *Rolls (MS/OS)*, *Soft reserve*, *Loot council*, *DKP*, *Credits*, *Other*; nessun sistema d'asta d'oro (GDKP, vietato su Forever secondo la nota del sondaggio, [M11](../roadmap/M11-loot-handbook.md#addons-on-wow-forever)), che si può scrivere solo come *Other* dalla gilda.

**Qualunque addon di CurseForge** (risposta del proprietario a SPEC-10 Q30, 2026-11-26). Oltre agli addon di `KNOWN`, la gilda può scegliere come addon del loot qualunque addon di loot pubblicato su CurseForge, con `addon = other`: un ufficiale scrive il nome (`addonName`), la cartella (`addonFolder`) e l'indirizzo CurseForge (`url`). Per un addon così Accord fa solo il **livello 0**: lo stato su questo client (`Integrations:Detect` sulla cartella data) e chi lo ha caricato (§8.3). Il **livello 1**, la lettura dei suoi dati, resta per gli addon con un'API pubblica documentata e un provider nel codice di Accord, oggi solo FDCP (regole d'integrazione di [M10](../roadmap/M10-calendar-raids.md#integration-rules-owner-2026-11-24)); un addon che ne pubblica una si aggiunge a `KNOWN` con un passo suo.

**Una sola fonte per dato.** La fonte `loot` di `sources` (`none` | `fdcp`, M10.2) dice da dove Accord legge i crediti e le regole; l'addon del loot dice che cosa usa la gilda. Da M11.6 si scelgono **insieme**, nella parte fissa della pagina del loot (la vista *Raid* mostra la scelta e rimanda lì): scegliere FDCP come addon scrive anche `sources.loot = fdcp`, scegliere un altro addon o nessuno scrive `sources.loot = none`, nella stessa operazione (due record, lo stesso clic). Un client che riceve `sources.loot = fdcp` con `loot.addon ≠ fdcp` (due ufficiali insieme) mostra l'addon e non legge FDCP. È la proposta di SPEC-10 Q30.

### 8.2 La parte fissa

Dall'alto:

1. **Loot system**: il nome del sistema (o "Not set" per gli scrittori; per i membri la riga non c'è).
2. **Loot addon**: il nome dell'addon scelto, con lo stato su **questo** client: *Loaded* (con la versione), *Not loaded*, *Not installed* o *Folder not confirmed* (dal riconoscimento di M10.2, `Integrations:Detect`); per FDCP anche *Open FDCP*.
3. **Download**: l'indirizzo in una casella di sola lettura da copiare (§8.4), se l'addon non è caricato su questo client o sempre per gli scrittori.
4. **Who has it** (§8.3).
5. **FDCP rules** (§8.6), solo con `sources.loot = fdcp`.
6. Senza addon scelto, solo il suggerimento di §8.5.

Gli ufficiali vedono *Change* accanto a sistema e addon: un menu con i valori di §8.1, e per *Other* i campi del nome e dell'indirizzo. Il cambio è un clic su *Save* (nessuna conferma: si può sempre cambiare di nuovo).

### 8.3 Chi ha l'addon

Dal censimento degli addon di M9.9 attraverso `Integrations:Holders(id)` (M10.2, [SPEC-14 §3.4](SPEC-14-calendar-raids-season.md#34-chi-ha-gli-addon-in-gilda-m102)), per l'addon scelto (di `KNOWN`; con `other` si cerca la cartella `addonFolder`, senza maiuscole, tra le cartelle del censimento, e se non si trova la riga lo dice):

- **tutti** vedono il conteggio: "14 of 22 members who share their list have it loaded", con le versioni più usate;
- **ufficiali e Guild Master** vedono **chi** lo ha, con la versione, e **chi non ce l'ha**: gli account della gilda che condividono l'elenco e non lo hanno caricato, e a parte quanti non condividono o non hanno Accord (mai contati come mancanti); ognuno vede sempre la propria riga. È la regola di `Census:Who` (`Census.NAMES_VISIBLE_TO`, SPEC-10 Q11, Q17), non una nuova: SPEC-10 Q31.
- Con il censimento spento, nessuno che condivide, o il giocatore che non condivide, una riga lo dice invece di una tabella vuota.
- **Senza addon scelto non si controlla nulla**: nessuna chiamata a `Integrations:Holders` e nessuna riga (criterio di M11.6).

La parte non scrive e non manda nulla: legge il censimento che c'è già.

### 8.4 L'indirizzo di download

- Per un addon di `KNOWN` l'indirizzo è **dell'addon Accord**, non della gilda: un campo `url` nuovo di `Integrations.KNOWN` (la pagina pubblica del progetto: CurseForge, GitHub, Wago o WoWInterface), scritto e controllato nel codice. FDCP: `https://github.com/Finland6738/finland-dragon-credit-points/releases`. Un addon di `KNOWN` senza `url` confermato non mostra la casella.
- Per `other` l'indirizzo lo scrive un ufficiale, e si accetta solo se comincia con `https://` e il nome del sito è uno di `Loot.URL_HOSTS` = `www.curseforge.com`, `curseforge.com`: **solo CurseForge** (risposta del proprietario a SPEC-10 Q32, 2026-11-26); altrimenti il record si rifiuta (`owner`), sia da chi scrive sia da chi riceve. Niente spazi, `|` o caratteri di controllo.
- La casella è di **sola lettura** (come in *About*: si seleziona al clic e torna com'era se il giocatore ci scrive); il gioco non apre il browser. Sopra: "Copy this address into your browser. Install addons only from sources you trust."

### 8.5 Il suggerimento di FDCP

Con `addon = none` la parte fissa **non mostra nulla sugli addon** (nessuno stato, conteggio o casella) e, **solo agli scrittori** (SPEC-10 Q33), una riga della lingua dell'interfaccia: "No loot addon chosen. Finland Dragon Credit Points (FDCP), from the same family as Accord, keeps loot credits and can be read here." / "Nessun addon del loot scelto. Finland Dragon Credit Points (FDCP), della stessa famiglia di Accord, tiene i crediti del loot e si può leggere qui.", con l'indirizzo di FDCP nella casella di §8.4 e *Choose FDCP* per gli ufficiali. È una chiave di `Locale` (`LOOT_SUGGEST_FDCP`), non un dato della gilda: non si manda, non si salva e non entra nel testo della pagina.

### 8.6 FDCP accanto alla pagina

Già fatto in M11.7 ([ADR 0022](../adr/0022-integrations-with-raid-and-loot-addons.md), `Data/FDCP.lua`, `UI/Raid.lua`): con la fonte `loot` = `fdcp` e FDCP al livello 1 (`API_VERSION == 1`) la vista *Raid* mostra il **riassunto delle regole** (`FDCP.Rules()`: preset, metrica, crediti iniziali, costi per categoria e numero di partecipanti o *council*, moltiplicatore della risposta, ingresso tardivo, effetto della panchina, penalità, modo di assegnazione) e i propri crediti e posto in coda, e la scheda del membro *Loot (FDCP)*.

**Che cosa si sposta in M11.6:**

- il **riassunto delle regole** passa dalla vista *Raid* alla parte fissa della pagina del loot (punto 5 di §8.2), in sola lettura, **mai copiato nel testo della pagina** (non entra in `body`, non si manda: si rilegge da FDCP a ogni apertura); sul client di un membro è il preset predefinito del Patto, e la riga lo dice ("FDCP shows members the preset's default rules; officers see the guild's", finché FDCP non dà le regole della gilda, richiesta F5);
- i **propri crediti e posto in coda** compaiono anche nella parte fissa, sotto le regole;
- la vista *Raid* tiene la scelta della fonte `raid`, il pool, la formazione e la panchina, e al posto del riassunto un collegamento "Loot rules are on the handbook's loot page";
- la scelta della fonte `loot` si sposta nella pagina del loot (§8.1);
- al livello 0 (FDCP presente ma API sconosciuta) la parte fissa mostra solo stato, versione e *Open FDCP*; FDCP assente: *Not installed* e la casella di download.

Le callback di FDCP restano registrate solo finché FDCP è una fonte (ADR 0022 punto 8); `RULES_CHANGED` e `CREDITS_CHANGED` ridisegnano la parte fissa se è aperta.

## 9. FDCP: che cosa dà al client di un membro e di un ufficiale

Dall'API pubblica di FDCP (`FinlandDragonCreditPointsAPI`, `API_VERSION` 1, passo M8-1 di FDCP, sua ADR 0009). Il client di un ufficiale legge il registro di FDCP (`GetSource() = "LEDGER"`); quello di un membro solo la fotografia dei crediti che un ufficiale ha mandato (`"SNAPSHOT"`).

| Dato | Funzione | Client di un membro | Client di un ufficiale | Dove in Accord |
|---|---|---|---|---|
| Stato, versione, fonte | `IsReady`, `GetVersion`, `GetSource` | sì | sì | livello (M10.2), righe di stato |
| Season | `GetSeason` | sì | sì | vista *Season* |
| Pool: main, fazione, classe, ruolo, MS1, stato, alt | `GetPool`, `GetMember` | solo i main che giocano | tutti | vista *Season*, conteggi |
| MS2, OS, gemello (`twin`), disponibilità dichiarata (`avail`) | `GetPool` | **no** (richiesta F1) | sì | conteggi, mappa della disponibilità |
| Crediti, posto in coda | `GetCredits`, `GetCreditList` | sì, gli stessi | sì | scheda del membro, pagina del loot |
| Serata: formazione e panchina | `GetNight` | **no** (`nil`, richiesta F2) | sì | vista *Events*, vista *Raid* |
| Regole della gilda | `GetRules` | **no**: i predefiniti del preset Patto (`source = "DEFAULT"`, richiesta F5) | sì (`source = "GUILD"`) | pagina del loot (§8.6) |
| Callback | `RegisterCallback` | sì | sì | ridisegno, solo finché FDCP è una fonte |
| Presenze e assenze, nota del roster, registro, audit, consiglio | — | mai | mai (non esposti) | — |

Accord non chiede a FDCP nulla di nuovo per M11: le richieste di [FDCP-API-requests](../integrations/FDCP-API-requests.md) restano quelle (F5 è quella che serve alla pagina del loot). Accord non salva e non manda nulla di ciò che legge da FDCP (ADR 0022 punto 9).

## 10. Gli addon di loot e di roster su Forever

Il sondaggio è nel file della milestone ([M11, Addons on WoW Forever](../roadmap/M11-loot-handbook.md#addons-on-wow-forever)), aggiornato in M11.1 (2026-11-26) dalle pagine pubbliche. In breve:

- **Nessun addon di loot** oltre a FDCP ha un'API pubblica documentata per altri addon: tutti restano al **livello 0** (ADR 0022 punto 3).
- Confermati su Forever dalla loro pagina: **Gargul** (file Forever del 2026-11-24), **RaidCore** (Interface 16001, 2026-10-26), e il nuovo **TLC - Loot Council** (2026-11-19, "built and tested" per Forever), che M11.6 aggiunge a `Integrations.KNOWN` con la cartella non confermata.
- **WLC**, **Forever Loot Manager**, **NostalgiaForeverLC** e **RollForMe** non sono stati ritrovati in questo sondaggio: restano in `KNOWN` (un addon con una cartella sbagliata semplicemente non si trova) finché la prova in gioco di M11.8 non dice altro.
- Non girano su Forever (nessuna versione Forever sulla pagina): l'estensione Loot Council di Gargul, MeltdownLC, LootReserve; RCLootCouncil resta senza file Forever.
- Le cartelle confermate restano solo quella di FDCP; le altre si confermano in gioco (M11.8, come previsto da M10.2).

## 11. Test per passo

| Passo | File | Casi |
|---|---|---|
| M11.2 | `Tests/test_handbook.lua` | una pagina di un non scrittore si rifiuta (`authority`), anche come revisione; un grado scelto scrive, un grado rinominato no; un ex scrittore: le pagine restano, le revisioni nuove no; due modifiche della stessa revisione tengono la più recente su tutti i client e l'autore della perdente ha l'avviso e la revisione `lost`; salvare sopra una revisione cambiata non sostituisce in silenzio; limiti (corpo, titolo, pagine, totale, ritmo); revisioni locali (5) senza traffico; riepilogo a parte ignorato da un client che non lo conosce; richieste servite una volta su `GUILD` a più client; traffico nel simulatore (§3.7); interruttore spento |
| M11.3 | `Tests/test_handbook_view.lua` (testo e vista) | blocchi, elenchi, collegamenti (vivi, mancanti, a sezione, `[[season]]`), escape HTML, nessun `|`; ricerca senza maiuscole e accenti; lettura offline; il segno "aggiornata" si toglie leggendo e non per le proprie modifiche |
| M11.4 | `Tests/test_handbook_editor.lua` | un testo oltre il limite non si salva (dopo la pulizia); anteprima; bozza; *Restore* crea una revisione nuova; pagina cancellata ripristinata |
| M11.5 | `Tests/test_handbook_defaults.lua` | una gilda nuova riceve i modelli una volta; due semine insieme non fanno doppioni; una pagina cancellata non torna, nemmeno da un client che semina dopo; i modelli non hanno testo oltre a intestazioni e collegamenti; i membri non vedono i modelli |
| M11.6 | `Tests/test_loot_page.lua` | sistema e addon scritti solo da ufficiali; addon e fonte `loot` scritti insieme; chi lo ha (ufficiali) e i conteggi (tutti); senza addon nessun controllo; il suggerimento è una chiave di `Locale` e solo per gli scrittori; indirizzo `other` solo dai siti ammessi; regole di FDCP accanto alla pagina e mai nel testo; FDCP assente o al livello 0 |

## 12. Cosa resta da verificare nel client

Nella prova di M11.8 (`docs/checklists/M11.md`):

- SimpleHTML con i caratteri dell'addon, i collegamenti cliccabili e lo scorrimento di una pagina lunga;
- la casella a più righe con 4000 byte, l'incolla di un testo lungo (nessun taglio) e il cursore che resta visibile scorrendo;
- che un link a un oggetto incollato nell'editor diventi `[Nome]` al salvataggio;
- una pagina di 4000 byte che arriva intera a un membro (circa 11 parti) durante una serata normale, e senza rifiuti per limite di velocità con FDCP caricato;
- il criterio di uscita: un ufficiale cambia il regolamento, un membro che entra dopo lo vede segnato come aggiornato;
- la pagina del loot con l'addon della gilda scelto e gli ufficiali che vedono chi lo ha caricato; le cartelle degli addon di loot su Forever (Gargul, RaidCore, TLC);
- il riassunto delle regole di FDCP accanto alla pagina, sul client di un ufficiale e di un membro.
