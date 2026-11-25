# SPEC-13: Centro azioni e avvisi

Specifica della milestone M9 ([roadmap](../roadmap/M9-action-center.md)): un solo posto per ciò che aspetta il giocatore (**Centro azioni**), una cronologia degli avvisi con le **ore di quiete** e un **riepilogo all'accesso**; un **cercagruppi solo per la gilda** con candidature e inviti; la tabella degli **addon della gilda**. Ogni sezione dice il passo che la realizza; i passi M9.2–M9.9 non hanno scelte di progetto da fare oltre a queste. Le scelte che spettano al proprietario sono in [SPEC-10](SPEC-10-risks-open-questions.md) (Q17–Q19): il proprietario le ha accettate come proposte (2026-11-25).

Nomi di codice, campi e testi dell'interfaccia in inglese (con la traduzione italiana nel file di lingua `itIT.lua`, [ADR 0015](../adr/0015-interface-and-documentation-languages.md)). Le ore dei record sono ore del server in secondi (`Compat.ServerTime()`); le **ore di quiete** sono ore locali del computer del giocatore (`date("*t")`), perché il giocatore pensa nel proprio fuso.

## 1. Moduli, interruttori, dati locali

### 1.1 Interruttori

Una release non porta funzioni a metà (decisione del proprietario, 2026-11-25, [`Core/Features.lua`](../../AzerothAccord/Core/Features.lua)). M9 aggiunge tre interruttori, **spenti** dal passo che aggiunge il codice fino al passo M9.10, che li accende prima di `v0.9.0`:

| Interruttore | Passi | Spento vuol dire |
|---|---|---|
| `actions` | M9.2–M9.5 | nessuna vista *Action Center*, nessun avviso nuovo (gli avvisi della banca di M5 restano come oggi, §3.2), nessun riepilogo, nessuna ora di quiete |
| `groups` | M9.6–M9.8 | nessuna vista *Groups*; l'insieme `groups` non si accetta né si manda (`Store.SETS.groups.feature = "groups"`); `GAPP` e `GASK` si ignorano |
| `census` | M9.9 | nessuna vista *Guild addons*; l'insieme `addons` non si accetta né si manda; nessuna riga in *What I share* |

Come per `raid`, i moduli chiedono `Features.On(nome)` quando agiscono, mai una volta al caricamento; i test accendono l'interruttore; `Tests/test_features.lua` controlla che spento non si veda e non si mandi nulla.

### 1.2 File nuovi

| File | Contenuto | Passo |
|---|---|---|
| `Data/Actions.lua` | il Centro azioni: registro dei fornitori, elenco ordinato (§2) | M9.2 |
| `Data/Notify.lua` | avvisi: livelli, cronologia, uscite, ore di quiete, contro le inondazioni (§3, §4) | M9.3, M9.4 |
| `Data/Digest.lua` | riepilogo all'accesso (§5) | M9.5 |
| `Data/GroupActivities.lua` | la tabella delle spedizioni e delle incursioni (§6.4) | M9.6 |
| `Data/Groups.lua` | annunci, candidature, inviti, `GASK` (§6) | M9.6 |
| `Data/GameFinder.lua` | l'annuncio privato nel Group Finder del gioco (§7) | M9.8 |
| `Data/Census.lua` | censimento degli addon (§8) | M9.9 |
| `UI/Actions.lua`, `UI/Toast.lua` | la vista *Action Center* (pagine *Inbox* e *Notices*), il toast | M9.2, M9.3 |
| `UI/Groups.lua` | la vista *Groups* | M9.7 |
| `UI/GuildAddons.lua` | la vista *Guild addons* | M9.9 |

