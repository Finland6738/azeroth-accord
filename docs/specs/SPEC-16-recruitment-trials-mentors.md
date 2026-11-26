# SPEC-16: Reclutamento, prove e mentori

Specifica della milestone M12 ([roadmap](../roadmap/M12-recruitment.md)): il **testo di reclutamento**, costruito dalle mancanze del roster della season (M10, [SPEC-14](SPEC-14-calendar-raids-season.md)) e da una breve descrizione della gilda presa dal manuale (M11, [SPEC-15](SPEC-15-guild-handbook-loot.md)), da copiare a mano; le **prove** dei nuovi membri, seguite dagli ufficiali con note riservate e un promemoria alla fine; l'**accoglienza**, una lista di cose da fare per chi è appena entrato, che si spunta da sola; i **mentori**, un elenco di volontari, con le coppie suggerite agli ufficiali dal gioco di gruppo e dal grafo sociale. Ogni sezione dice il passo che la realizza (M12.2–M12.5; M12.6 è la prova e il rilascio `v0.12.0`). Le scelte che spettano al proprietario sono in [SPEC-10](SPEC-10-risks-open-questions.md) (Q34–Q38), con una proposta che il codice applica finché il proprietario non risponde. La decisione di architettura è [ADR 0026](../adr/0026-recruitment-copied-by-hand-trials-among-officers-mentors-opt-in.md).

Nomi di codice, campi e testi dell'interfaccia in inglese (con la traduzione italiana in `itIT.lua`, [ADR 0015](../adr/0015-interface-and-documentation-languages.md)). Le ore dei record sono ore del server in secondi (`Compat.ServerTime()`); un **giorno** è il giorno UTC scritto `AAAAMMGG`, come in [SPEC-12](SPEC-12-officer-tools.md). Le lunghezze sono in **byte** UTF-8 (una lettera accentata italiana conta 2).

## 1. Principi

Valgono le regole di integrazione del proprietario ([SPEC-14 §1](SPEC-14-calendar-raids-season.md#1-principi)) e quelle degli strumenti per ufficiali ([ADR 0023](../adr/0023-officer-tools-observe-and-suggest-officer-data-stays-among-officers.md)). In più:

| # | Regola | Che cosa vuol dire qui |
|---|---|---|
| RC-01 | **L'addon non scrive in nessun canale** | il testo di reclutamento si mostra in una casella da copiare; nessuna chiamata a `SendChatMessage`, `C_ChatInfo.SendChatMessage`, `BNSendWhisper` o simili, in nessun modulo di M12; un messaggio automatico in un canale pubblico sarebbe anche contrario alle regole del gioco (§3.4) |
| RC-02 | **Osserva e suggerisce** | una prova non cambia il grado e non espelle; una coppia di mentore e nuovo membro non avvisa nessuno; gli ufficiali agiscono a mano nel gioco |
| RC-03 | **I dati degli ufficiali restano tra ufficiali** | le prove e le loro note sono un insieme solo per ufficiali, con tutte le regole OFF-01…OFF-10 di [SPEC-12 §1](SPEC-12-officer-tools.md#1-chi-vede-cosa-e-dove-vanno-i-dati-degli-ufficiali) |
| RC-04 | **Mentore solo chi lo sceglie** | nessun membro compare come mentore senza il proprio clic; si esce dall'elenco quando si vuole, con un clic; le coppie suggerite le vedono solo gli ufficiali |
| RC-05 | **Locale dove basta** | il testo di reclutamento, la lista dell'accoglienza e le coppie suggerite si calcolano sul client e non viaggiano |
| RC-06 | **Il traffico condiviso non sale** | M12 aggiunge due insiemi piccoli (§7); il limite di [SPEC-09 §7](SPEC-09-quality-release.md#7-budget-di-traffico-condiviso-m10) resta quello di oggi, con il picco del primo scambio accettato in SPEC-10 Q26 e R17 come tetto |

## 2. Moduli, interruttore, dati locali

### 2.1 L'interruttore `recruit`

Tutto M12 è dietro un interruttore nuovo, **`recruit`**, in [`Core/Features.lua`](../../AzerothAccord/Core/Features.lua), **spento** fino a M12.6. Spento: non si vede nulla di M12 (né il pulsante del testo di reclutamento, né la pagina *Trials*, né la carta dell'accoglienza, né la modalità *Mentors*), i comandi `/accord recruit` e `/accord welcome` rispondono come comandi sconosciuti, gli insiemi `trials` e `mentor` non si scrivono, non si accettano e non si mandano (`feature = "recruit"` nella definizione di `Net/Store.lua`), il fornitore `trials` del Centro azioni non c'è e nessun avviso parte.

`recruit` **non** accende altri interruttori (nessuna voce in `Features.IMPLIES`): ogni parte che usa M10 o M11 chiede il proprio interruttore e, se è spento, la parte manca e lo dice (le mancanze vogliono `season`, la descrizione `raid`, la riga del Centro azioni `actions`). Oggi sono tutti accesi. Come gli altri interruttori, i moduli chiedono `Features.On("recruit")` quando agiscono, mai una volta sola al caricamento. I test lo accendono e lo spengono (`Tests/test_features.lua` e i test di ogni passo, §9).

### 2.2 File nuovi

| File | Contenuto | Passo |
|---|---|---|
| `Data/Recruit.lua` | il testo di reclutamento: parti, formati, limiti (§3) | M12.2 |
| `UI/Recruit.lua` | la finestra del testo con la casella da copiare | M12.2 |
| `Data/Trials.lua` | l'insieme `trials`, il fornitore `trials` del Centro azioni, l'avviso della fine (§4) | M12.3 |
| `UI/Trials.lua` | la pagina *Trials* della scheda *Officers* e la sezione *Trial* della scheda del membro | M12.3 |
| `Data/Onboarding.lua` | chi è nuovo, le voci della lista e il loro stato (§5) | M12.4 |
| `UI/Onboarding.lua` | la carta *Welcome* e `/accord welcome` | M12.4 |
| `Data/Mentors.lua` | l'insieme `mentor`, le coppie suggerite (§6) | M12.5 |
| `UI/Mentors.lua` | la modalità *Mentors* della vista *Reputation* e i suggerimenti nella pagina *Trials* | M12.5 |

Nessuna vista nuova in `Config.VIEWS`: il testo di reclutamento si apre dalla vista *Season* (e da `/accord recruit`), le prove sono una pagina della scheda *Officers* (`View.AddPage("trials", …)`, ordine 40, dopo *Timeline*), i mentori una modalità della vista *Reputation* (`View.AddMode("mentors", …)`), l'accoglienza una carta del Centro azioni.

### 2.3 Eventi del Bus

`TRIALS_CHANGED(guid)` (una prova o una nota arrivata o scritta; `guid` nil = più personaggi), `ONBOARDING_CHANGED()` (una voce della lista è cambiata, o la lista è comparsa o chiusa), `MENTORS_CHANGED()` (un'offerta di mentore arrivata, scritta o ritirata). Si aggiungono all'intestazione di `Core/Bus.lua`. Il testo di reclutamento non ha un evento suo: si ricostruisce dopo `SEASON_CHANGED`, `SOURCES_CHANGED`, `FDCP_CHANGED` e `HANDBOOK_CHANGED` (§3.5).

### 2.4 Dati locali

Nessuna migrazione di schema: le chiavi nuove si aggiungono dove mancano, al primo uso.

| Chiave | Contenuto | Sezione |
|---|---|---|
| `GuildKey:Data().recruit` | `{ contact, extra, format }`: la riga del contatto e la riga in più scritte da questo ufficiale, l'ultimo formato scelto | §3.3 |
| `GuildKey:Data().onboarding` | `{ [GUID] = { joined, how, known, done = { [voce] = ora }, dismissed, notified, completed } }` o `{ none = true }`: la lista dell'accoglienza di ogni personaggio dell'account in questa gilda | §5 |

Niente di questo si manda, ed entrambe le chiavi restano fuori dai backup personali (M7.5). Le prove (`trials`) e le offerte dei mentori (`mentor`) sono insiemi sincronizzati (§4.1, §6.1).

## 3. Il testo di reclutamento (M12.2)

### 3.1 Chi lo vede

Gli **ufficiali e il Guild Master** (`Recruit.VISIBLE_TO = "officers"`, un solo punto, SPEC-10 Q34): il pulsante *Recruitment text* compare nella vista *Season* accanto alle mancanze (SPEC-14 §4.5) e `/accord recruit` apre la stessa finestra. Il testo usa solo dati che ogni membro vede già (le mancanze sono numeri del roster, il manuale è della gilda): la regola serve a non avere un annuncio diverso da ogni membro in un canale pubblico, non a nascondere dati. Con `"members"` lo vedrebbero tutti.

### 3.2 Le parti

Il testo si costruisce ogni volta da quattro parti, nell'ordine, nella lingua dell'interfaccia di chi lo apre:

1. **Testa**: il nome della gilda, la fazione e il reame (`<Gilda> (<Alleanza|Orda>, <reame>)`), dal gioco.
2. **Descrizione**: dal manuale (`raid` acceso), la pagina `P:info` (*Guild info*, SPEC-15 §7.1), se esiste, è viva e non è più un modello: il **primo paragrafo sotto la prima intestazione** (nei modelli è *About us*), o il primo paragrafo se la pagina non ha intestazioni. Sotto la prima intestazione si guarda solo fino alla successiva; vale il primo paragrafo (o elenco) che, ridotto a testo, non è vuoto, e un elenco subito sotto il paragrafo, senza righe vuote in mezzo, ne fa parte. Passa dal lettore del testo (`HandbookText`, SPEC-15 §4): i collegamenti `[[slug|testo]]` diventano il testo, `[[slug]]` il titolo della pagina, `[[season]]` e `[[loot]]` spariscono, gli elenchi diventano frasi separate da `; `. Si taglia sull'ultima parola intera entro il limite del formato (§3.3) e finisce con `…`. Senza pagina, con la pagina ancora un modello o con un paragrafo vuoto la parte manca e la finestra lo dice: "Write the first paragraph of the handbook's Guild info page to add a description."
3. **Mancanze**: dalla fonte scelta per la season (`season` acceso; Accord o FDCP, SPEC-14 §3.1), con le stesse righe della vista (`Composition.Count`, `Composition.Gaps`): per ogni ruolo con `obiettivo − MS1 > 0` il numero e il ruolo, nell'ordine tank, healer, melee, ranged ("Looking for: 2 tanks, 1 healer, 3 ranged"). Si usano le mancanze di **MS1**: la copertura di MS2 è un ripiego interno del raid, non un posto libero (SPEC-10 Q34). Con FDCP la season conta come aperta finché FDCP non la dice chiusa (`CLOSED`); senza un roster leggibile da FDCP su questo computer la parte manca e la finestra lo dice. Senza season aperta, senza composizione obiettivo (`guildcfg` `target`) o senza mancanze la parte manca e la finestra dice perché ("No open season", "Set a target composition first", "No gaps against the target").
4. **Contatto e riga in più**: di predefinito "Whisper <nome del personaggio>" (il personaggio che apre la finestra); l'ufficiale lo può sostituire con un suo testo (`recruit.contact`, 0–48 byte, per esempio un nome Discord) e aggiungere una riga sua (`recruit.extra`, 0–100 byte, per esempio gli orari dei raid). Le due righe restano **solo su questo computer**: non sono dati della gilda e non viaggiano.

Le parti non contengono mai `|`, a capo dentro una parte o caratteri di controllo: le righe scritte dall'ufficiale passano dalla pulizia di SPEC-15 §4.4 al salvataggio, i nomi del gioco non ne hanno.

### 3.3 I due formati

| Formato | Forma | Limite | Taglio |
|---|---|---|---|
| `chat` | una sola riga, parti separate da ` – ` | **255 byte** (il limite di un messaggio di chat del gioco) | prima si accorcia la descrizione (fino a 0), poi la riga in più; testa, mancanze e contatto non si tagliano |
| `discord` | più righe: la testa in grassetto (`**…**`), la descrizione (fino a 600 byte), "Looking for:" con un ruolo per riga, la riga in più, il contatto | **1900 caratteri** (sotto i 2000 di un messaggio di Discord, come [SPEC-12 §6.4](SPEC-12-officer-tools.md#64-testo-per-discord)) | come `chat` |

`Recruit.Build(format)` restituisce il testo e l'elenco delle parti mancanti con il motivo (per la finestra e per i test). Il formato scelto per ultimo si ricorda (`recruit.format`).

### 3.4 La finestra e il "mai inviato"

Una finestra piccola (`UI/Recruit.lua`) con: la scelta del formato (*Chat line* / *Discord*), le due caselle del contatto e della riga in più, la casella del testo e il conteggio ("212 / 255 bytes"). La casella del testo è di **sola lettura** e si seleziona tutta al clic, come la casella di copia (`UI/CopyBox.lua`): il giocatore copia con Ctrl+C e incolla dove vuole. Sopra: "Copy this text and post it yourself. Accord never posts it." Nessun pulsante manda il testo.

- **REC-01** Nessun modulo di M12 chiama una funzione che manda un messaggio di chat o di Battle.net; il test di M12.2 sostituisce quelle funzioni nel client finto con versioni che falliscono il test se chiamate, e apre la finestra con ogni combinazione di parti.
- **REC-02** Il testo non si salva (si ricostruisce) e non è un record: nessun traffico.
- **REC-03** Le parti vengono solo dai dati della gilda che il client tiene e dalle due righe locali dell'ufficiale; nessun indirizzo web si aggiunge da sé.

Il gioco vieta di mandare in automatico messaggi nei canali pubblici e i canali di commercio e di ricerca hanno regole proprie: per questo il testo si copia e basta, e la frase sopra la casella lo dice.

### 3.5 Quando cambia

La finestra aperta si ricostruisce dopo `SEASON_CHANGED` (una dichiarazione o una season), `SOURCES_CHANGED` (la fonte o la composizione obiettivo, che è un record di `guildcfg`), `FDCP_CHANGED` (con FDCP come fonte) e `HANDBOOK_CHANGED` (la pagina `P:info`), raccolti per 0,5 s, e quando l'ufficiale cambia formato o una delle sue righe; la finestra si chiude se il personaggio non può più vederla o cambia gilda. È il criterio di M12.2: il testo cambia quando cambiano le mancanze. Se il giocatore ha appena selezionato il testo, la selezione si perde: il conteggio lampeggia per dire che il testo è nuovo.

## 4. Le prove (M12.3)

Una **prova** dice che un personaggio è in prova dal giorno `start` per `days` giorni: gli ufficiali la segnano, scrivono le loro impressioni, e alla fine il Centro azioni ricorda di decidere. La decisione si prende a mano nel gioco (un grado nuovo, un saluto): Accord la registra soltanto.

### 4.1 L'insieme `trials`

Un insieme **solo per ufficiali** come quelli di M8 ([SPEC-12 §1.2](SPEC-12-officer-tools.md#12-insiemi-solo-per-ufficiali)): `restricted` per ogni record, `officerTool = true`, in coda a `Store.SET_ORDER`. Due tipi di record:

| Record | Id | Campi | Chi scrive | `maxBytes` |
|---|---|---|---|---|
| Prova | `T:<GUID>:<start>` (`GUID` = il personaggio in prova, `start` = il giorno d'inizio) | `char` (GUID), `start` (giorno), `days` (1–`Trials.MAX_DAYS`), `ends` (giorno, `start` + `days`; cresce con una proroga), `state` = `open` \| `passed` \| `failed` \| `cancelled`, `closed` (giorno, con uno stato diverso da `open`) | un ufficiale (`authorAny`) | 256 |
| Nota | `N:<GUID>:<start>:<GUID ufficiale>` | `char`, `text` | l'ufficiale del suo id, solo lui | 1280 |

- **Lunghezza**: predefinita `Trials.DEFAULT_DAYS` = 14 giorni, da 1 a `Trials.MAX_DAYS` = 60; una **proroga** sposta `ends` più avanti (al massimo `start` + 120 giorni) e si può fare finché la prova è aperta. `start` non più di 30 giorni nel passato né più di 14 nel futuro rispetto al giorno della scrittura (SPEC-10 Q35).
- **Una nota per ufficiale e per prova**, con le regole di [SPEC-12 §5](SPEC-12-officer-tools.md#5-note-estese-m85) (ONT-02): al massimo 500 caratteri, 1000 byte e 20 righe, niente caratteri di controllo tranne l'a capo, il `|` raddoppiato nella visualizzazione; *Delete* scrive `text = ""` e il record vuoto scade dopo 60 giorni. Ogni ufficiale scrive solo la propria nota; quelle degli altri si leggono.
- **Una prova chiusa non si riapre**: per una seconda prova dello stesso personaggio se ne scrive una nuova, con un altro `start`. Le prove chiuse restano come storia nella scheda del membro.
- **Conservazione**: come la cronologia e le note estese, **nessun limite di età** (risposta del proprietario a SPEC-10 Q14, confermata per le prove con Q35 il 2026-11-26); restano i limiti di dimensione. Sparisce solo con OFF-10 (un ufficiale retrocesso).

### 4.2 Regole di fiducia (TRI-01…TRI-05)

- **TRI-01 Solo ufficiali.** Valgono OFF-01…OFF-03: un client che non è di un ufficiale rifiuta ogni record di `trials` (`restricted`); un ufficiale lo accetta solo se il mittente è ufficiale nel proprio roster; l'autore deve essere stato ufficiale quando l'ha scritto (`authorAny`). Nessuna eccezione per il membro in prova: non scrive e non riceve nulla della propria prova.
- **TRI-02 Solo il canale degli ufficiali.** Valgono OFF-04…OFF-09: i record viaggiano solo su `OFFICER` o in whisper a un ufficiale, con il doppio controllo `officerOnly` di `Sync` e `Transport`; finché il canale non è provato (S5) restano su questo computer, con la riga *Only on this computer until the officer channel works.* Nel riepilogo `m` di `OHELLO` l'insieme è un gruppo solo, `trials` (le voci passano da 47 a 48, circa 530 B).
- **TRI-03 Forma.** Id, campi e limiti di §4.1 (giorni validi, `ends ≥ start + 1`, `ends ≤ start + 120`, `state` tra i quattro, `closed` solo con uno stato chiuso); una nota con un autore diverso dal GUID del suo id si rifiuta. Altrimenti `owner`.
- **TRI-04 Transizioni.** Una revisione nuova di una prova può: prorogarla (`ends` più grande, stato `open`) o chiuderla (`open` → uno stato chiuso). Non può riaprirla, accorciarla, cambiare `char` o `start`: si rifiuta con il motivo `locked`, come una season chiusa (SEA-03).
- **TRI-05 Un ufficiale retrocesso** perde le prove e le note con gli altri dati degli ufficiali: M12.3 aggiunge `trials` all'elenco di OFF-10.

Il motivo di rifiuto (`restricted`, `authority`, `owner`, `locked`) arriva al contatore di `/accord debug` attraverso `Net/Store.lua`. Un client `v0.11` non conosce l'insieme e lo ignora (SPEC-02 §6), senza contarlo come rifiutato.

### 4.3 Chi vede

Solo **ufficiali e Guild Master** (`Officer.VISIBLE_TO.trials = "officers"`, la tabella di SPEC-12 §1.1, SPEC-10 Q35). Il membro in prova non vede nulla della prova in Accord: il gioco può già dirlo con il nome del grado, se la gilda ha un grado per le prove. Due ufficiali che segnano insieme la stessa persona scrivono due prove aperte con `start` diversi o la stessa con `start` uguale (vince la più recente, `Store.Compare`); la vista mostra una riga per personaggio, la prova aperta con `ends` più lontano, e dice quante altre ne ha aperte ("2 open trials").

### 4.4 Il promemoria alla fine

- **Il fornitore `trials`** del Centro azioni ([SPEC-13 §2.1](SPEC-13-action-center-notices.md#21-il-fornitore)), registrato da `Data/Trials.lua` con `feature = "recruit"` e `visible()` = `Officer.CanSee("trials")`: per ogni prova **aperta** con `ends` uguale o precedente al giorno di oggi una riga "Trial of <nome> ended on <data>: decide" (`urgency` 2, `time` = l'inizio del giorno `ends`, `who` = il nome), che apre la pagina *Trials* su quella prova e sparisce quando un ufficiale la chiude (o la proroga). Se il personaggio non è più nel roster la riga dice "<nome> left the guild during the trial" (`urgency` 1) e resta finché un ufficiale non la chiude (*Cancel*). Nessuna riga prima del giorno della fine.
- **L'avviso** `trials.ended` (livello `normal`, chat, interruttore del tipo `notify.trials.off.ended`), **una volta** per prova e per giorno della fine: la chiave dell'avviso è `<id della prova>:<ends>`, quindi lo stesso promemoria non torna a ogni accesso né con un `/reload`, e una proroga ne dà uno nuovo alla nuova fine. Parte il giorno della fine al primo aggiornamento del fornitore (all'accesso, o allo scoccare del giorno mentre si gioca); un ufficiale che entra tre giorni dopo vede la riga del Centro azioni e l'avviso una volta. È il criterio di M12.3: "il promemoria compare una volta, il giorno della fine".
- **Il riepilogo all'accesso** (M9.5) conta le prove finite da decidere nella riga del fornitore, come gli altri.

### 4.5 L'interfaccia

- **Pagina *Trials*** della scheda *Officers*: le prove aperte (nome, grado, inizio, fine, giorni che mancano, numero di note) e sotto, in un selettore, quelle chiuse degli ultimi 90 giorni (più vecchie dalla scheda del membro). Pulsanti: *Start trial* (un menu dei membri del roster, con la lunghezza e l'inizio, oggi di predefinito), *Extend* (giorni in più), *Passed*, *Not passed*, *Cancel*, ognuno con un secondo clic **Confirm**. Con i nuovi membri (§6.4) la stessa pagina mostra i mentori suggeriti.
- **Sezione *Trial*** della scheda del membro, solo per gli ufficiali: la prova aperta o l'ultima chiusa, le note degli ufficiali (la propria modificabile, nella finestra a più righe delle note estese, `UI/OfficerNotes.lua`, le altre in sola lettura con autore ed età, M7.2).
- **Passed** propone, con un riquadro da spuntare (spento di predefinito), di aggiungere alla propria coda delle azioni manuali ([SPEC-12 §4.2](SPEC-12-officer-tools.md#42-la-coda)) una promozione da fare nel gioco; Accord non promuove (RC-02).

### 4.6 Come è fatto (M12.3)

- `Data/Trials.lua` (`ns.Trials`) e `UI/Trials.lua` (`ns.TrialsView`). L'insieme ha `maxBytes` 1280 (la nota); una prova oltre 256 byte la rifiuta `Trials.ValidRecord`. La finestra dell'inizio (30 giorni indietro, 14 avanti) si controlla quando un ufficiale scrive (`Trials:Start`), non quando un record arriva: una prova vecchia resta valida.
- TRI-04 guarda solo una revisione **più nuova** di quella tenuta (`Store.Compare`); una più vecchia passa e il deposito la scarta come `older`, senza contarla tra i rifiuti. Anche `days` non cambia: una proroga sposta solo `ends`.
- *Passed* con l'interruttore acceso aggiunge alla coda di M8.4 una voce `promote` verso il grado subito sopra quello del membro tra quelli che l'ufficiale può dare (`OfficerOps:RankChoices`); senza un grado possibile, o con il membro fuori dal roster, la prova si chiude lo stesso e la finestra dice perché.
- Il nome di un personaggio uscito dalla gilda viene dal roster, poi dall'account, poi dall'ultimo evento della cronologia (§2 di SPEC-12); la riga "<nome> left the guild during the trial" compare solo dopo una lettura del roster non vuota.
- L'avviso usa il libro di `Notify:Seen("trials")`: una chiave `<id>:<ends>` per prova finita; una chiave che non è più da ricordare (prova chiusa o prorogata) si toglie dal libro, e non torna perché `ends` non diminuisce mai. Il fornitore del Centro azioni ha ordine 32 e la riga ha `mark` = la revisione della prova.
- La pagina *Trials* è registrata con `View.AddPage("trials", { order = 40, visible = … })`: una pagina con `visible()` falso non è nel selettore della scheda *Officers* (l'interruttore spento). Il menu dei membri di *Start trial* è un `Widgets.Select` con il roster in ordine di nome. La nota di una prova si scrive nella finestra delle note estese, a cui `OfficerNotesView:Open(guid, name, backend)` passa da dove leggere e scrivere.
- La demo (§8) aggiunge le tre prove e le due note a `D.recruit.trials`, messe al loro posto solo con `recruit` acceso.

## 5. L'accoglienza (M12.4)

### 5.1 Chi è nuovo

La lista compare **solo sul client del nuovo membro** e solo se il client sa che il personaggio è entrato **dopo** che l'addon, nella gilda, vedeva già il roster: chi era in gilda quando la gilda ha installato Accord non la riceve, come la prima lettura della cronologia non "fa entrare" tutta la gilda (TL-02). Un personaggio è **nuovo** se vale ONB-01 e nessuna delle esclusioni ONB-02, ONB-03:

- **ONB-01 L'ingresso è noto.** Uno dei due segni:
  1. **visto da questo client** (`how = "seen"`): il client legge la gilda del personaggio (`AzerothAccordDB.chars[reame][GUID].guild`, aggiornata a ogni lettura da `Data/Accounts.lua`) e il valore tenuto era un'altra gilda o nessuna (`""`); l'ora dell'ingresso è l'ora della lettura. Vale per chi aveva Accord prima di entrare. Non vale se l'account aveva già i dati di quella gilda (creati più di `Onboarding.KNOWN_MARGIN` = 60 s prima): la conosceva, quindi non è un primo ingresso, e una lettura "nessuna gilda" fatta mentre il gioco non era pronto non fa passare per nuovo un vecchio membro.
  2. **dal registro della gilda** (`how = "log"`, **[verificare]**): il registro degli eventi della gilda del gioco (`QueryGuildEventLog`, poi `GetNumGuildEvents` e `GetGuildEventInfo` globali, che il dump di Forever `1.60.1` non elenca: c'è solo l'evento `GUILD_EVENT_LOG_UPDATE`; le funzioni con lo stesso nome del dump sono quelle di `C_Calendar`) ha un ingresso (`join`) del proprio personaggio negli ultimi `Onboarding.NEW_DAYS` = 14 giorni; l'ora dell'ingresso è adesso meno l'età dell'evento. Vale per chi installa Accord dopo essere entrato. Si legge una volta, 60 s dopo il primo accesso nella gilda senza una voce in `onboarding`; senza le funzioni il segno manca e resta solo il primo.
- **ONB-02 L'addon c'era prima.** Il client tiene almeno un record di questa gilda scritto da un **altro account** con `time` precedente all'ingresso (la prova che un client di Accord della gilda vedeva il roster prima). Senza, il personaggio non è nuovo: è la gilda che comincia a usare Accord.
- **ONB-03 Non è un alt.** Un altro personaggio dello stesso account (`AzerothAccordDB.chars`) era già in questa gilda prima dell'ingresso (la sua gilda letta è questa, da prima: `guildSince`, l'ora da cui il client legge quella gilda per quel personaggio, aggiunta in M12.4 perché `guildAt` si aggiorna a ogni lettura; senza, `guildAt`): chi porta un alt nella gilda non è un membro nuovo.

Il segno si scrive una volta in `onboarding[GUID] = { joined, how }`; un personaggio senza i segni, o un alt (ONB-03), ha `onboarding[GUID] = { none = true }` e non si controlla più. La chiave è per gilda: ogni gilda ha la sua voce, e chi esce e rientra nella stessa tiene quella di prima.

ONB-02 al momento dell'ingresso non si può ancora sapere: i record della gilda arrivano con la sincronizzazione, minuti dopo. La voce nasce quindi da confermare e il personaggio è **nuovo** dal primo record che la soddisfa (`known`, una volta per tutte): prima di allora non si vede nulla, e senza quel record la voce resta così fino alla scadenza.

### 5.2 Le voci

Quattro voci fisse, nell'ordine; ognuna **si spunta da sola** quando il dato c'è (ONB-04) e si rilegge dopo gli eventi del modulo che la riguarda. Una voce che non si può fare in questa gilda **non si mostra**:

| Voce | Si spunta quando | Non si mostra se | Il clic apre |
|---|---|---|---|
| `read` *Read the guild info and rules* | l'account ha letto (`handbook.read`, SPEC-15 §5.4) la pagina `P:info` e la pagina `P:rules`, ciascuna se esiste ed è visibile | `raid` spento, o nessuna delle due pagine esiste o è visibile | il manuale sulla prima non letta |
| `main` *Choose your main* | l'account ha un main **scelto** (`Accounts:Main()` = `"chosen"`, [SPEC-05](SPEC-05-roster-alts-contacts.md)), oppure ha un solo personaggio | — | la carta *Main character* di *Settings* (la scheda del proprio membro non offre di scegliere il personaggio che è già il main di predefinito) |
| `discord` *Add your Discord name* | il proprio record `contacts` ha un nome Discord, condiviso o letto dal gioco | — | la carta del nome Discord in *Settings* |
| `season` *Declare for the season* | con la fonte Accord, l'account ha una dichiarazione nella season aperta (anche *Not sure yet*); con FDCP, `GetMember` di FDCP trova un personaggio dell'account nel pool (**[verificare]** sul client di un membro) | `season` spento, o nessuna season aperta (compare quando un ufficiale la apre), o con FDCP non caricato | la vista *Season*, o FDCP |

Una voce spuntata resta spuntata (`done[voce]` = ora) anche se il dato poi cambia: la lista accoglie, non sorveglia. Quando tutte le voci mostrate sono spuntate la carta dice "All done. Welcome to <gilda>!" per il resto della sessione (`completed`), poi non compare più.

### 5.3 Dove e per quanto

- **La carta *Welcome*** in cima alla pagina *Inbox* del Centro azioni (sopra la carta del riepilogo, SPEC-13 §2.4), con le voci, il numero ("2 of 4 done") e *Dismiss*; e una riga del fornitore `welcome` (urgenza 1, "Welcome checklist: 2 of 4 done") che la apre. Senza l'interruttore `actions` la carta non c'è, e la lista si apre solo con `/accord welcome`.
- **Una riga in chat**, una volta (`notified`), quando il personaggio risulta nuovo: "Welcome to <gilda>! Accord has a short checklist for new members: /accord welcome".
- **Dismiss** la chiude per sempre per quel personaggio (`dismissed`, criterio di M12.4: si può chiudere); la lista sparisce comunque `Onboarding.SHOW_DAYS` = 30 giorni dopo l'ingresso.
- **`/accord welcome`** apre la lista a chiunque, anche a chi non è nuovo o l'ha chiusa, in una finestra piccola con la stessa carta: senza voce in `onboarding` mostra le stesse voci con il loro stato, senza riga del Centro azioni e senza scrivere nulla.
- La riga in chat esce dopo le ore di quiete (`Notify:WhenFree`). *Cancella i dati della gilda* (M6.1) tiene `onboarding`, così una lista chiusa resta chiusa.

### 5.4 Come è fatta (M12.4)

- `Data/Onboarding.lua` (`ns.Onboarding`) e `UI/Onboarding.lua` (`ns.OnboardingView`); `UI/Actions.lua` chiede alla vista la carta in cima all'*Inbox*; `UI/Settings.lua` ha `View:ShowCard("main" | "contacts")`.
- `Data/Accounts.lua` emette `CHARACTER_GUILD_CHANGED(guid, da, a)` quando la gilda letta per un personaggio cambia: è il segno `seen`. Il registro si legge con `Compat.Guild.QueryEventLog` e, 10 s dopo, `Compat.Guild.EventLog`.
- Tutto il deposito si guarda una volta per voce e per sessione (ONB-02); poi basta il record che arriva (`STORE_CHANGED`). Le voci si rileggono 0,5 s dopo gli eventi dei loro moduli.

### 5.5 Solo su questo computer

La lista non scrive record e non manda nulla: legge dati che il client ha già. Gli ufficiali **non** vedono l'avanzamento di un nuovo membro (SPEC-10 Q36): servirebbe un insieme nuovo con un messaggio per ogni voce, e la lista è un aiuto per chi entra, non un controllo. Chi vuole sapere se un nuovo membro ha scelto il main o dichiarato lo vede già nel roster e nella season.

## 6. I mentori (M12.5)

### 6.1 L'insieme `mentor`

Un insieme sincronizzato su `GUILD` come gli altri, un record per account che si offre:

| Campo | Valori | Note |
|---|---|---|
| id | `M:<GUID>` | il personaggio con cui il mentore vuole essere contattato |
| `on` | `true` | l'offerta è valida |
| `off` | `true` | il mentore ha lasciato l'elenco: nessun altro campo |
| `topics` | da 0 a 6 tra `raids`, `dungeons`, `pvp`, `professions`, `leveling`, `addons` | gli argomenti su cui aiuta |
| `note` | 0–80 byte | testo libero, senza `|`, a capo né caratteri di controllo |

Esattamente uno tra `on` e `off`. `maxBytes = 256`. Un record `off` scade 60 giorni dopo il suo `time` (come una nota estesa cancellata); un record `on` non scade, ma conta solo se il personaggio è nel roster.

**Regole di fiducia (MEN-01…MEN-04):**

- **MEN-01 Solo la propria offerta.** Un record `M:<GUID>` si accetta solo se l'autore è `GUID` o un personaggio dello stesso account con l'elenco reciproco (NET-10), o se lo ritrasmette un ufficiale (NET-11) con il contenuto dell'autore; nessuno, ufficiali compresi, mette un altro nell'elenco (`owner`), come SEA-01.
- **MEN-02 Forma.** Campi e limiti sopra; un argomento sconosciuto, una nota con `|` o un record con altri campi si rifiutano (`owner`).
- **MEN-03 Uno per account.** `Mentors:Join` rifiuta (`account`) l'offerta di un secondo personaggio dell'account (prima si lascia quella vecchia); se arrivano offerte vive di due personaggi dello stesso account, la vista mostra quella con il `time` più vecchio (a parità il GUID minore), senza rifiutare l'altra, come SEA-05.
- **MEN-04 Ritmo.** Al massimo 10 revisioni all'ora per autore si accettano da chi riceve (`rate`): entrare e uscire di continuo non inonda la gilda.

### 6.2 Entrare e uscire

- **Solo dal clic** (RC-04): *Offer to mentor new members* nella modalità *Mentors* della vista *Reputation* e nella riga di *What I share* (§8). Nessun record esiste prima del clic: l'offerta è **spenta di predefinito** (SPEC-10 Q37).
- **Lasciare** (*Leave the mentor list*) scrive subito `off` (una revisione nuova, così arriva a tutti) e l'account sparisce dall'elenco e dalle coppie di ogni client al suo arrivo; chi riceve un `off` toglie le coppie già mostrate al prossimo ridisegno. Si può tornare quando si vuole (un `on` nuovo). È il criterio di M12.5.
- **Chi esce dalla gilda** non compare più (non è nel roster); il suo record resta finché non scade o non lo cambia.

### 6.3 L'elenco dei mentori

La modalità *Mentors* della vista *Reputation* mostra a **tutti** i membri l'elenco delle offerte vive (nome del personaggio, main dell'account, argomenti, nota, online o no) con il pulsante *Whisper* (apre la casella della chat con `/w Nome `, come SOC-20: l'addon non manda nulla). Filtro per argomento. In cima, per il giocatore, la propria offerta con *Edit* e *Leave*. L'elenco è pubblico perché chi si offre vuole essere trovato; le **coppie** no (§6.4).

### 6.4 Le coppie suggerite

Solo sul client di un ufficiale o del Guild Master (`Mentors.PAIRS_VISIBLE_TO = "officers"`, un solo punto, SPEC-10 Q37), calcolate quando si apre la pagina *Trials* o la scheda di un nuovo membro, **mai salvate e mai mandate** (RC-05).

- **I nuovi membri** (dal punto di vista dell'ufficiale): gli account con una prova aperta (§4) e quelli con un evento `join` nella cronologia degli ufficiali ([SPEC-12 §2.2](SPEC-12-officer-tools.md#22-eventi-e-record)) negli ultimi `Mentors.NEW_DAYS` = 30 giorni, ancora nel roster. La lista dell'accoglienza (§5) non serve: è solo sul client del membro.
- **I mentori**: gli account con un'offerta viva (§6.1), nel roster, diversi dal nuovo membro e che non sono a loro volta nuovi membri.
- **Il punteggio** viene dal grafo sociale di [SPEC-07 §3](SPEC-07-reputation-social.md#3-indice-sociale) (minuti di gioco insieme per coppia di account negli ultimi 30 giorni, lo stesso dell'indice sociale e della mappa dei gruppi), in quest'ordine:
  1. **insieme** = i minuti tra mentore e nuovo membro (già si conoscono);
  2. **in comune** = la somma, sui compagni `c` di entrambi, di `min(minuti(mentore, c), minuti(nuovo, c))` (giocano con le stesse persone);
  3. **stesso gruppo** della mappa dei gruppi (SOC-10) prima degli altri;
  4. **ore in comune** della mappa della disponibilità ([SPEC-14 §8](SPEC-14-calendar-raids-season.md#8-mappa-della-disponibilità-m108)), con `season` acceso: le caselle in cui entrambi giocano di solito (livello 2 o più), se l'ufficiale vede i nomi (Q23);
  5. a parità il livello più alto del main del mentore, poi il nome.
  Stessi dati, stesse coppie su ogni client di ufficiale.
- **Quante**: per ogni nuovo membro al massimo 3 mentori; un mentore compare come **prima scelta** di al massimo `Mentors.MAX_PER_MENTOR` = 3 nuovi membri, assegnati in ordine di ingresso (il più vecchio prima): oltre, la prima scelta passa al successivo, così un mentore molto giocato non riceve tutti.
- **Che cosa si mostra**: accanto a ogni nuovo membro i mentori con il motivo ("2 h together", "plays with the same people", "same group", "usually online at the same hours"), o "No play together yet" quando il grafo non dice nulla; *Whisper* per il mentore e per il nuovo membro. Nessuna coppia si accetta o si registra: l'ufficiale parla con i due nel gioco.
- **Solo chi si è offerto**: il calcolo parte dall'elenco delle offerte vive al momento del calcolo; un account senza offerta, o con `off`, non è mai un mentore suggerito (criterio di M12.5).

I minuti di gioco insieme sono dati che ogni client riceve (`coplay` va a tutta la gilda, SPEC-03 §4): tenere le coppie per gli ufficiali è una **regola dell'interfaccia**, come i nomi del censimento (SPEC-10 Q17) e la mappa dei gruppi (Q3), e *What I share* lo dice (§8). Chi ha spento *Record time played together* non pubblica co-play nuovo, ma gli altri osservano ancora i gruppi in cui c'è anche lui (SPEC-11 §5).

## 7. Traffico

Stima per la gilda di 50 client di [SPEC-02 §4](SPEC-02-network-protocol.md#4-sincronizzazione):

| Parte | Dove viaggia | Stima |
|---|---|---|
| Testo di reclutamento | da nessuna parte | 0 |
| Accoglienza | da nessuna parte | 0 |
| Coppie suggerite | da nessuna parte (calcolate sui dati che il client ha) | 0 |
| `trials` | solo `OFFICER` e whisper tra ufficiali (TRI-02) | una prova circa 120 B sul filo, una nota fino a circa 900 B; qualche scrittura a settimana; una voce di 11 byte nel riepilogo `m` di `OHELLO`: meno di **2 B/min** per ufficiale |
| `mentor` | `GUILD`, nel riepilogo per autore come gli altri insiemi | circa 120 B sul filo per record, scritto solo da un clic; ogni offerta nuova o cambiata fa richiedere il gruppo del suo autore una volta (come una mappa della disponibilità, R17): con 10 offerte a settimana meno di **2 B/min** per client in media |

**Il primo scambio.** Il giorno in cui si accende `recruit` nessun record di `trials` o `mentor` esiste: le offerte e le prove nascono dai clic, sparse nei giorni seguenti, quindi M12 **non si somma** al primo scambio delle mappe della disponibilità né a quello del manuale. Il tetto resta quello accettato dal proprietario per il primo scambio (SPEC-10 Q26, R17): la media fino a circa **550 B/min** e il client più carico al picco misurato (2,3 KB/min); a gilda allineata la media al massimo **450 B/min** e il client più carico **2 KB/min** ([SPEC-09 §7](SPEC-09-quality-release.md#7-budget-di-traffico-condiviso-m10)). Il limite **non sale per M12**.

**Da misurare in M12.5** (`Tests/test_mentors.lua`, con `recruit` acceso, lo scenario di M10.8 al primo scambio e a gilda allineata, con un account su dieci che entra nell'elenco dei mentori ed esce durante i 45 minuti): la media e il client più carico devono restare entro i limiti sopra. Se non ci stanno, prima si riduce (le offerte in una voce a parte del riepilogo come il censimento, `c`/`cb`), poi si chiede al proprietario. M12.3 misura le prove nel simulatore degli ufficiali di M8.2 (`Tests/test_sync_sim.lua`): nessun record su `GUILD` né in whisper a un membro, e il traffico degli insiemi degli ufficiali sotto i 150 B/min per ufficiale di SPEC-12 §1.5.

## 8. *What I share*, diagnostica, demo, backup

- **What I share** ([SPEC-11 §5](SPEC-11-data-trust.md#5-pannello-cosa-condivido-m76)), con `ShareModel.Add` e `def.feature = "recruit"`:
  - riga **Mentor offer** / *Offerta di mentore* (`mentor`): a chi *the whole guild*; il contenuto: offerta valida o no, argomenti, nota, con `rev` ed età; l'interruttore è l'offerta stessa (*Offer to mentor new members* / *Offriti come mentore ai nuovi membri*, spento di predefinito); la nota dice: "Officers may see you suggested as a mentor for new members, from the time you played together." Con l'offerta spenta e un record `off` la riga dice che l'uscita è stata mandata;
  - riga **Welcome checklist** / *Lista di benvenuto*: *only on this computer*, nessun interruttore (non si manda nulla);
  - per gli ufficiali, la riga *Officer tools* di SPEC-12 §7 aggiunge le prove scritte da questo personaggio e le sue note di prova (**conteggi**, mai il testo), a chi *officers, on the officer channel* (o *only on this computer* finché il canale non è provato);
  - il testo di reclutamento non compare: non si condivide (le due righe dell'ufficiale restano sul computer).
- **`/accord debug`**: per `trials` e `mentor` il numero di record e i rifiuti per motivo; per l'accoglienza il segno usato (`seen`, `log`, `none`) e se le funzioni del registro della gilda ci sono. Mai nomi, GUID o testi (SPEC-09 §6).
- **Demo** (M7.4, `Data/Demo.lua`): ogni passo aggiunge la sua parte alla gilda inventata: M12.2 una season aperta con le sue dichiarazioni, una composizione obiettivo con due mancanze e la pagina *Guild info* (solo con `recruit` acceso); M12.3 tre prove (una che finisce oggi, una prorogata, una chiusa) con due note; M12.4 la lista di un personaggio nuovo con due voci spuntate; M12.5 cinque offerte di mentore e i nuovi membri con le coppie. Nella demo nulla si manda.
- **Backup** (M7.5): nessuna delle parti di M12 entra nel backup personale; l'offerta di mentore torna dalla sincronizzazione (la tengono gli altri client), le prove sono dati degli ufficiali, la lista è locale.

## 9. Test per passo

| Passo | File | Casi |
|---|---|---|
| M12.2 | `Tests/test_recruit.lua` | il testo cambia quando cambiano le mancanze (una dichiarazione, l'obiettivo, la fonte FDCP); mancanze di MS1, non di MS2; descrizione dal primo paragrafo di `P:info`, con i collegamenti ridotti a testo, tagliata sulla parola; parti mancanti con il motivo (nessuna season, nessun obiettivo, nessuna mancanza, pagina assente o modello, `raid` o `season` spenti); `chat` entro 255 byte e `discord` entro 1900 caratteri anche con testo italiano; nessun `|`; nessuna funzione di invio chiamata (REC-01); solo ufficiali; interruttore spento |
| M12.3 | `Tests/test_trials.lua` | solo ufficiali scrivono e ricevono; un membro rifiuta ogni record, anche il proprio; mai su `GUILD` né in whisper a un membro (ogni messaggio del simulatore), solo su questo computer senza S5; proroga sì, riapertura e accorciamento no (`locked`); una nota per ufficiale, solo il suo autore; il promemoria compare il giorno della fine, una volta, anche dopo un `/reload` e un secondo accesso, e di nuovo dopo una proroga; la riga sparisce alla chiusura; chi esce dalla gilda; OFF-10 cancella le prove; interruttore spento |
| M12.4 | `Tests/test_onboarding.lua` | un personaggio entrato con Accord già installato ha la lista; uno che era in gilda quando la gilda ha cominciato a usare Accord no (ONB-02); un alt di un account già in gilda no (ONB-03); il segno del registro della gilda con il client finto e senza le funzioni; ogni voce si spunta da sola e non torna indietro; voci nascoste quando non si possono fare; *Dismiss* per sempre; 30 giorni; nulla si manda; `/accord welcome` per chiunque |
| M12.5 | `Tests/test_mentors.lua` | solo la propria offerta (MEN-01), uno per account, ritmo; si esce in ogni momento e l'uscita arriva a tutti; solo chi si è offerto è suggerito; punteggio e ordine deterministici sullo stesso grafo; al massimo 3 per nuovo membro e 3 prime scelte per mentore; le coppie solo sul client di un ufficiale, mai in un record o in un messaggio; traffico nel simulatore (§7); interruttore spento |

## 10. Cosa resta da verificare nel client

Nella prova di M12.6 (`docs/checklists/M12.md`):

- il criterio di uscita: un ufficiale copia un testo di reclutamento costruito dalle mancanze della season; un membro in prova compare nel Centro azioni quando la prova finisce; un nuovo membro vede la lista di benvenuto;
- che la riga `chat` di 255 byte, con lettere accentate, entri intera nella casella della chat del gioco e in un canale, e il testo `discord` incollato in Discord;
- il registro degli eventi della gilda su Forever: se `QueryGuildEventLog`, `GetNumGuildEvents` e `GetGuildEventInfo` globali esistono, se un membro semplice li può leggere, se l'ingresso del proprio personaggio c'è e con quale età; senza, solo chi aveva Accord prima di entrare vede la lista da sola (SPEC-10 R19);
- che la gilda del personaggio si legga subito dopo l'ingresso (`GUILD_CHANGED`, `PLAYER_GUILD_UPDATE`) e il segno `seen` nasca al momento giusto;
- il canale degli ufficiali (S5) per le prove e le note, e un membro che non le riceve;
- il giorno della fine di una prova: il promemoria parte alle 00:00 UTC del giorno `ends` (l'una o le due di notte in Italia), con l'ora del server; da controllare che la data mostrata, UTC come nella cronologia, sia quella che l'ufficiale si aspetta;
- con FDCP come fonte, che `GetMember` sul client di un membro dica se il suo personaggio è nel pool (voce `season` dell'accoglienza);
- le coppie suggerite con il gioco di gruppo reale di una gilda (una serata di dungeon con un nuovo membro).