`Config.VIEWS` aggiunge `actions`, `groups`, `addons`. Comandi: `/accord inbox`, `/accord groups`, `/accord addons` (aprono la vista; con l'interruttore spento rispondono come un comando sconosciuto).

### 1.3 Eventi del Bus

`ACTIONS_CHANGED()` (l'elenco del Centro azioni è cambiato), `NOTICE_POSTED(entry)` e `NOTICES_CHANGED()` (cronologia), `GROUPS_CHANGED(id)` (un annuncio), `APPLICANTS_CHANGED(id)` (le candidature di un annuncio, sul client del capo o del candidato), `CENSUS_CHANGED()`. Si aggiungono all'intestazione di `Core/Bus.lua`.

### 1.4 Impostazioni (schema 4)

`Config.SCHEMA_VERSION` passa a 4; la migrazione dell'account aggiunge, solo dove mancano:

| Chiave | Tipo e predefinito | Sezione |
|---|---|---|
| `account.settings.notify` | tabella `{ [modulo] = { chat, toast, sound, off = { [tipo] = true } } }`, predefiniti di §3.2 | §3.2 |
| `account.settings.quiet` | `{ on = false, from = 23, to = 8, instances = true }`, ore intere 0–23, `from ≠ to` | §4 |
| `account.settings.shareAddons` | booleano, `true` | §8.3 |
| `account.settings.groupFilter` | `{ kinds = {}, fits = true, roles = {} }` (i filtri salvati della vista Groups) | §6.9 |

`account.settings.notifyOfficer` e `notifyDecision` (M5) **restano** con lo stesso nome e lo stesso predefinito: sono i due interruttori dei tipi della banca (§3.2). La migrazione del personaggio crea `char.groups = { next = 0, apps = {}, mine = {}, game = nil }` (§6.5, §7).

## 2. Centro azioni (M9.2)

Una vista con le cose che **aspettano il giocatore**. Non salva nulla di suo: ogni riga viene, ogni volta, da un **fornitore** che legge i dati del proprio modulo. Una cosa risolta nella sua vista sparisce perché il fornitore non la restituisce più.

### 2.1 Il fornitore

`Actions:Register(id, def)`; `id` è un nome breve (`bank`, `craft`, `officer`, `groups`, …), `def`:

| Campo | Significato |
|---|---|
| `label` | chiave del testo del fornitore (chip del filtro, tooltip) |
| `order` | ordine tra fornitori a parità di urgenza e ora |
| `events` | eventi del Bus dopo cui rileggere (per esempio `STORE_CHANGED`, `OPS_CHANGED`, `ROLE_CHANGED`) |
| `feature` | facoltativo: il nome di un interruttore di `Features`; spento, il fornitore non c'è |
| `visible()` | facoltativo: `false` = il fornitore non c'è per questo personaggio (per esempio i soli ufficiali) |
| `items(now)` | restituisce l'elenco delle righe |

Una **riga**: `{ key, urgency, time, title, detail, who, open, dismiss }`:

- `key` (stringa, al massimo 64 caratteri) unica nel fornitore; `urgency` 3, 2 o 1 (§2.2); `time` = l'ora del server da cui la cosa aspetta (apertura della richiesta, arrivo della candidatura);
- `title` (al massimo 80 caratteri) e `detail` (facoltativo, 120) già nella lingua dell'interfaccia; `who` facoltativo, il nome da mostrare (tagliato con i puntini, SPEC-11 §6.6); `mark` facoltativo (stringa o numero), che cambia quando cambia la cosa stessa (§5.4);
- `open()` apre la vista che risolve la riga (sempre presente); `dismiss()` solo per i **promemoria locali** (§2.3, `craft`), che il giocatore chiude a mano.

Regole:

- **ACT-01** `items` legge e basta: non scrive record, non manda messaggi, non stampa. Un errore si prende con `pcall`: il fornitore si salta in quell'aggiornamento e l'errore va in `/accord debug` (come il Bus).
- **ACT-02** Al massimo **50 righe per fornitore**: oltre, le prime 50 secondo §2.2 più una riga `and N more` che apre la stessa vista. Al massimo 200 righe in tutto.
- **ACT-03** L'elenco si ricalcola dopo un evento di `events` (raccolti per 0,5 s), al cambio di ruolo o di gilda, all'apertura della vista e ogni 60 s (le urgenze che dipendono dall'ora). Emette `ACTIONS_CHANGED` solo se l'elenco è cambiato (impronta di chiavi, urgenze e titoli).
- **ACT-04** Il Centro azioni non risolve nulla da sé: il clic apre la vista del modulo, dove il giocatore agisce. Fa eccezione solo `dismiss()` dei promemoria locali.

### 2.2 Urgenza e ordine

| Urgenza | Nome | Quando |
|---|---|---|
| 3 | *Now* / *Adesso* | qualcuno aspetta ora ed è online (un candidato al proprio gruppo), o la cosa scade entro 24 ore |
| 2 | *To do* / *Da fare* | tocca al giocatore (una richiesta in banca da decidere o consegnare, azioni manuali in coda) |
| 1 | *Reminder* / *Promemoria* | il giocatore aspetta gli altri, o è solo da ricordare |

Ordine: urgenza decrescente, poi `time` crescente (chi aspetta da più tempo prima), poi `order` del fornitore, poi `key`. Il **numero** della vista (il distintivo della scheda, `Shell.BadgeText`, e la riga del tooltip del Compartment `Action Center: N to do`) conta le righe di urgenza 2 e 3.

### 2.3 I fornitori di M9.2

| Fornitore | Chi | Righe | Urgenza | Apre | Sparisce quando |
|---|---|---|---|---|---|
| `bank` (`Data/BankInbox.lua`) | ufficiali e GM | ogni richiesta **aperta** (`Bank request: <oggetto> x<n>`, `who` = richiedente, `time` = apertura) e ogni richiesta **approvata** non ancora consegnata (`Deliver: …`) | 2 | la casella della banca (*Inbox*) su quella richiesta | è decisa, consegnata, annullata o scade |
| `bank` | il richiedente (ogni membro) | le **proprie** richieste aperte o approvate (`Waiting for an officer` / `Approved`) | 1 | le proprie richieste nella vista Bank | è chiusa |
| `craft` (`Data/Recipes.lua`) | chi ha chiesto | ogni richiesta di crafting fatta con *Request craft* (`CRAFT_REQUESTED`) negli ultimi 7 giorni: `You asked <nome> to craft <ricetta>` | 1 | l'elenco delle ricette di quel membro | il giocatore la chiude (*Done*, `dismiss`) o dopo 7 giorni |
| `officer` (`Data/OfficerOps.lua`) | ufficiali e GM (`Officer.CanSee("inactivity")`) | le azioni manuali **aperte** della propria coda, **una riga per tipo** con il numero (`3 promotions to do in the game`) | 2 | la pagina *Queue* | la coda di quel tipo è vuota |
| `officer` (`Data/Absence.lua`) | ufficiali e GM | ogni assenza dichiarata il cui rientro è oggi o negli ultimi 3 giorni: `<nome> is back (away until <data>)` | 1 | la pagina *Inactive* | 3 giorni dopo il rientro |
| `officer` | il membro stesso | la **propria** assenza che finisce entro 3 giorni: `Your absence ends on <data>` | 1 | la scheda *Absence* di Settings | dopo il rientro |

- Le richieste di crafting di M3 sono solo un sussurro scritto dal giocatore ([SPEC-06 §2.3](SPEC-06-professions-recipes.md#23-richiesta-di-creazione-m36-pro-05)): nessuno le salva e l'artigiano non è avvisato dall'addon. Il fornitore `craft` tiene **solo un promemoria locale di chi chiede**: `GuildKey:Data().craftAsks`, al massimo 20 (le più vecchie escono), `{ guid, recipeId, at }`, mai inviato, mai nel backup. M13.2 lo sostituisce con gli ordini e migra i promemoria aperti ([M13](../roadmap/M13-economy.md)). Decisa dal proprietario come proposto ([SPEC-10 Q19](SPEC-10-risks-open-questions.md#2-domande-aperte-per-il-proprietario), 2026-11-25).
- Fornitori dei passi successivi: `groups` (M9.7, §6.9: i candidati in attesa al proprio annuncio, urgenza 3); poi le iscrizioni (M10), le prove dei nuovi membri (M12), i sondaggi (M14). Ognuno si registra con `Actions:Register` nel proprio modulo, senza toccare `Data/Actions.lua`.
- **Come è fatto (M9.2).** `Data/Actions.lua` non conosce nessun modulo. `bank` è registrato da `Data/BankInbox.lua`, `craft` da `Data/Recipes.lua`; `officer` è **un solo** fornitore registrato da `Data/OfficerOps.lua`, che unisce le righe della coda a quelle di `Absence:ActionRows` (le assenze servono anche al membro, quindi non ha `visible()`: filtra le righe), con l'etichetta *Officers and absences* / *Ufficiali e assenze*. Un ufficiale che ha una propria richiesta in banca ha le due righe della tabella (decidere e promemoria). La riga `and N more` apre la vista della prima riga rimasta fuori. Un promemoria `craft` si rinnova se si richiede la stessa ricetta allo stesso membro, e non si salva con l'interruttore spento. Il clic su una riga della banca porta la lista fino alla richiesta e la evidenzia.
- **Demo** ([SPEC-11 §3](SPEC-11-data-trust.md#3-modalità-demo-m74)): i fornitori leggono i dati della gilda inventata; la demo aggiunge due richieste di crafting e un candidato.

### 2.4 La vista

Vista `actions` (*Action Center* / *Centro azioni*, ordine 5, prima di Roster), con due pagine nel selettore (come Officers): **Inbox** (questa sezione) e **Notices** (§3.3). La pagina Inbox: in cima la scheda del riepilogo (§5.3), poi i chip dei fornitori (*All* più uno per fornitore presente), poi la tabella: segno dell'urgenza (colore del tema: `danger` per 3, `accent` per 2, `text-3` per 1), titolo, dettaglio, chi, età (`Provenance.AgeText`). Clic su una riga = `open()`; il pulsante *Done* compare solo sulle righe con `dismiss`. Testo vuoto: `Nothing waits for you.` / `Non c'è niente in attesa.`

## 3. Avvisi (M9.3)

### 3.1 Livelli

| Livello | Significato | Uscite predefinite |
|---|---|---|
| `alert` | qualcuno aspetta il giocatore **adesso** | riga in chat e toast |
| `normal` | è cambiato qualcosa che lo riguarda | riga in chat |
| `quiet` | buono a sapersi | solo cronologia e riepilogo, mai un'uscita |

Un modulo pubblica con `Notify:Post(module, kind, n)`, `n = { key, level, text, args, view, page, still }`:

- `text` = **chiave** del testo (non il testo), `args` = al massimo 4 stringhe o numeri: la cronologia si mostra nella lingua di oggi anche se è cambiata;
- `view`, `page` = dove porta il clic; `key` = identità dell'avviso (§3.5); `still()` facoltativo: `false` se la cosa non c'è più (una candidatura ritirata), così un avviso trattenuto non esce (§4).

### 3.2 Moduli, tipi e interruttori

| Modulo.tipo | Livello | A chi | Uscite predefinite | Interruttore del tipo |
|---|---|---|---|---|
| `bank.officer` | `normal` | ufficiali: arriva una richiesta non vista | chat | `account.settings.notifyOfficer` (M5) |
| `bank.decision` | `normal` | richiedente: la propria richiesta approvata, rifiutata o consegnata | chat | `account.settings.notifyDecision` (M5) |
| `groups.applicant` (M9.7) | `alert` | capo: una candidatura nuova | chat, toast | `notify.groups.off.applicant` |
| `groups.answer` (M9.7) | `alert` | candidato: accettato o rifiutato | chat, toast | `notify.groups.off.answer` |
| `groups.match` (M9.7) | `normal` | chiunque: un annuncio nuovo che va bene per lui (§6.9) | **spento** | `notify.groups.off.match` (predefinito `true`) |
| `groups.game` (M9.8) | `alert` | capo: c'è da togliere l'annuncio nel gioco (§7.2) | chat, toast | nessuno |
| `officer.back` | `quiet` | ufficiali: un'assenza finita | — | — |
| `likes.received` | `quiet` | chi riceve un like (solo il numero) | — | — |
| `digest` | `normal` | il riepilogo (§5) | chat | `notify.digest.chat` |

- Ogni modulo ha tre uscite, `chat`, `toast`, `sound`, nella tabella `account.settings.notify[modulo]` (predefiniti: `bank` chat sì, toast no, suono no; `groups` chat sì, toast sì, suono no; `digest` chat sì). Il suono è spento ovunque di predefinito.
- **NTF-01** Un tipo **spento** non produce nessuna uscita ma entra **comunque** nella cronologia, segnato `muted` (criterio di M9.3).
- **NTF-02** Le due opzioni di M5 funzionano come oggi: `notifyOfficer` e `notifyDecision` restano le chiavi, con lo stesso predefinito (acceso) e lo stesso testo; la riga in chat ha le stesse parole di M5. La carta *Notices* di Settings mostra, per modulo, le tre uscite e sotto gli interruttori dei tipi. `BankInbox` smette di stampare da sé e chiama `Notify:Post`; con l'interruttore `actions` spento, stampa come oggi.
- Il tipo `quiet` non ha uscite da scegliere.

### 3.3 Cronologia

- In `GuildKey:Data().notify = { list = { … }, n = 0, seen = { … } }` (dell'account, per gilda). Una voce: `{ n, module, kind, level, text, args, view, page, key, time, char, read, muted, count }`; `char` = GUID del personaggio a cui è rivolta (nil = a tutto l'account): la pagina mostra le voci del personaggio connesso e quelle di tutto l'account.
- **NTF-03** Al massimo **200 voci** e **30 giorni**: oltre, le più vecchie escono.
- Lette e non lette: una voce è letta quando il giocatore ci clicca (apre `view`/`page`) o con *Mark all read*. Il numero delle non lette è il distintivo della pagina *Notices*. Nessuna voce si marca letta da sola.
- La pagina *Notices*: le voci, la più recente in cima, con il modulo, il testo, l'età, il segno *muted*; i chip *All* / *Unread*; *Mark all read*; *Clear* (svuota la cronologia, con conferma).
- `bank.seen` di M5 (gli stati già annunciati) passa in `notify.seen.bank` con la migrazione, senza perdere nulla: nessuna richiesta già annunciata torna come nuova.

### 3.4 Uscite

- **Chat**: una riga nel riquadro di chat predefinito, preceduta da `Accord:` nel colore dell'addon. Gli avvisi che arrivano entro 3 s escono insieme: al massimo **3 righe** più `and N more — /accord inbox` (le costanti `NOTICE_WAIT` e `MAX_LINES` di `BankInbox` passano a `Notify`).
- **Toast**: una cornice dell'addon (`UI/Toast.lua`), in alto al centro sotto la zona degli errori del gioco, con il tema; uno alla volta, 6 s, il clic apre la vista, il clic destro lo chiude; in coda al massimo 3, oltre si riassumono in `N more notices`. **Mai** le cornici o i sistemi di avviso del gioco (`AlertFrame`, `RaidNotice_AddMessage`): niente taint.
- **Suono**: `Compat.Sound.Play(kind)` con un solo suono del gioco per livello (`PlaySound` con un id di `SOUNDKIT`, in `Compat` **[verificare]** quali id esistono su Forever), al massimo uno ogni 10 s.

### 3.5 Contro le inondazioni

- **NTF-04 Prima volta**: la prima volta che `Notify` gira in una gilda (nessun `notify.seen`), tutto ciò che c'è è preso come visto: nessun avviso. Lo stesso dopo *Clear guild data*.
- **NTF-05 Recupero dopo l'accesso**: dall'accesso fino a **120 s dopo il primo `HELLO` mandato** (al massimo 300 s dall'accesso) gli avvisi che vengono da record ricevuti non escono uno per uno: entrano nella cronologia **raggruppati** per modulo e tipo (`count`, testo `5 new bank requests`) e il riepilogo (§5) li conta. Così un'assenza lunga, quando la sincronizzazione porta tutto in una volta, dà una riga, non cento.
- **NTF-06 Raffica**: più di 20 avvisi dello stesso modulo e tipo in 60 s diventano una voce raggruppata.
- **NTF-07 Stessa chiave**: un avviso con la `key` di una voce non letta aggiorna quella voce (ora e testo), non ne crea una nuova e non esce di nuovo.
- **NTF-08 Per sessione**: al massimo 30 uscite (chat o toast); oltre, solo cronologia e una riga `More notices in /accord inbox`.

### 3.6 Come è fatto (M9.3)

- `Data/Notify.lua` non conosce nessun modulo: ognuno si registra con `Notify:Register(modulo, { label, order, kinds, open, check })`; ogni tipo ha `level`, il testo di gruppo `group` e l'interruttore (`option`, un'opzione di `SettingsModel`, o `off`, l'etichetta dell'interruttore `notify.<modulo>.off.<tipo>`). Registrati: `bank` (`Data/BankInbox.lua`), `officer` (`Data/Absence.lua`, tipo `back`), `likes` (`Data/Likes.lua`, tipo `received`); `officer` e `likes`, solo `quiet`, non hanno uscite nella carta. `check` (ogni 60 s e all'accesso) coglie ciò che nessun evento annuncia.
- La chiave di `bank.decision` contiene lo stato (`<id>:<stato>`): approvata e poi consegnata sono due avvisi, come in M5; il motivo di un rifiuto è un testo suo (`BANKNOTE_REJECTED_NOTE`), con le stesse parole.
- **NTF-05**: la finestra si apre solo a un accesso (`isInitialLogin`), non dopo un `/reload`. Nella finestra ogni tipo ha una voce (quelle `muted` a parte) che **esce una volta alla fine della finestra**: con un solo avviso con le sue parole, con più d'uno con il testo di gruppo; una voce letta nel frattempo non esce.
- `officer.back` e `likes.received` seguono NTF-04: la prima volta si ricorda soltanto. I like nuovi aggiornano la stessa voce non letta (il numero si somma).
- *Clear guild data* svuota la cronologia e tiene `notify.seen`; le chiavi nuove di `account.settings` di M9.4–M9.9 si aggiungono allo stesso passo di migrazione 4 (nessuna release ha ancora lo schema 4).
- `NOTICE_WAIT` e `MAX_LINES` sono di `Notify`; `BankInbox` le riprende per il percorso con l'interruttore spento. La riga e il suono passano da `Compat.ChatLine` e `Compat.Sound.Play`, che usa il nome di una costante di `SOUNDKIT` (`TELL_MESSAGE`; per `alert` prima `RAID_WARNING`) **[verificare]**.
- Le scelte delle uscite non entrano nel backup personale (SPEC-11 §4), che porta solo le impostazioni semplici.

## 4. Ore di quiete (M9.4)

- **Impostazione** `account.settings.quiet = { on, from, to, instances }`: ore intere locali; `from = 23, to = 8` vuol dire dalle 23:00 alle 7:59; `from ≠ to` (uguali si rifiutano: la regola di `Config` rimette il predefinito). Nella carta *Notices* di Settings: *Quiet hours* (spento di predefinito), *From*, *To*, *Also in dungeons, raids and battlegrounds* (acceso).
- **QUI-01 Trattenere**: un avviso esce (chat, toast, suono) solo se **nessuna** di queste vale; altrimenti è **trattenuto**:
  - le ore di quiete sono accese e l'ora locale è in `[from, to)`;
  - il giocatore è in combattimento (`Compat.InCombat()`, e tra `PLAYER_REGEN_DISABLED` e `PLAYER_REGEN_ENABLED`): sempre, anche senza ore di quiete;
  - `instances` è acceso e il giocatore è in un'istanza (`Compat.InInstance()` con tipo `party`, `raid`, `pvp`, `arena` o `scenario`).
- **QUI-02** Un avviso trattenuto entra **subito** nella cronologia (non letto); il Centro azioni non cambia (è un elenco, non un'uscita).
- **QUI-03 Rilascio**: quando nessuna condizione vale più (3 s dopo `PLAYER_REGEN_ENABLED`, 5 s dopo l'uscita dall'istanza, al controllo di ogni minuto per la fine delle ore di quiete), gli avvisi trattenuti escono **una volta sola, nell'ordine di arrivo**, come una sola raffica (§3.4: 3 righe e `and N more`), con un solo toast (l'ultimo `alert`) e al massimo un suono. Un avviso con `still()` falso o trattenuto da più di 12 ore non esce (resta nella cronologia).
- Anche il riepilogo (§5) aspetta.

### 4.1 Come è fatto (M9.4)

- Tutto in `Data/Notify.lua`: `Notify:Holding()` dice perché si trattiene (`combat`, `instance`, `hours` o niente, anche in `/accord debug`). Gli avvisi trattenuti restano nella coda delle uscite, nell'ordine di arrivo, segnati con l'ora in cui sono stati trattenuti (le 12 ore contano da lì). Un avviso nuovo che arriva dopo la fine di ogni condizione, prima del rilascio, esce insieme ai trattenuti, in coda a loro.
- `instances` vale **anche con le ore di quiete spente** (QUI-01); `on` governa solo le ore. L'ora locale è `Compat.LocalHour()` (`date("*t")`).
- Il rilascio parte dopo `PLAYER_REGEN_ENABLED` (3 s), dopo `PLAYER_ENTERING_WORLD` e `ZONE_CHANGED_NEW_AREA` (5 s), al controllo di ogni minuto e subito quando si cambia un'impostazione delle ore di quiete.
- Il toast del rilascio è l'ultimo `alert`; se tra i rilasciati non c'è un `alert`, l'ultimo che ha il toast. I toast già in coda dietro quello sullo schermo si fermano finché una condizione vale e riprendono al rilascio; quello già visibile resta fino alla sua scadenza.
- La coda è della sessione: dopo un `/reload`, un logout o un cambio di gilda gli avvisi trattenuti restano solo nella cronologia (non letti).
- Nella carta, *From* e *To* sono due elenchi delle 24 ore, e ognuno non offre l'ora dell'altro; un valore salvato con `from = to` rimette tutta la tabella `quiet` al predefinito.

## 5. Riepilogo all'accesso (M9.5)

### 5.1 Quando

- **DIG-01** Solo al **primo accesso** della sessione (`PLAYER_ENTERING_WORLD` con `isInitialLogin`), mai dopo un `/reload`, mai in demo; 10 s dopo la prima lettura completa del roster (al massimo 60 s dopo l'accesso); trattenuto come un avviso (§4).
- "Dall'ultima sessione" = da `GuildKey:Data().digest.at`, l'ora del server dell'ultima volta che l'account era in gioco in questa gilda: si aggiorna ogni 5 minuti e a `PLAYER_LOGOUT`.
- **Prima volta** (nessun `digest.at`): si prende la fotografia (§5.2) e non si mostra nulla.

### 5.2 Righe

Nell'ordine, ognuna **solo se diversa da zero**:

| Riga | Fonte | Apre |
|---|---|---|
| `2 new members: Anna, Bob` | il roster di oggi contro la fotografia `digest.roster` (`{ [GUID] = nome }`, al massimo 1000) | Roster |
| `1 member left: Carl` | idem | Roster |
| `3 things wait for you` | le righe di urgenza 2 e 3 del Centro azioni | Action Center |
| `You received 2 likes` | le voci del libro dei like con destinatario un personaggio dell'account e `time` > `digest.at`: **solo il numero, mai chi** (LIKE-04) | Reputation |
| `Bank: +120 g, 14 movements` | foto della banca più recenti di `digest.at` che il giocatore può vedere (SPEC-08): differenza del denaro e numero di voci nuove dei registri | Bank |
| `5 unread notices` | voci non lette della cronologia con `time` > `digest.at` | Notices |

- Al massimo 3 nomi per riga, poi `and N more`. Se mancano più di 90 giorni o più di 50 persone sono entrate o uscite, solo i numeri.
- La fotografia del roster si aggiorna dopo il riepilogo e a ogni lettura completa del roster (non dopo una lettura parziale).

### 5.3 Dove

- **DIG-02** Una sola riga in chat (se l'uscita `chat` del modulo `digest` è accesa): `Accord: since your last session: 2 new members, 3 things wait for you, 2 likes. /accord inbox`, solo i numeri.
- In cima alla pagina *Inbox* la scheda *Since your last session* con le righe di §5.2, ognuna cliccabile verso la sua vista, fino al prossimo accesso (o finché il giocatore la chiude). Nessun collegamento cliccabile nella chat (eviterebbe un hook sulla chat del gioco).
- **DIG-03** Niente è cambiato: nessuna riga in chat, nessuna scheda, nessun suono (criterio di M9.5).

### 5.4 Come è fatto (M9.5)

- Tutto in `Data/Digest.lua`; la scheda è in `UI/Actions.lua`, in cima alla pagina *Inbox*. `GuildKey:Data().digest = { at, roster, cut, pending, money, moves, card }`: dell'account per gilda, mai inviato, mai nel backup; *Clear guild data* lo toglie (l'accesso dopo è una prima volta).
- Finché il riepilogo di un accesso non è uscito, né `at` né la fotografia si rinnovano: un logout subito dopo l'accesso non perde nulla. Un `/reload` prima del riepilogo lo salta. Se la gilda non è nota entro la fine del recupero, per quell'accesso non c'è riepilogo.
- **Recupero**: ciò che è successo mentre il giocatore era via arriva con la sincronizzazione, dopo il primo `HELLO`. Fino a **150 s dall'accesso** le righe si rileggono quando arriva qualcosa (raccolti per 2 s) e la scheda si aggiorna; poi resta com'è. La riga in chat (DIG-02) esce **una volta**: al riepilogo, o alla fine del recupero se prima non c'era nulla. Ciò che arriva oltre i 150 s, o con un'ora precedente a `digest.at` (un like scritto prima dell'ultima sessione e ricevuto solo ora), non compare.
- **Cose che aspettano** (DIG-03): da sole non sono un cambiamento. La riga conta tutte quelle di urgenza 2 e 3, ma il riepilogo esce per esse solo se almeno una è **nuova o diversa** dall'ultima sessione (`digest.pending`, per fornitore e chiave, con il `mark` facoltativo della riga: lo stato di una richiesta in banca, il numero di una coda degli ufficiali). Se qualcos'altro è cambiato, la riga c'è comunque.
- **Membri**: confronto per GUID alla prima lettura completa del roster; i nomi senza reame, in ordine alfabetico. «Più di 50» vale per la somma di entrati e usciti, e allora tutte e due le righe hanno solo il numero. Oltre 1000 membri niente righe del roster.
- **Like**: `Likes:ReceivedSince(at)` restituisce **solo un numero** (gli pseudonimi nuovi sui personaggi dell'account che nessuna voce più vecchia ha); niente altro dei libri passa al riepilogo o alla scheda.
- **Banca**: il denaro è confrontato con `digest.money` quando la foto è più recente di `at`. I movimenti sono le voci dei registri visibili non presenti in `digest.moves` (le ultime 48 ore al momento del salvataggio, perché il gioco arrotonda le ore dei registri anche di un giorno), unite con `BankLog.Merge`.
- **Uscita**: la riga in chat non passa dalla cronologia degli avvisi né dalla finestra di NTF-05; aspetta con `Notify:WhenFree` (stesse condizioni di QUI-01, stesse 12 ore, dopo gli avvisi trattenuti) e usa l'ora in cui esce: se la scheda è stata chiusa nel frattempo non esce. Il modulo `digest` si registra in `Notify` con la sola uscita `chat` (`outputs = { "chat" }`), quindi la carta di Settings mostra solo quella.

## 6. Cercagruppi della gilda (M9.6–M9.7)

Come il pannello dei gruppi predefiniti del gioco, ma **solo per la gilda**: un capo pubblica un annuncio, i membri si candidano con un ruolo, il capo accetta e invita.

### 6.1 Principi

- **GRP-01 Solo la gilda**: gli annunci viaggiano solo su `GUILD` o in `WHISPER` a un membro nel roster; un annuncio si accetta solo da un mittente nel roster (`Store`, motivo `sender`). Nessuno fuori dalla gilda li vede.
- **GRP-02 Solo il capo scrive**: l'annuncio si accetta **solo di prima mano** (il mittente è il capo o un personaggio del suo account, NET-10); un ufficiale **non** può ritrasmetterlo (nuovo campo di definizione `firstHandOnly = true`: NET-11 non vale, motivo `relay`).
- **GRP-03 Breve vita, fuori dal riepilogo**: l'insieme è **volatile** (nuovo campo `volatile = true`): non entra nei riepiloghi `HELLO`, `BHELLO` e `OHELLO`, non si spinge e non risponde a `REQ`, non va nel backup né nelle esportazioni. Si scrive su `GUILD` come ogni modifica locale (`REC`, raccolta di 5 s) e chi arriva dopo lo chiede con `GASK` (§6.7). Così annunci che durano poche ore non cambiano i riepiloghi e non scatenano riparazioni ([ADR 0024](../adr/0024-guild-group-finder-short-lived-listings-private-game-listing.md)).
- **GRP-04 Si chiude da solo**: ogni client decide da sé, con gli stessi dati, se un annuncio è aperto (§6.3): pieno, scaduto e abbandonato si chiudono su ogni client anche senza un messaggio.

### 6.2 L'insieme `groups`

Un record per annuncio, `id = "<GUID del capo>:<n>"` (`n` intero crescente del personaggio, `char.groups.next`), `author` = il capo. Campi:

| Campo | Tipo | Regola |
|---|---|---|
| `kind` | stringa | `dungeon`, `raid`, `quest`, `elite`, `pvp`, `farm`, `prof`, `help`, `other` (testi: *Dungeon*, *Raid*, *Quest*, *Elite*, *PvP*, *Farming*, *Professions*, *Help*, *Other*) |
| `act` | numero o stringa | `dungeon`/`raid`: il `mapID` dell'istanza (intero 1–1 000 000, §6.4); gli altri tipi: testo di 1–40 caratteri (missione, zona, campo di battaglia, professione…); `help`: **solo il nome della zona** |
| `min`, `max` | interi | livelli 1–livello massimo del gioco (`GetMaxPlayerLevel`, **[verificare]**), `min ≤ max` |
| `size` | intero | `dungeon`/`raid`: quella della tabella (§6.4); gli altri 2–40 |
| `need` | tabella `{ t, h, d }` | tank, guaritori, danno ancora cercati: interi ≥ 0, somma ≤ `size − have` |
| `have` | intero | quanti sono già nel gruppo, capo compreso: 1–`size` |
| `note` | stringa | 0–80 caratteri |
| `meet` | stringa | 0–40 caratteri: il punto d'incontro **in parole**, mai una posizione |
| `until` | ora del server | fine dell'annuncio: da `time` + 30 minuti a `time` + 4 ore (predefinito 2 ore) |
| `status` | stringa | `open`, `full`, `closed` |
| `why` | stringa | per `closed`: `leader` (chiuso dal capo), `logout` (il capo era uscito), `replaced` (il capo ne ha aperto un altro) |

- **Testi**: niente `|` (sequenze di escape del gioco), niente caratteri di controllo, niente spazi agli estremi; altrimenti la regola del proprietario rifiuta il record (`owner`). La stessa funzione pulisce i campi del modulo prima di scrivere.
- **Regola del proprietario** (`Groups.ValidRecord`): l'id comincia con il GUID dell'`author`; ogni campo come sopra; `rev ≤ 100`.
- **Definizione in `Store.SETS`**: `groups = { feature = "groups", volatile = true, firstHandOnly = true, maxBytes = 384, owner = Groups.ValidRecord, expires = … }`, in coda a `Store.SET_ORDER`.
- **Conservazione** (`expires`): un record si toglie 10 minuti dopo `until`, o 10 minuti dopo `time` se `status ≠ open`; un record che arriva già oltre si rifiuta (`expired`, come oggi). La pulizia gira all'accesso e ogni 60 s mentre la vista è aperta.

### 6.3 Aperto o chiuso: la regola di ogni client

Un annuncio si mostra **aperto** solo se valgono tutte:

1. `status == "open"`;
2. `until` > ora del server;
3. il capo è **online** nell'ultima lettura del roster (offline = *abbandonato*);
4. `need.t + need.h + need.d > 0` e `have < size`;
5. è l'annuncio aperto **più recente** del suo capo (un capo ha un solo annuncio aperto: uno più vecchio si mostra chiuso, `replaced`).

Altrimenti si mostra chiuso con il motivo (*Full*, *Expired*, *Leader offline*, *Closed*) per 10 minuti, poi sparisce. Il client del capo scrive anche lo stato, così chi arriva dopo lo legge:

- `full` quando `need` arriva a zero o il gruppo del gioco arriva a `size` (`Compat.Group.Size()`);
- `closed`/`logout` al **primo accesso** successivo, per i propri annunci ancora aperti e non scaduti (non dopo un `/reload`: un `/reload` del capo non chiude il gruppo);
- `closed`/`replaced` sul vecchio quando ne apre uno nuovo; `closed`/`leader` dal pulsante *Close*.

### 6.4 La tabella delle attività

`Data/GroupActivities.lua`: `{ mapID, kind = "dungeon" | "raid", size, min, max, name }` (`name` in inglese, di riserva).

- **Contenuto**: le spedizioni e le incursioni del gioco base (livelli 1–60), più quelle che il client riporta in gioco: all'avvio, se `C_LFGList.GetAvailableCategories`, `GetAvailableActivities` e `GetActivityInfoTable` esistono (sono nel dump), ogni attività delle categorie spedizioni e incursioni aggiunge o corregge la riga del suo `mapID` (`maxNumPlayers` → `size`, `minLevel`, `maxLevelSuggestion`). Quali istanze ha davvero Forever si conferma nella prova di M9 **[verificare]**.
- **Nome mostrato**: `GetRealZoneText(mapID)` (nel dump) nella lingua del client; se non risponde, `name`; se l'istanza non è nella tabella, `Instance <mapID>`.
- **Sul filo** va solo il `mapID`: un client con una tabella diversa accetta comunque l'annuncio (il `mapID` è un intero nel suo intervallo) e lo mostra con il nome del gioco. Il modulo del capo offre solo le istanze della tabella; `size` di un `mapID` sconosciuto è quella scritta dal capo (2–40).

### 6.5 Candidature: il messaggio `GAPP`

Un tipo nuovo, solo in `WHISPER` (`Codec:RegisterType("GAPP", { g = "string", k = "string" })`, priorità `ALERT`): `g` = id dell'annuncio, `k` = che cosa.

| `k` | Da → a | Altri campi |
|---|---|---|
| `apply` | candidato → capo | `r` = ruolo (`t`, `h`, `d`), `c` = commento facoltativo (0–60 caratteri, stesse regole dei testi), `l` = livello |
| `cancel` | candidato → capo | — |
| `accept`, `decline` | capo → candidato | — |
| `full` | capo → candidato | l'annuncio si è riempito o chiuso mentre la candidatura aspettava |

Regole del **candidato** (il pulsante *Apply* le controlla prima di mandare):

- **GRP-05** Manda solo al **capo**: il nome del personaggio con il GUID `author` nel roster, che deve essere online; mai su `GUILD`. Nessun altro sa chi si è candidato.
- Non si candida a un annuncio del proprio account; il proprio livello è tra `min` e `max`; il ruolo scelto ha `need` > 0; una candidatura per annuncio (una nuova sostituisce la vecchia), al massimo 3 in attesa in tutto; dopo un `decline` aspetta 10 minuti per lo stesso annuncio.
- Accetta una risposta solo dal personaggio `author` dell'annuncio (GUID dal roster) e solo per un annuncio a cui si è candidato.

Regole del **capo** (`Groups:OnApply`):

- **GRP-06** Accetta un `GAPP` solo se: il mittente è nel roster e non è del proprio account; l'annuncio è suo e aperto (§6.3); `k` e `r` sono validi. Al massimo **10 `GAPP` al minuto per mittente** (gli altri si ignorano) e **40 candidature in attesa per annuncio** (oltre, risponde `full`).
- Le candidature in attesa stanno in `char.groups.apps[id] = { [nome] = { r, c, l, at } }` (salvate, così un `/reload` non le perde) e si cancellano quando l'annuncio si chiude; quelle del candidato in `char.groups.mine`. **Mai** in `Store`, mai sincronizzate.
- Quando il capo chiude l'annuncio (pulsante o `full`), manda `full` a ogni candidato in attesa. Un annuncio scaduto o abbandonato non manda nulla: ogni candidato lo vede chiuso da sé (§6.3) e toglie la propria candidatura.

### 6.6 Accettare e invitare

**GRP-07** Il capo clicca *Accept* su un candidato. Nello stesso gestore del clic:

1. controlli: il capo è solo o è capo del gruppo del gioco (`UnitIsGroupLeader("player")`, o `C_PartyInfo.CanInvite()`); il gruppo non è pieno (`Compat.Group.Size() < size`); se il gruppo ha 5 persone e `size` > 5, nessun invito e il testo `Convert your party to a raid first.` (Accord non chiama mai `ConvertToRaid`);
2. `Compat.Group.Invite(nome)`: `C_PartyInfo.InviteUnit` (nel dump; il vecchio `InviteUnit` globale **non** c'è nel dump di Forever, `Compat` tiene il ripiego), con i nomi con lo spazio di [SPEC-11 §6.6](SPEC-11-data-trust.md#66-nomi-con-lo-spazio);
3. `need[r]` scende di uno, `have` sale di uno, l'annuncio si riscrive; parte `GAPP accept`; se `need` arriva a zero, `status = "full"` e `GAPP full` agli altri.

*Decline* manda `GAPP decline` e toglie la candidatura. Accord **non** accetta candidature da solo, **non** invita senza il clic del capo e **non** risponde per il candidato all'invito del gioco. Dentro un'istanza i `GAPP` aspettano nella coda come ogni messaggio (NET-05); se `InviteUnit` funzioni da un addon su Forever e durante il lockdown della chat nelle istanze si verifica nel client (**[verificare]**, criterio "Real client" di M9.6).

### 6.7 Chi arriva dopo: il messaggio `GASK`

Gli annunci pubblicati mentre un client era offline non sono nei riepiloghi (GRP-03). Un client li chiede con `GASK` (tipo nuovo su `GUILD`, `Codec:RegisterType("GASK", {})`, priorità `NORMAL`):

- **quando**: all'apertura della vista Groups se in questa sessione non ha mandato un `GASK` negli ultimi 10 minuti; oppure 60–90 s dopo il primo `HELLO` di un primo accesso, solo se `groups.match` è acceso (§6.9);
- **campo `h`**: stringa di impronte da 4 byte (`Hash.Fast(id .. ":" .. rev)`) degli annunci aperti che ha già, al massimo 60 (240 B);
- **risposta**: ogni client con un **proprio** annuncio aperto la cui impronta non è in `h` lo manda al richiedente come `REC` (`s = "groups"`) in `WHISPER`, dopo 0,5–3 s casuali, chiave di coda `GROUPS|<richiedente>`. Solo il capo (o il suo account) risponde: è di prima mano.
- **limiti**: si manda al massimo un `GASK` ogni 10 minuti (`Transport.RATE.GASK = { 1, 600 }`); chi riceve ne gestisce uno ogni 5 minuti per mittente e risponde a ogni richiedente al massimo una volta al minuto.

All'accesso **non** parte nessun annuncio: il costo di un accesso (SPEC-02 §4) non cambia.

### 6.8 Limiti

| Limite | Valore |
|---|---|
| un annuncio (stima di `Config.EstimateSize`) | `maxBytes` 384 |
| testi | `act` 40, `note` 80, `meet` 40, commento della candidatura 60 caratteri |
| annunci aperti | uno per personaggio (§6.3, punto 5) |
| revisioni | `rev ≤ 100`; il client del capo riscrive `have`/`need` al massimo una volta ogni 10 s (le modifiche si uniscono) |
| durata | da 30 minuti a 4 ore; tolto 10 minuti dopo la fine |
| `GAPP` | ≤ 200 B codificato; 10 al minuto per mittente; 40 in attesa per annuncio; 3 in attesa per candidato |
| `GASK` | uno ogni 10 minuti mandato; uno ogni 5 minuti per mittente gestito; `h` al massimo 60 impronte |

- I limiti per mittente di [SPEC-11 §6.3](SPEC-11-data-trust.md#63-inondazioni) valgono così come sono: un record `groups` rifiutato conta tra i rifiutati (quarantena dopo 50 in 10 minuti); il testo decodificato conta nei 256 KB al minuto.
- **Simulatore** (`Tests/test_groups.lua`, sopra `Tests/sim`): 50 client, 5 ufficiali, **50 annunci aperti** (uno per client), ognuno riscritto 3 volte, 20 candidature al minuto in tutta la gilda, un `GASK` di ogni client alla prima apertura della vista, 45 minuti di accessi e uscite come in [SPEC-02 §4](SPEC-02-network-protocol.md#4-sincronizzazione). Devono valere **i limiti di SPEC-02 §4 senza cambiarli** (media ≤ 400 B/min, client più carico ≤ 2 KB/min, costo di un accesso ≤ 8 KB, allineati ≤ 100 e 200 B/min) e in più: costo di un `GASK` con 50 annunci aperti ≤ 16 KB per tutta la gilda; coda di `Transport` mai oltre 100. Se non stanno nei limiti, M9.6 cambia i valori di questa sezione e lo scrive qui; un limite di SPEC-02 si alza solo con una nota in SPEC-10.

### 6.9 La vista Groups (M9.7)

Vista `groups` (*Groups* / *Gruppi*, ordine 40), nello stile del pannello dei gruppi predefiniti, con [`ui-style.md`](ui-style.md):

- **Elenco**: tipo (icona), attività, livelli, ruoli cercati (icone con il numero), `have/size`, capo, età, tempo rimasto. Filtri: chip dei tipi, attività (`Widgets.Select`), *Fits my level*, chip dei ruoli che il giocatore può fare, ricerca nel testo. Ordine predefinito: il più recente. I filtri si salvano in `account.settings.groupFilter`. I chiusi restano grigi 10 minuti.
- **Modulo** *Post a group*: tipo, attività (per spedizioni e incursioni un `Widgets.Select` della tabella, le istanze adatte al livello del giocatore in cima; altrimenti testo; per *Help* la zona attuale, `GetRealZoneText()`, già scritta), livelli (predefiniti quelli dell'attività), dimensione, ruoli cercati, nota, punto d'incontro, durata (30 min, 1, 2, 4 ore; predefinito 2). *Post*, *Update*, *Close*. Pubblicarne un secondo chiede di chiudere il primo.
- **Candidati** (solo il capo): nome, classe, livello, ruolo, commento, età; *Accept*, *Decline*. Fornitore `groups` del Centro azioni: una riga di urgenza 3 per candidato in attesa (`Bob wants to join as healer`), che apre questo elenco.
- **Candidarsi**: *Apply* con il ruolo **preselezionato**: il primo ruolo cercato tra quelli salvati nel Group Finder del gioco (`C_LFGListRoles.GetSavedRoles()`, nel dump); altrimenti il ruolo nel gruppo (`UnitGroupRolesAssigned("player")`); altrimenti il primo che la classe può fare (tabella `Groups.CLASS_ROLES`). Con M10 la dichiarazione della stagione viene prima. Accanto all'annuncio lo stato: `Applied as healer, waiting`, `Accepted: watch for the invitation`, `Declined`.
- **Avviso `groups.match`** (spento di predefinito): un annuncio nuovo il cui tipo è nei filtri salvati, che va bene per il livello e cerca un ruolo che il giocatore può fare; al massimo uno ogni 5 minuti; trattenuto come ogni avviso (§4).
- La pagina del manuale *Groups* in inglese e italiano; la demo mostra 6 annunci e 2 candidati.

## 7. Il Group Finder del gioco, in privato (M9.8)

### 7.1 Che cosa dice il dump

Nel dump di Forever 1.60.1 (`../WoW-Addons/docs/api.json`, consultato, non copiato) c'è `C_LFGList`:

- `CreateListing(createData)`, con `LfgListingCreateData` = `activityIDs`, `questID`, `isAutoAccept`, `isCrossFactionListing`, **`isPrivateGroup`**, `newPlayerFriendly`, `playstyle`, `generalPlaystyle`, `requiredDungeonScore`, `requiredItemLevel`, `requiredPvpRating`; `UpdateListing(createData)`; `RemoveListing` (tra i globali del client, non nella documentazione);
- `GetActiveEntryInfo()` → `LfgEntryData` con **`privateGroup`**; `HasActiveEntryInfo`, `IsPremadeGroupFinderEnabled`, `GetPremadeGroupFinderStyle`, `GetAvailableCategories`, `GetAvailableActivities`, `GetActivityInfoTable` (`fullName`, `mapID`, `minLevel`, `maxNumPlayers`, `categoryID`…);
- eventi `LFG_LIST_ACTIVE_ENTRY_UPDATE`, `LFG_LIST_ENTRY_CREATION_FAILED`, `LFG_LIST_ENTRY_EXPIRED_TIMEOUT`, `LFG_LIST_ENTRY_EXPIRED_TOO_MANY_PLAYERS`; `ADDON_ACTION_BLOCKED` e `ADDON_ACTION_FORBIDDEN` (`isTainted`, `function`).

Che cosa **non** dice: i dati di creazione non hanno nome né commento (il titolo viene dall'attività, il commento dalla casella del gioco, l'interfaccia "LFGListing" in stile Classic: `LFGListingComment_*`); il dump **non segna** le funzioni protette. Accord tratta quindi `CreateListing`, `UpdateListing` e `RemoveListing` come **protette**: servono un clic del giocatore e niente combattimento.

### 7.2 Regole

- **LFG-01 Mai pubblico**: Accord crea un annuncio nel gioco solo con `isPrivateGroup = true`, non lo cambia mai con `UpdateListing` e non scrive testo (né nome né commento). Dopo `LFG_LIST_ACTIVE_ENTRY_UPDATE`, se `GetActiveEntryInfo().privateGroup` non è `true` (il server ha ignorato il campo), la capacità diventa `missing` per quella versione del client (`account.gameFinder = { build, state }`, salvato: non si offre più) e parte l'avviso `groups.game` `The game listed the group publicly. Remove it?` con il pulsante *Remove* (un clic: `RemoveListing`).
- **LFG-02 Solo dal clic del capo**: `CreateListing` e `RemoveListing` si chiamano **solo** nel gestore `OnClick` di un pulsante di Accord premuto dal capo (*Also list privately in the game's Group Finder*, *Close*, *Remove*), mai da un timer, un evento, un messaggio o un comando; mai in combattimento (pulsante spento); solo se il giocatore è solo o capo del gruppo.
- **LFG-03 Niente taint**: Accord non tocca le cornici del Group Finder del gioco (`LFGListingFrame`, `PVEFrame`…), non chiama le funzioni `LFGListing*` dell'interfaccia del gioco e non fa hook. Se `ADDON_ACTION_BLOCKED` o `ADDON_ACTION_FORBIDDEN` nomina Accord, la capacità diventa `restricted` per la sessione, il pulsante sparisce e `/accord debug` lo dice.
- **LFG-04 Capacità** `gameFinderPrivate` (nuova in `Compat.FEATURES`): `available` quando `C_LFGList.CreateListing`, `RemoveListing`, `GetActiveEntryInfo` e `GetActivityInfoTable` sono funzioni e `IsPremadeGroupFinderEnabled()` è vero; per un annuncio si offre solo se è `dungeon` o `raid` e c'è un'attività del gioco con lo stesso `mapID` (§6.4). Gli altri tipi non hanno il pulsante.
- **LFG-05 Si chiude con l'annuncio della gilda**: il client ricorda l'annuncio creato da Accord (`char.groups.game` = id dell'annuncio della gilda). *Close* del capo chiama `RemoveListing` nello stesso clic. Quando l'annuncio della gilda si chiude da solo (pieno, scaduto) e quello del gioco c'è ancora (`HasActiveEntryInfo`), parte l'avviso `groups.game` con *Remove* (un clic). Il gioco toglie da sé l'annuncio pieno (`LFG_LIST_ENTRY_EXPIRED_TOO_MANY_PLAYERS`) e scaduto (`…_TIMEOUT`); all'uscita del capo **[verificare]**.
- **LFG-06 Chi lo vede**: un gruppo privato si vede dagli **amici e dai membri della gilda** del capo **[verificare]**: anche amici fuori dalla gilda. Il tooltip della casella lo dice: `Your friends outside the guild can see it too.` / `Lo vedono anche i tuoi amici fuori dalla gilda.` È una scelta del capo, con il suo clic.
- **LFG-07 Senza la capacità** non si offre nulla e non compare nessun testo: il cercagruppi di M9.6–M9.7 resta l'unico. M9.8 scrive l'esito della prova qui e nella checklist di M9.
- I candidati che arrivano dal Group Finder del gioco si gestiscono nella finestra del gioco; Accord vede solo la dimensione del gruppo (`have`).

## 8. Censimento degli addon (M9.9)

### 8.1 Che cosa si condivide

- **CEN-01** Gli addon **caricati** di questo personaggio: per `i` da 1 a `C_AddOns.GetNumAddOns()`, `name` (la cartella), `title` e `security` da `C_AddOns.GetAddOnInfo(i)`, caricato se il secondo valore di `C_AddOns.IsAddOnLoaded(i)` (`loaded`) è vero, versione da `C_AddOns.GetAddOnMetadata(name, "Version")`. Tutte nel dump; solo letture.
- **Fuori**: gli addon di Blizzard (`security == "SECURE"` o cartella che comincia con `Blizzard_`); gli addon installati ma non caricati (spenti, a richiesta non ancora caricati, con errori). Accord stesso **c'è** (le versioni in uso servono).
- **Pulizia**: cartella ≤ 64 caratteri; versione ≤ 40 caratteri, altrimenti nessuna (la regola di `Compat.Addon.State`); titolo senza codici di colore (`|c…`, `|r`), icone (`|T…|t`) e altre sequenze `|`, al massimo 48 caratteri, e non si manda se è uguale alla cartella.
- **CEN-02 Una sola lettura**: `Compat.Addon.Loaded()` (nuova) dà l'elenco ordinato per cartella, con le stesse chiamate e le stesse regole di `Compat.Addon.State` di M10.2.

**Rapporto con M10.2.** `Data/Integrations.lua` riconosce oggi solo gli addon noti di raid e loot (`Integrations.KNOWN`) **sul client del giocatore**, con `Compat.Addon.State(cartella)` e, per FDCP, il livello dell'API; la sua intestazione già dice che chi tra **gli altri** membri li ha viene dal censimento e che non tiene un campo proprio. M9.9 quindi **riusa** quella lettura (la stessa via di `Compat.Addon`, la stessa chiave: il **nome della cartella**, lo stesso limite della versione) e **non sostituisce nulla**: `Integrations:Detect` resta la fonte per il proprio client e per il livello; il censimento aggiunge la vista sugli altri. M9.9 aggiunge `Integrations:Holders(id)`, che legge il censimento con la cartella di `KNOWN` e dà gli account che hanno quell'addon caricato con la versione; finché `Features.raid` è spento nessuno la chiama.

### 8.2 L'insieme `addons`

Un record per personaggio, `id` = il suo GUID, `author` = un personaggio dello stesso account (come `contacts`); un insieme **normale**: nei riepiloghi, ritrasmesso dagli ufficiali (NET-11), salvato.

| Campo | Contenuto |
|---|---|
| `l` | elenco di `{ cartella, versione, titolo }` (versione e titolo possono mancare), ordinato per cartella |
| `more` | quanti addon sono rimasti fuori per il limite |
| `del` | `true` quando la condivisione è spenta: nessun `l` |

- **Limiti**: al massimo **120 voci**; `maxBytes` 6144 (stima); oltre, si tengono le prime in ordine di cartella e `more` dice quante mancano. Sul filo il `REC` è compresso (SPEC-02 §2).
- **Regola del proprietario** (`Census.ValidRecord`): `id` è un personaggio dell'account dell'autore (`SameAccount`); ogni voce rispetta §8.1; nessun carattere di controllo o `|`; con `del` nessun `l`.
- **Quando parte**: al primo accesso, 60–120 s dopo il primo `HELLO`, **solo se l'elenco è diverso** dal proprio record; quando cambia durante la sessione (un `ADDON_LOADED` di un addon a richiesta: nuovo controllo dopo 60 s, al massimo una volta ogni 10 minuti); e con lo stesso contenuto se il proprio record ha più di 30 giorni, così la conservazione non toglie un membro attivo.
- **Conservazione**: 60 giorni da `time` (`expires`); chi è uscito dalla gilda non si conta (§8.5) e il suo record scade.

### 8.3 L'interruttore

- `account.settings.shareAddons` (booleano, predefinito **acceso**, risposta del proprietario a Q11), *Share my addon list* / *Condividi l'elenco dei miei addon*, nella pagina *What I share* e nella carta della privacy di Settings.
- **CEN-03 Spento**: al prossimo accesso di ogni personaggio dell'account che aveva pubblicato un elenco parte **un solo** record con `del = true` (così gli altri lo tolgono dai conteggi), poi più nulla; nessun record se non aveva mai pubblicato. Riacceso: si pubblica al controllo successivo.
- *What I share* ([SPEC-11 §5](SPEC-11-data-trust.md#5-pannello-cosa-condivido-m76)) aggiunge la riga con `ShareModel.Add("addons", …)`: *Loaded addons* · tutta la gilda · all'accesso e quando cambiano · quanti addon e i primi 5 · l'interruttore.

### 8.4 Chi vede che cosa (SPEC-10 Q11)

| Dato | Tutti i membri | Ufficiali e GM |
|---|---|---|
| quanti account usano un addon, la quota, le versioni | sì | sì |
| **chi** usa un addon | no | sì |
| il proprio elenco (il proprio account segnato in ogni riga) | sì | sì |

La scelta è quella **decisa dal proprietario** (2026-11-24, [SPEC-10 Q11](SPEC-10-risks-open-questions.md#2-domande-aperte-per-il-proprietario)) e sta in un punto solo, `Census.NAMES_VISIBLE_TO = "officers"`. È una regola **dell'interfaccia**: i record arrivano a tutta la gilda; tenerli davvero riservati chiederebbe il canale degli ufficiali (S5, non provato). Decisa dal proprietario come proposto ([SPEC-10 Q17](SPEC-10-risks-open-questions.md#2-domande-aperte-per-il-proprietario), 2026-11-25); il manuale e *What I share* lo dicono.

### 8.5 Conteggi

- **Unità = account** (alt raggruppati con l'elenco reciproco di `accounts`; un personaggio senza record `accounts` è un account da solo). Un account **usa** un addon se il record non cancellato di almeno uno dei suoi personaggi **nella gilda** lo elenca.
- **Denominatore**: gli account della gilda con almeno un record del censimento non cancellato. La vista lo dice sempre: `Out of 34 members who run Accord and share their list.` / `Su 34 membri che usano Accord e condividono l'elenco.` Chi non ha Accord non si conosce.
- **Versioni**: le versioni diverse, ognuna con il numero di account.
- `CENSUS_CHANGED` dopo un record nuovo, un cambio del roster o di gilda (calcolo raccolto per 1 s).

### 8.6 La vista

Vista `addons` (*Guild addons* / *Addon della gilda*, ordine 70): una tabella con nome (il titolo, o la cartella; la cartella nel tooltip), utenti, quota (%), versioni (la più usata e `+N`); ricerca; ordine per ogni colonna (predefinito: utenti, decrescente); la frase del denominatore sopra la tabella. Un ufficiale clicca una riga e vede chi: gli account (nome del main e personaggi) con la versione. La propria riga è segnata. Pagina del manuale in inglese e italiano.

## 9. Test per passo

| Passo | Test | Che cosa prova |
|---|---|---|
| M9.2 | `Tests/test_actions.lua` | tre fornitori in un elenco, ordine di §2.2, una riga sparisce quando la cosa è risolta nella sua vista, il limite di ACT-02, un fornitore che fallisce non ferma gli altri |
| M9.3 | `Tests/test_notify.lua` | le opzioni di M5 funzionano come prima; un tipo spento non esce ma entra nella cronologia; 200 voci e 30 giorni; NTF-04–NTF-08 |
| M9.4 | `Tests/test_quiet.lua` | trattenuti in combattimento, in istanza e nelle ore di quiete (anche oltre la mezzanotte), escono una volta sola e in ordine |
| M9.5 | `Tests/test_digest.lua` | vuoto e muto se nulla è cambiato; mai il nome di chi ha dato un like; niente dopo un `/reload`; la prima volta solo la fotografia |
| M9.6 | `Tests/test_groups.lua` | un annuncio da fuori gilda o con un autore falso si rifiuta (anche da un ufficiale); le candidature arrivano solo al capo; pieno, scaduto e abbandonato si chiudono su ogni client; `GASK`; il simulatore con 50 annunci aperti nei limiti di §6.8 |
| M9.8 | `Tests/test_game_finder.lua` (mock di `C_LFGList`) | senza capacità nulla; con la capacità la creazione solo dal clic, sempre privata, chiusa con l'annuncio della gilda; un annuncio diventato pubblico spegne la capacità |
| M9.9 | `Tests/test_addons_census.lua` | conteggi su molti autori; chi spegne sparisce dai conteggi; un elenco cambiato sostituisce il vecchio; un elenco troppo lungo si taglia; i vecchi scadono; niente addon di Blizzard; `Integrations:Holders` |

## 10. Cosa resta da verificare nel client

- Gli id di `SOUNDKIT` per i suoni degli avvisi (§3.4).
- `C_PartyInfo.InviteUnit` da un addon, con nomi con lo spazio e dentro un'istanza durante il lockdown della chat (§6.6).
- `GetMaxPlayerLevel`, `GetRealZoneText(mapID)` e quali spedizioni e incursioni ha Forever (§6.4); `C_LFGListRoles.GetSavedRoles` (§6.9).
- Se gli annunci privati esistono su Forever, chi li vede, se `CreateListing`/`RemoveListing` chiedono un evento dell'hardware e se il gioco toglie l'annuncio quando il capo esce (§7).
- `C_AddOns.GetAddOnInfo` per indice e il valore di `security` degli addon di Blizzard su Forever (§8.1).
