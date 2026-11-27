# SPEC-17: Economia di gilda

Specifica della milestone M13 ([roadmap](../roadmap/M13-economy.md)): gli **ordini di crafting** con i loro stati, nati dalle richieste di M3 e da "who can craft" ([SPEC-06](SPEC-06-professions-recipes.md)); la **domanda di materiali** della gilda; la **lista dei desideri** di ogni giocatore; la **lista della spesa** personale, con i conteggi *posseduti/necessari* che l'assistente delle professioni di M17 riusa; la **bacheca compro/vendo** (WTS/WTB) con la doppia conferma manuale; gli **obiettivi di gilda** letti dai registri della banca ([SPEC-08](SPEC-08-guild-bank.md)); e il disegno, solo descritto, delle **aste** con un ufficiale come host (M13.7). Ogni sezione dice il passo che la realizza (M13.2–M13.7; M13.8 è la prova e il rilascio `v0.13.0`). Le scelte che spettano al proprietario sono in [SPEC-10](SPEC-10-risks-open-questions.md) (Q40–Q49), con una proposta che il codice applica finché il proprietario non risponde. La decisione di architettura è [ADR 0028](../adr/0028-guild-economy-never-moves-gold-or-items-each-side-writes-its-own-record.md).

Nomi di codice, campi e testi dell'interfaccia in inglese (con la traduzione italiana in `itIT.lua`, [ADR 0015](../adr/0015-interface-and-documentation-languages.md)). Le ore dei record sono ore del server in secondi (`Compat.ServerTime()`); un **giorno** è il giorno UTC scritto `AAAAMMGG`, come in [SPEC-12](SPEC-12-officer-tools.md). Le lunghezze sono in **byte** UTF-8 (una lettera accentata italiana conta 2). Un **oggetto** è il suo `itemID`; le varianti (incanti, suffissi) non contano in M13.

## 1. Principi

Valgono le regole di integrazione del proprietario ([SPEC-14 §1](SPEC-14-calendar-raids-season.md#1-principi), [ADR 0022](../adr/0022-integrations-with-raid-and-loot-addons.md)) e quanto resta fuori sempre ([SPEC-00 §3](SPEC-00-vision-scope.md#3-cosa-resta-fuori-sempre)). In più:

| # | Regola | Che cosa vuol dire qui |
|---|---|---|
| ECO-01 | **L'addon non sposta mai oro né oggetti** | nessuna chiamata che scambia, spedisce, compra, vende, deposita o preleva (`InitiateTrade`, `AcceptTrade`, `SendMail`, `TakeInboxItem`, `PlaceAuctionBid`, `C_CraftingOrders.PlaceNewOrder`, `DepositGuildBankMoney`…), in nessun modulo di M13; un ordine, un affare o un obiettivo **registra** ciò che i giocatori fanno a mano nel gioco. Il test di ogni passo sostituisce quelle funzioni nel client finto con versioni che falliscono il test se chiamate, come REC-01 |
| ECO-02 | **Ognuno scrive solo la propria parte** | un ordine e un affare coinvolgono due giocatori: ognuno scrive un **record suo** (il compratore il suo, l'artigiano il suo), e lo stato che si vede si ricava dai due; nessun record ha due autori, quindi nessuno cambia la parte dell'altro e due scritture insieme non si contendono la stessa `rev` (§3.2, §7.2) |
| ECO-03 | **Chiuso solo da entrambi** | un ordine è *consegnato* e un affare è *concluso* solo quando **tutti e due** lo hanno confermato a mano; una conferma da una parte sola resta aperta, e lo dice |
| ECO-04 | **Prezzi come testo** | il prezzo di un ordine o di un annuncio è un testo scritto dal giocatore (`"5g"`, `"materiali + mancia"`), mai un numero che l'addon riscuote; nessun conto, nessun saldo, nessuna commissione |
| ECO-05 | **Quello che si possiede resta sul computer** | i conteggi di borse, banca, alt e posta (§5) stanno solo in questo computer e non viaggiano mai; la lista della spesa è privata finché il giocatore non preme *Ask the guild* o *Ask the bank*, e anche allora esce solo ciò che **manca** |
| ECO-06 | **Altri addon in sola lettura** | i prezzi vengono da Auctionator, se è installato, solo attraverso la sua API pubblica documentata e con versione, mai dalle sue SavedVariables, mai richiesto (§5.7); il resto di Accord funziona uguale senza |
| ECO-07 | **Il traffico condiviso non sale** | M13 aggiunge quattro insiemi piccoli, scritti da clic (§10); il limite di [SPEC-09 §7](SPEC-09-quality-release.md#7-budget-di-traffico-condiviso-m10) resta quello di oggi |

## 2. Moduli, interruttore, dati locali

### 2.1 L'interruttore `econ`

Tutto M13 è dietro un interruttore nuovo, **`econ`**, in [`Core/Features.lua`](../../AzerothAccord/Core/Features.lua), **spento** fino a M13.8. Spento: non si vede nulla di M13 (né la vista *Market*, né la pagina *Shopping list*, né le righe del Centro azioni, né le righe di *What I share*), i comandi `/accord market` e `/accord shopping` rispondono come comandi sconosciuti, gli insiemi `orders`, `wish`, `board` e `goals` non si scrivono, non si accettano e non si mandano (`feature = "econ"` nella definizione di `Net/Store.lua`), il riepilogo `ec` non si manda (§10.2), l'inventario non si legge e Auctionator non si chiama. Il pulsante *Request craft* resta quello di M3 (un sussurro precompilato).

`econ` **non** accende altri interruttori (nessuna voce in `Features.IMPLIES`): le righe del Centro azioni e gli avvisi vogliono anche `actions`; tutto il resto usa insiemi senza interruttore (`recipes`, `recipecat`, `bank`, `bankreq`). Come gli altri interruttori, i moduli chiedono `Features.On("econ")` quando agiscono, mai una volta sola al caricamento. I test lo accendono e lo spengono (`Tests/test_features.lua` e i test di ogni passo, §12).

### 2.2 File nuovi

| File | Contenuto | Passo |
|---|---|---|
| `Data/Orders.lua` | l'insieme `orders`, gli stati ricavati, la migrazione dei promemoria di M3, il fornitore `orders` del Centro azioni, gli avvisi (§3) | M13.2 |
| `UI/Orders.lua` | la modalità *Orders* della vista *Market*, la finestra *New order* | M13.2 |
| `Data/Reagents.lua` | i materiali di una ricetta letti dal gioco, la loro cache, la scomposizione degli intermedi (§5.2, §5.3); riusato da M17 | M13.3 |
| `Data/Demand.lua` | la domanda di materiali, calcolata (§4.1) | M13.3 |
| `Data/Wishlist.lua`, `UI/Wishlist.lua` | l'insieme `wish` e la modalità *Wishlist* (§4.2) | M13.3 |
| `Data/Inventory.lua` | i conteggi posseduti: borse, banca, alt, posta, banca di gilda (§5.4, §5.5); **il modulo che M17 riusa** | M13.4 |
| `Data/Prices.lua` | i prezzi di Auctionator (§5.7); riusato da M17 | M13.4 |
| `Data/Shopping.lua`, `UI/Shopping.lua` | la lista della spesa e la pagina *Shopping list* della vista *Professions* (§5) | M13.4 |
| `Data/Board.lua`, `UI/Board.lua` | l'insieme `board` e la modalità *Board* (§6) | M13.5 |
| `Data/Goals.lua`, `UI/Goals.lua` | l'insieme `goals`, l'avanzamento dai registri, la modalità *Goals* (§7) | M13.6 |

**Una vista nuova**, *Market* (`market` in `Config.VIEWS`, dopo `bank`; `/accord market`), con le modalità *Orders*, *Wishlist*, *Demand*, *Board* e *Goals* (`View.AddMode`, in quest'ordine, ognuna aggiunta dal suo passo). La lista della spesa è una pagina della vista *Professions* (`/accord shopping`), accanto al catalogo, perché parte dalle ricette e perché M17 vi aggiunge la pagina *Levelling*.

### 2.3 Eventi del Bus

`ORDERS_CHANGED(id)` (un ordine o la parte dell'artigiano arrivati o scritti; `id` nil = più ordini), `WISHLIST_CHANGED(guid)`, `DEMAND_CHANGED()` (la domanda ricalcolata), `INVENTORY_CHANGED(guid)` (i conteggi di un personaggio dell'account: borse, banca o posta), `REAGENTS_CHANGED(recipeID)` (i materiali di una ricetta letti dal gioco), `PRICES_CHANGED()` (Auctionator ha dati nuovi), `SHOPPING_CHANGED()`, `BOARD_CHANGED(id)`, `GOALS_CHANGED(id)`. Si aggiungono all'intestazione di `Core/Bus.lua`. `INVENTORY_CHANGED`, `REAGENTS_CHANGED` e `PRICES_CHANGED` sono l'interfaccia che M17 ascolta.

### 2.4 Dati locali

Nessuna migrazione di schema: le chiavi nuove si aggiungono dove mancano, al primo uso.

| Chiave | Contenuto | Sezione |
|---|---|---|
| `AzerothAccordDB.inventory` | `[reame][GUID] = { bags, bank, mail, bagsAt, bankAt, mailAt, mailPartial, faction }`: per ogni personaggio dell'account i conteggi `{ [itemID] = n }` dell'ultima lettura e la sua ora | §5.4 |
| `AzerothAccordDB.reagents` | `[recipeID] = { out, made, r = { { itemID, n } … }, at, build }`: i materiali di una ricetta come li ha dati il gioco | §5.2 |
| `AzerothAccordDB.shopping` | `{ list = { { recipe, n } … }, breakdown, skill, at }`: la lista della spesa dell'account | §5.1 |
| `GuildKey:Data().econ` | `{ next, seen, migrated, hidden }`: il contatore degli id, i libri degli avvisi, i promemoria di M3 già offerti come ordini, gli autori della bacheca nascosti da questo giocatore | §3, §6 |

`inventory`, `reagents` e `shopping` sono **per account** (tutti i personaggi del computer li vedono) e **fuori da ogni gilda**: un alt in un'altra gilda conta lo stesso (§5.4). Niente di questo si manda (ECO-05) e niente entra nel backup personale (M7.5): l'inventario si rilegge, i materiali si richiedono al gioco, la lista si rifà. *Cancella i dati della gilda* (M6.1) toglie `econ`, non l'inventario.

## 3. Gli ordini di crafting (M13.2)

Un **ordine** dice: *il compratore B chiede all'artigiano C di creare `n` volte la ricetta R*. Nasce da *Request craft* (SPEC-06 §2.3), che con `econ` acceso apre la finestra *New order* invece del solo sussurro.

### 3.1 L'insieme `orders`

Un insieme sincronizzato su `GUILD`, con due tipi di record, uno per parte (ECO-02):

| Record | Id | Campi | Chi scrive | `maxBytes` |
|---|---|---|---|---|
| Ordine | `O:<GUID compratore>:<n>` | `crafter` (GUID), `recipe` (spellID), `item` (itemID creato, se noto), `count` (1–`Orders.MAX_COUNT` = 200), `mats` = `buyer` \| `crafter` \| `mixed` (chi porta i materiali), `price` (0–24 byte, testo, ECO-04), `note` (0–80 byte), `by` (giorno, facoltativo: entro quando), `created`, `state` = `open` \| `received` \| `cancelled`, `closed` (ora, con uno stato diverso da `open`) | l'account del compratore | 384 |
| Parte dell'artigiano | `A:<GUID compratore>:<n>` (lo stesso numero dell'ordine) | `crafter` (GUID), `state` = `accepted` \| `declined` \| `working` \| `ready` \| `handed`, `note` (0–80 byte), `at` (ora dell'ultimo passaggio) | l'account dell'artigiano dell'ordine | 256 |

Il numero `n` cresce per compratore (`GuildKey:Data().econ.next`); un ordine non si riusa. `note` e `price` passano dalla pulizia di SPEC-15 §4.4 (niente `|`, a capo né caratteri di controllo).

### 3.2 Gli stati che si vedono

Lo stato dell'ordine non si scrive: ogni client lo **ricava** dai due record, nello stesso modo (`Orders.State(o, a)`):

| Stato | Quando | Chi può agire |
|---|---|---|
| *requested* | ordine `open`, nessuna parte dell'artigiano (o una parte di un altro personaggio) | l'artigiano accetta o rifiuta; il compratore annulla |
| *accepted* | ordine `open`, parte `accepted` | l'artigiano passa a *in progress* o *ready*, o rinuncia (`declined`); il compratore annulla |
| *in progress* | ordine `open`, parte `working` | come sopra |
| *ready* | ordine `open`, parte `ready` | i due si incontrano nel gioco; ognuno segna la consegna |
| *delivered* | ordine `received` **e** parte `handed` (ECO-03) | nessuno: è chiuso |
| *cancelled* | ordine `cancelled`, oppure parte `declined`, oppure scaduto (§3.4) | nessuno: è chiuso |

Con una consegna confermata da una parte sola la riga resta *ready* e dice chi manca: "Delivered on Bob's side, waiting for you to confirm" o "Waiting for Alice to confirm she received it". È il criterio di M13.2 ("both mark it delivered"). Il compratore può segnare `received` anche da *accepted* o *in progress* (l'artigiano ha consegnato senza passare da *ready*); l'artigiano può segnare `handed` dagli stessi stati.

### 3.3 Regole di fiducia (ORD-01…ORD-06)

- **ORD-01 Solo il compratore e l'artigiano.** Un record `O:` si accetta solo se l'autore è il GUID del suo id o un personaggio dello stesso account con l'elenco reciproco (NET-10), o se lo ritrasmette un ufficiale (NET-11) con il contenuto dell'autore. Un record `A:` si accetta solo se l'autore è il `crafter` dell'ordine o un personaggio del suo account, con le stesse regole. Nessuno, ufficiali compresi, scrive la parte di un altro (`owner`). È il criterio di M13.2.
- **ORD-02 Forma.** Campi e limiti di §3.1; `crafter` diverso dal compratore e dal suo account; `recipe` e `item` interi positivi; `by` non oltre 60 giorni dalla creazione. Altrimenti `owner`.
- **ORD-03 Il contenuto non cambia.** Dopo la prima scrittura `crafter`, `recipe`, `item`, `count`, `mats`, `price` e `created` restano quelli; una revisione dell'ordine cambia solo `state`, `note` e `closed`. Anche `crafter` della parte deve essere quello dell'ordine. Altrimenti `locked`, come TRI-04.
- **ORD-04 Passaggi.** L'ordine: `open` → `received` o `cancelled`, mai indietro. La parte: `accepted` → `working` → `ready` → `handed`, con `declined` da `accepted`, `working` o `ready` (e come prima scrittura), mai da `handed`; uno stato può saltare in avanti (`accepted` → `ready`), non tornare indietro. Una revisione che torna indietro si rifiuta (`locked`); una più vecchia di quella tenuta la scarta il deposito come `older`.
- **ORD-05 La parte aspetta il suo ordine.** Una parte `A:` che arriva prima del suo `O:` non si può controllare (non si sa chi è l'artigiano): aspetta (motivo `wait`, al massimo 10 minuti e 50 record, come il catalogo delle ricette) e si accetta quando l'ordine arriva.
- **ORD-06 Ritmo e limiti.** Al massimo `Orders.MAX_OPEN` = 10 ordini aperti per compratore (contando il suo account); al massimo 30 revisioni all'ora per autore si accettano da chi riceve (`rate`); `Orders:Create` rifiuta oltre i limiti (`limit`). L'artigiano non ha un limite di ordini ricevuti: rifiuta quelli che non vuole.

Il motivo di rifiuto (`owner`, `locked`, `wait`, `rate`) arriva al contatore di `/accord debug` attraverso `Net/Store.lua`. Un client `v0.12` non conosce l'insieme e lo ignora (SPEC-02 §6), senza contarlo come rifiutato.

### 3.4 Durata e conservazione

- Un ordine ancora *requested* dopo `Orders.REQUEST_DAYS` = 14 giorni, o con `by` passato da 7 giorni senza consegna, si mostra *cancelled* ("expired"): lo decide ogni client dalla data, senza scrivere nulla.
- Un ordine chiuso (consegnato, annullato o scaduto) e la sua parte si cancellano **30 giorni** dopo la chiusura (la più recente tra `closed` e `at`), come le richieste chiuse della banca dopo 60 (SPEC-02 §6).
- Un compratore o un artigiano che esce dalla gilda: i suoi ordini aperti si mostrano *cancelled* ("left the guild") dopo una lettura del roster non vuota; i record restano fino alla scadenza.

### 3.5 Nascita di un ordine

- **Dal pulsante *Request craft*** (catalogo, "who can craft", scheda del membro): la finestra *New order* (`UI/Orders.lua`) mostra la ricetta con l'icona, l'artigiano (scelto; un menu degli altri che la sanno creare, online prima, da `Crafters:Who`), *How many*, *Materials* (*I bring them* / *You use yours* / *Some of each*, segmentati), *Price* e *Note*, e i materiali della ricetta con il proprio *posseduti/necessari* (§5) quando sono noti. Il pulsante pieno è *Place order*. Sotto, spento di predefinito, *Also whisper <nome>* apre la casella della chat con il sussurro di M3 (l'addon non lo manda, SPEC-06 §2.3).
- **Anche offline**: un ordine si può fare a un artigiano non online (arriva con la sincronizzazione); la finestra lo dice ("Bob is offline: he will see the order when he logs in").
- **Un artigiano per ordine** (SPEC-10 Q41): un ordine "a chiunque sappia crearla" vorrebbe una gara tra artigiani su chi lo prende, cioè due scrittori dello stesso dato.
- `Orders:Create` emette ancora `CRAFT_REQUESTED(guid, recipeId)`; il fornitore `craft` di M9 (SPEC-13 §2.3) con `econ` acceso non registra più promemoria nuovi: li sostituiscono le righe degli ordini.

### 3.6 I promemoria di M3 (la migrazione)

I promemoria locali di *Request craft* (`GuildKey:Data().craftAsks`, `{ guid, recipeId, at }`, al massimo 20, SPEC-13 §2.3) erano sussurri: l'artigiano non sa di averli in Accord. La migrazione **non li pubblica da sola** (SPEC-10 Q42): alla prima apertura della modalità *Orders* con `econ` acceso, ogni promemoria ancora aperto e più giovane di 7 giorni diventa una riga *From your earlier requests* con *Make it an order* (apre *New order* già compilata con la ricetta e l'artigiano, quantità 1) e *Dismiss*. Un promemoria offerto non torna (`econ.migrated[<guid>:<recipeId>:<at>]`); quelli non toccati scadono come prima dopo 7 giorni. È il criterio di M13.2 ("old M3 requests are migrated"): nessuna richiesta di prima si perde, nessuna diventa pubblica senza un clic.

### 3.7 Centro azioni e avvisi

- **Il fornitore `orders`** ([SPEC-13 §2.1](SPEC-13-action-center-notices.md#21-il-fornitore)), registrato da `Data/Orders.lua` con `feature = "econ"`: all'artigiano ogni ordine *requested* ("Alice ordered 2 × Flask of the Titans", urgenza 2); al compratore ogni ordine *ready* ("Bob has your Flask of the Titans ready", urgenza 2); a entrambi una consegna confermata solo dall'altro ("Confirm the delivery of …", urgenza 2); al compratore un ordine rifiutato o scaduto, una volta (urgenza 1, sparisce con *Done*). Ogni riga apre la modalità *Orders* su quell'ordine.
- **Gli avvisi** del modulo `orders` (livello `normal`, chat, interruttori dei tipi `notify.orders.off.<tipo>`): `new` (all'artigiano), `state` (al compratore, quando la parte cambia), `delivered` (a entrambi, alla chiusura). Una volta per ordine e stato (chiave `<id>:<stato>` nel libro di `Notify:Seen("orders")`); la prima volta tutto ciò che c'è già conta come visto, come per la banca (SPEC-08 §10).
- Con `actions` spento le righe non ci sono e gli avvisi escono in chat come quelli della banca prima di M9.

### 3.8 La modalità *Orders*

Una tabella con tre chip in cima: *For me* (l'artigiano sono io o un mio alt), *Mine* (il compratore sono io), *Everyone* (tutti, SPEC-10 Q40). Colonne: oggetto (icona, nome, `× n`), compratore, artigiano, stato (con il token di §11), materiali, prezzo, età. Il chip *Show closed ones too* aggiunge i chiusi degli ultimi 30 giorni. I pulsanti sulla riga dipendono da chi guarda e dallo stato: per l'artigiano *Accept*, *Decline*, *Working on it*, *Ready*, *Handed over*; per il compratore *Cancel*, *Received*; ognuno chiude con un secondo clic **Confirm**, come le prove (SPEC-16 §4.5). Il tooltip della riga ha la nota di entrambi, la storia dei passaggi (le ore dei due record) e i materiali con il *posseduti/necessari* di chi guarda. *Whisper* apre la casella della chat verso l'altro.

## 4. Domanda di materiali e lista dei desideri (M13.3)

### 4.1 La domanda

La **domanda** è la somma, per oggetto, dei materiali che servono alla gilda; si **calcola** su ogni client dai dati che ha e non viaggia (`Demand:Compute`, ricalcolata 1 s dopo `ORDERS_CHANGED`, `GOALS_CHANGED`, `REAGENTS_CHANGED`):

- **dagli ordini aperti** (*requested*, *accepted*, *in progress*): i materiali della ricetta (§5.2) per `count`, con la scomposizione spenta (un ordine chiede quella ricetta, non i suoi intermedi);
- **dagli obiettivi aperti** di oggetti (§7): quanto manca al traguardo.

La modalità *Demand* della vista *Market* mostra una riga per oggetto: icona e nome, quanti ne servono, da quanti ordini e obiettivi (il tooltip li elenca), quanti ne ha la banca di gilda secondo la foto che il giocatore vede (SPEC-08 §6, con l'età) e, se il giocatore ne ha, i suoi (§5.4). Un ordine di cui il client non conosce ancora i materiali si conta a parte ("Materials unknown for 2 orders": li si legge aprendo la professione, §5.2). La domanda **cambia quando un ordine si chiude** (criterio di M13.3): è un calcolo, non uno stato da tenere in ordine.

### 4.2 L'insieme `wish`

Un record **per personaggio** con i suoi desideri:

| Campo | Valori | Note |
|---|---|---|
| id | `W:<GUID>` | il personaggio che desidera |
| `e` | da 0 a `Wishlist.MAX` = 30 voci `{ i = itemID, n = quantità 1–999, u = giorno di scadenza, s = "sl" se viene dalla lista della spesa }` | la lista; vuota = nessun desiderio |
| `note` | 0–80 byte | una riga per tutta la lista |

`maxBytes = 768`. Lo scrive solo l'account del personaggio (NET-10, o un ufficiale che lo ritrasmette; WSH-01, `owner`); un oggetto due volte, una quantità fuori dai limiti, una scadenza oltre 30 giorni dal `time` del record o già passata alla scrittura si rifiutano (WSH-02, `owner`); al massimo 20 revisioni all'ora per autore (WSH-03, `rate`).

- **Scadenza** (criterio di M13.3): ogni voce ha la sua, `Wishlist.DAYS` = 14 giorni di predefinito, da 1 a 30. Una voce scaduta **sparisce da sola** su ogni client dalla data, senza scrivere; il client dell'autore la toglie dal record alla prossima scrittura. Un record senza voci vive scade 30 giorni dopo il suo `time`.
- **Chi vede**: tutta la gilda (SPEC-10 Q43): chi desidera vuole che gli altri lo sappiano.
- **La modalità *Wishlist***: in cima la propria lista (aggiungere un oggetto da un link incollato, dal nome di un oggetto della cache del client o dalla lista della spesa; la quantità; i giorni; *Remove*); sotto, i desideri della gilda per oggetto, con chi li desidera (online prima), quanti ne vuole, la scadenza, e *I have some* che apre un sussurro precompilato ("Hi! I have Linen Cloth for your wishlist.", l'addon non lo manda). Il giocatore vede accanto a ogni oggetto quanti ne ha lui (§5.4), così sa se può aiutare.
- Desiderare non è chiedere un prezzo: per comprare e vendere c'è la bacheca (§6).

## 5. La lista della spesa (M13.4)

Le decisioni del proprietario del 2026-11-27 ([M13.4](../roadmap/M13-economy.md#m134--shopping-list)): il giocatore sceglie ricette e quantità da tutta la professione; Accord somma i materiali letti dal gioco; un interruttore scompone gli intermedi; ogni materiale mostra *posseduti/necessari*; i prezzi da Auctionator; *Ask the guild* e *Ask the bank*.

### 5.1 La lista

- **Si sceglie dal catalogo** (SPEC-06 §2.4): ogni riga del catalogo della gilda ha *Add to shopping list* (anche le ricette che nessuno sa creare e quelle che il giocatore non conosce: è una lista per comprare, non per creare); la pagina *Shopping list* ha lo stesso menu delle professioni e una ricerca per aggiungere da lì. Una ricetta già in lista aumenta la quantità.
- **Ogni voce**: la ricetta, *How many* (1–999; per le ricette che danno più pezzi per volta si sceglie quante volte crearla, e la riga dice quanti pezzi ne escono), *Remove*. Al massimo `Shopping.MAX_RECIPES` = 50 ricette, anche di professioni diverse; *Clear list* con conferma.
- **Una lista per account** (`AzerothAccordDB.shopping`): la vede ogni personaggio del computer, perché si compra con uno e si crea con un altro.
- **Privata** (ECO-05): non è un record e non viaggia, finché il giocatore non preme *Ask the guild* o *Ask the bank* (§5.8), e anche allora esce solo ciò che manca.

### 5.2 I materiali, dal gioco

I materiali di una ricetta si leggono con `C_TradeSkillUI.GetRecipeSchematic(recipeSpellID, isRecraft, recipeLevel)` (nel dump di Forever `1.60.1`: argomenti `recipeSpellID`, `isRecraft` = `false`, `recipeLevel` facoltativo; restituisce `CraftingRecipeSchematic`, una struttura **di cui il dump non elenca i campi**, **[verificare]**). Si leggono i campi del client moderno, attraverso `Compat.TradeSkill.Schematic`, che tollera nomi mancanti:

- `reagentSlotSchematics`: per ogni casella `reagents` (le alternative, `{ itemID }`), `quantityRequired`, `reagentType` (si tengono solo i **materiali di base**: `Enum.CraftingReagentType.Basic`, o `required` vero quando il tipo manca; i facoltativi e i *finishing* no);
- `outputItemID` e `quantityMin` / `quantityMax`: l'oggetto creato e quanti per volta (`made` = `quantityMin`, almeno 1).

Una casella con più alternative conta la **prima** e mostra le altre nel tooltip ("or Heavy Leather"); la scelta della qualità dei materiali (`supportsQualities`) non c'è su Forever per le ricette viste (SPEC-06 §1.5) e non si gestisce.

- **Cache** (`AzerothAccordDB.reagents`): la risposta si tiene per account, con la build del client (`build`); una build nuova la fa rileggere alla prima occasione. Non è un dato personale ma neanche un record: **non viaggia** (SPEC-10 Q45).
- **Quando si legge**: alla scansione della propria professione (`RecipeScan`, SPEC-06 §1.3) per le ricette di quella professione, al massimo 50 ogni secondo; e quando una vista chiede una ricetta che non ha (`Reagents:Ensure(recipeID)`). Se il gioco risponde solo con la finestra della professione aperta (**[verificare]** in M13.8), una ricetta di una professione che il giocatore non ha resta "Materials unknown: open <professione> once with any character of this computer" finché un personaggio dell'account non apre quella professione; nessun altro ripiego in M13.4.
- **Mai inventati**: una ricetta senza risposta del gioco non ha materiali, non zero materiali.

### 5.3 Gli intermedi

Un **intermedio** è un materiale che una ricetta del catalogo crea (un *Bolt of Silk Cloth* da *Silk Cloth*). L'indice `Reagents:MakerOf(itemID)` va dall'oggetto creato (`out` della cache) alla ricetta, nella stessa professione prima, poi nelle altre; con più ricette per lo stesso oggetto vince quella con meno materiali diversi, poi l'id più basso (stesso indice, stessa scelta su ogni client).

- **L'interruttore *Break down intermediate materials*** (`shopping.breakdown`, spento di predefinito) sostituisce ogni intermedio con i materiali della sua ricetta, per `⌈mancanti / made⌉` volte, fino a 4 livelli, senza giri (un oggetto già visto nel ramo resta com'è).
- **Prima ciò che si ha**: si scompone solo la parte **mancante** dell'intermedio (SPEC-10 Q44): con 3 *Bolt of Silk Cloth* già posseduti su 5 necessari, si cercano i materiali di 2. La riga dell'intermedio resta visibile, attenuata, con "3 owned, 2 broken down".
- Con l'interruttore spento ogni intermedio è un materiale come gli altri. Cambiare l'interruttore cambia i totali (criterio di M13.4); si ricorda per account.

### 5.4 Posseduti: l'inventario dell'account (`Data/Inventory.lua`)

Il modulo che M17 riusa. Per ogni personaggio dell'account su questo computer tiene l'ultima lettura (`AzerothAccordDB.inventory[reame][GUID]`), e risponde a `Inventory:Count(itemID, opts)` con le parti separate.

| Parte | Come si legge | Quando |
|---|---|---|
| **Borse** (`bags`) | le borse `Enum.BagIndex` da `Backpack` (0) a `Bag_4` (4) e `ReagentBag` (5) se c'è: `C_Container.GetContainerNumSlots`, `GetContainerItemInfo(borsa, casella)` → `itemID`, `stackCount` | all'accesso, dopo `BAG_UPDATE_DELAYED` (raccolti per 0,5 s) e a `PLAYER_LOGOUT` |
| **Banca** (`bank`) | con la banca aperta (`BANKFRAME_OPENED`, `PLAYERBANKSLOTS_CHANGED`, `BAG_UPDATE_DELAYED` mentre è aperta): `Characterbanktab` (-2) e le borse della banca (`CharacterBankTab_1`… o le borse 6–12 del client classico, quelle che `GetContainerNumSlots` dice non vuote) **[verificare]**; la banca dell'account (`Accountbanktab`, -3) solo se il client la dà, contata **una volta** per tutti i personaggi | all'apertura e ai cambiamenti mentre è aperta; tra due visite resta l'ultima lettura |
| **Posta** (`mail`) | con la cassetta aperta (`MAIL_SHOW`, `MAIL_INBOX_UPDATE`): per ogni messaggio di `GetInboxNumItems()` gli allegati di `GetInboxItem(messaggio, allegato)` (globale: nome, `itemID`, icona, quantità…; **firma non nel dump**, **[verificare]**), saltando i messaggi in contrassegno (`GetInboxHeaderInfo`: `CODAmount` > 0) e quelli che scadono prima della prossima lettura probabile | all'apertura della cassetta; tra due visite resta l'ultima lettura, meno i messaggi già scaduti (`daysLeft`) |
| **Alt** | le stesse parti degli **altri** personaggi dell'account, dalla loro ultima lettura | sempre, dalla cache |
| **Banca di gilda** | **a parte**, mai sommata ai posseduti: la foto della banca che il giocatore vede (`Req:BankItems()`, SPEC-08 §9, con l'età) | sempre, dalla cache della banca |

- **Posseduti = borse + banca + posta del personaggio + borse, banca e posta degli alt che contano**; la banca di gilda è una colonna sua. Contano gli alt **dello stesso reame e della stessa fazione** (quelli a cui si può spedire); gli altri si vedono nel tooltip ma non si sommano (SPEC-10 Q44).
- **Ogni parte con la sua età**: il tooltip di un materiale dice "Bags 12, Bank 40 (2 days ago), Mail 5 (1 h ago), Alts: Bob 20 (bank, 5 days ago)". Una parte mai letta (un alt che non ha mai aperto la banca con Accord) dice "never read" e conta 0.
- **Posta affidabile solo quanto il gioco**: se il gioco dice più messaggi di quanti ne mostra (`GetInboxNumItems` restituisce mostrati e totali), la lettura è parziale (`mailPartial`) e la parte lo dice ("more mail than the game shows"). Gli oggetti spediti a un alt non si contano finché l'alt non apre la cassetta: la riga lo ricorda ("items sent by mail count when the receiver opens the mailbox"). Se in M13.8 la posta non si legge in modo affidabile, la parte si spegne (`Inventory.READ_MAIL = false`, un solo punto) e i posseduti restano borse, banca e alt.
- **Solo su questo computer** (ECO-05): l'inventario non è un record, non viaggia, non entra nel backup e non si vede in nessun riepilogo; un personaggio giocato da un altro computer conta solo dall'ultima volta che è entrato da qui.
- **Interfaccia per M17**: `Inventory:Count(itemID, { alts = true, mail = true, guildBank = false })` → `{ owned, bags, bank, mail, alts = { [GUID] = n }, guildBank, ages }`; `Inventory:CountMany(itemIDs, opts)`; l'evento `INVENTORY_CHANGED`. Nessuna vista legge `AzerothAccordDB.inventory` direttamente.

### 5.5 Mentre si gioca

La lista **si aggiorna mentre il giocatore raccoglie e compra** (decisione del proprietario): `BAG_UPDATE_DELAYED` rilegge le borse (0,5 s), `INVENTORY_CHANGED` ricalcola i totali (0,2 s) e la pagina aperta ridisegna le righe senza tornare in cima. Un materiale appena completato lampeggia una volta (`Motion`, spento con le animazioni). Nessuna lettura durante il combattimento oltre a quella del gioco: con `InCombatLockdown()` la rilettura aspetta la fine.

### 5.6 La pagina *Shopping list*

- In alto le ricette scelte, ognuna con quantità e *Remove*; sotto, l'interruttore *Break down intermediate materials*, i chip *Missing only* e *Count alts* (acceso) e *Count mail* (acceso).
- **Una riga per materiale**: icona e nome (colore della qualità), una **barra** *posseduti/necessari* (`Widgets.ThinBar`, `accent` su `surface-3`, `ok` quando è piena), il testo `12 / 40` in mono, *Missing 28* (in `err` finché manca), la colonna *Guild bank* (`Bank 15`, attenuata con l'età di M7.2) e, con Auctionator, il prezzo (§5.7). Ordine: prima i mancanti, poi per nome.
- **In fondo**: quanti materiali mancano, e con Auctionator il costo stimato dei mancanti ("≈ 54g 20s at auction prices, 1 day old").
- I pulsanti *Ask the guild* (tonale) e *Ask the bank* (tonale); la pagina non ha un pulsante pieno (non conclude nulla, ui-style §9.6).

### 5.7 I prezzi: Auctionator

Le regole di [ADR 0022](../adr/0022-integrations-with-raid-and-loot-addons.md) (sola lettura, API pubblica con versione, livelli 0 e 1, mai una dipendenza), estese a un addon di prezzi da [ADR 0028](../adr/0028-guild-economy-never-moves-gold-or-items-each-side-writes-its-own-record.md):

- **Livello 0**: Auctionator è caricato (`C_AddOns.IsAddOnLoaded("Auctionator")`, cartella **[verificare]** su Forever). **Livello 1**: la tabella `Auctionator.API.v1` esiste e ha le funzioni che Accord usa: `GetAuctionPriceByItemID(callerID, itemID)` (prezzo in rame o `nil`) e `GetAuctionAgeByItemID(callerID, itemID)` (giorni dall'ultima scansione), con `callerID` = `"Azeroth Accord"`; `RegisterForDBUpdate(callerID, callback)` se c'è, per `PRICES_CHANGED`. I nomi vengono dalla documentazione pubblica dell'API di Auctionator e vanno riletti lì in M13.4 prima del codice (**[verificare]**: versione e presenza dell'addon su Forever). Ogni chiamata è protetta (`pcall`); un errore o una funzione mancante riporta al livello 0 per la sessione, senza errori a schermo.
- **Mai richiesto**: senza Auctionator la colonna del prezzo e il costo non ci sono e la pagina non lo dice più di una riga ("Install Auctionator to see prices"); nessun altro addon di prezzi in M13.
- **Mai condiviso, mai salvato**: i prezzi sono dati del giocatore, letti al momento; non entrano in nessun record, nemmeno nella lista dei desideri né negli annunci della bacheca (dove il prezzo è il testo del giocatore, ECO-04).
- Un prezzo vecchio (più di 7 giorni secondo Auctionator) si mostra attenuato con l'età.

### 5.8 *Ask the guild* e *Ask the bank*

- **Ask the guild**: scrive i **mancanti** nella propria lista dei desideri (§4.2), con `s = "sl"`, la scadenza predefinita e le quantità mancanti; una voce già nella lista per lo stesso oggetto prende la quantità più grande. Oltre 30 voci: si tengono i 30 mancanti più numerosi e la finestra di conferma dice quanti restano fuori. Prima di scrivere, una conferma elenca ciò che diventa visibile alla gilda ("The guild will see: Linen Cloth × 28, Coarse Thread × 6"). Con la scomposizione accesa si chiedono i materiali di base, altrimenti gli intermedi.
- **Ask the bank**: un elenco dei mancanti **che la banca di gilda mostra** (foto visibili al grado, `Req:BankItems()`), ognuno con *Request* che apre il modulo delle richieste della banca (SPEC-08 §9, *Withdraw*) **già compilato**: l'oggetto, la quantità = il minimo tra il mancante e il disponibile, il motivo `Shopping list: <prime ricette>` (al massimo 120 byte). Il giocatore invia una richiesta per volta (SPEC-10 Q46): restano i limiti di BANK-20 (5 aperte per personaggio) e BANK-25 (non oltre il disponibile). Un materiale che la banca non mostra non compare; un mancante già chiesto con una richiesta aperta dice "Already requested". È il criterio di M13.4: la richiesta tiene solo ciò che manca.

## 6. La bacheca compro/vendo (M13.5)

### 6.1 L'insieme `board`

| Record | Id | Campi | Chi scrive | `maxBytes` |
|---|---|---|---|---|
| Annuncio | `P:<GUID>:<n>` | `kind` = `wts` \| `wtb`, `item` (itemID), `count` (1–9999), `price` (0–24 byte, testo, ECO-04), `note` (0–80 byte), `until` (ora di scadenza), `state` = `open` \| `withdrawn` \| `done`, `with` (GUID dell'altra parte, con `done`) | l'account dell'autore | 320 |
| Risposta | `D:<GUID autore annuncio>:<n>:<GUID>` | `state` = `want` \| `withdrawn` \| `done`, `note` (0–80 byte) | l'account del personaggio nell'id | 192 |

- **Durata** (SPEC-10 Q47): `Board.DAYS` = 3 giorni di predefinito, da 1 a 7 (`until` non oltre 7 giorni dal `time` della prima scrittura); al massimo `Board.MAX_OPEN` = 10 annunci aperti per account e 20 revisioni all'ora per autore (`rate`). Un annuncio scaduto **sparisce da solo** su ogni client dalla data (criterio di M13.5); i record si cancellano 7 giorni dopo `until` (o dopo `done`), le risposte con il loro annuncio.
- **Fiducia** (BRD-01…BRD-03): ognuno scrive solo i propri record (NET-10, NET-11 per la ritrasmissione; `owner`); il contenuto di un annuncio (`kind`, `item`, `count`, `price`) non cambia dopo la prima scrittura (`locked`): per un altro prezzo si ritira e se ne scrive uno nuovo; una risposta che arriva prima del suo annuncio aspetta (`wait`, come ORD-05). Non ci si risponde da soli né da un alt.

### 6.2 L'affare con la doppia conferma

1. **Interesse**: chi vede un annuncio preme *Deal* e scrive la sua risposta `want` (e, se vuole, *Whisper*). L'autore vede "Carol wants this" nella riga.
2. **Lo scambio è nel gioco**: i due si incontrano e scambiano (commercio, posta, asta): l'addon non fa nulla (ECO-01).
3. **Due conferme**: l'autore preme *Deal done with Carol* (l'annuncio passa a `done` con `with` = Carol); Carol preme *Deal done* (la sua risposta passa a `done`). L'affare è **concluso** solo con **entrambe** (ECO-03); con una sola la riga dice "Confirmed by Alice, waiting for Carol" e l'annuncio **resta aperto** per tutti gli altri (criterio di M13.5). Ogni conferma è un secondo clic **Confirm**.
4. **Ripensamenti**: finché l'altra parte non ha confermato, ognuno ritira la propria conferma o il proprio interesse (`withdrawn`); dopo le due conferme l'affare è chiuso e nessuno lo riapre. Un annuncio con una conferma dell'autore verso una persona che non conferma entro la scadenza scade come gli altri.

Un annuncio concluso mostra "Deal closed between Alice and Carol" per 7 giorni. Nessuna valutazione dei giocatori, nessuna storia degli affari oltre questi 7 giorni (SPEC-10 Q47).

### 6.3 La modalità *Board*

Due colonne di chip, *Selling* e *Buying* (o *All*), la ricerca per nome dell'oggetto, il chip *Only what I can help with* (gli annunci WTB di oggetti che il giocatore possiede, §5.4, e i WTS di oggetti nella sua lista della spesa o tra i suoi desideri). Riga: tipo (etichetta), oggetto, quantità, prezzo (il testo dell'autore, in mono), autore (online prima), scadenza, risposte. Il pulsante pieno è *Post* nella finestra di un annuncio nuovo. **Nessuna moderazione degli ufficiali** (come i gruppi e i raduni, SPEC-10 Q18 e Q24): l'autore ritira il suo annuncio; ognuno può **nascondere** gli annunci di un autore sul proprio computer (*Hide posts from <nome>*, `econ.hidden`, si annulla da *Settings*). Una riga avverte una volta: "Accord does not trade. Prices are what the author wrote; check the trade window."

## 7. Gli obiettivi di gilda (M13.6)

### 7.1 L'insieme `goals`

Un record per obiettivo, scritto dagli **ufficiali e dal Guild Master** (`Goals.WRITERS = "officers"`, un solo punto, SPEC-10 Q48), come le season (NET-12 con `authorAny`: resta valido se l'autore perde il grado):

| Campo | Valori | Note |
|---|---|---|
| id | `G:<n>` | `n` è l'ora della creazione in secondi, scelta da chi crea (due ufficiali non creano lo stesso id nello stesso secondo; se succede vince il più recente, `Store.Compare`) |
| `kind` | `items` \| `gold` | |
| `item` | itemID | solo con `items` |
| `target` | 1–100 000 pezzi, o oro in rame (da 1 a 1 000 000 oro, monete intere) | il traguardo |
| `start`, `ends` | giorni | `ends` da `start` + 1 a `start` + 180 |
| `title` | 1–40 byte | "Flasks for Naxxramas" |
| `note` | 0–120 byte | |
| `state` | `open` \| `cancelled` | un ufficiale annulla; *raggiunto* e *finito* non si scrivono (§7.2) |

`maxBytes = 384`; al massimo `Goals.MAX_OPEN` = 5 obiettivi aperti per gilda (`Goals:Create` rifiuta oltre, `limit`). Forma sbagliata: `owner`; un mittente che non è ufficiale: `authority`. Dopo la creazione cambiano solo `title`, `note`, `ends` (solo più avanti) e `state` (`locked` per il resto). Un obiettivo chiuso si tiene 90 giorni dopo la chiusura, poi si cancella.

### 7.2 L'avanzamento, dai registri della banca

L'avanzamento **non si scrive**: ogni client lo calcola dai registri della banca che ha (SPEC-08 §8, `BankLog`, l'unione deterministica dei record di tutti gli autori), con `Goals:Progress(goal)`:

- **oggetti**: la somma delle voci `deposit` di quell'oggetto, su tutte le schede, con l'ora della voce nel giorno `start` o dopo e non oltre la fine del giorno `ends`;
- **oro**: la somma dei depositi di denaro (registro del denaro, scheda 0) nello stesso intervallo; prelievi e riparazioni **non** si sottraggono (SPEC-10 Q48): un obiettivo conta quanto la gilda ha dato, non il saldo.
- **Chiuso** quando l'avanzamento raggiunge `target` (*reached*, con il giorno della voce che lo ha raggiunto) o dopo il giorno `ends` (*ended*, con l'avanzamento di quel momento): lo decide ogni client dagli stessi dati, senza scrivere nulla (criterio di M13.6). Un registro letto dopo può ancora cambiare un obiettivo *ended* in *reached* se la voce cade dentro l'intervallo.
- **Chi ha contribuito**: per account, come le donazioni (BANK-11), visibile come la loro classifica (`BankLog.DONATIONS_VISIBLE_TO`, SPEC-10 Q5).
- **Stessi dati, stesso numero**: due client con gli stessi registri danno lo stesso avanzamento (il criterio "progress matches the logs"). Un membro che non vede una scheda non ne vede il registro (SPEC-08 §8): il suo avanzamento può essere **più basso** di quello di un ufficiale, e la riga lo dice ("Counted from the logs you can see: 3 of 5 tabs"). Le ore del registro sono arrotondate (BANK-10): una voce vicina a `start` o a `ends` può cadere dalla parte sbagliata di un blocco; il tooltip dice "about".
- **Registro fermo**: il gioco tiene una storia corta e la cattura avviene solo quando un membro con Accord apre la banca. Una riga dice l'età del registro più recente ("Bank log read 3 days ago"); con più di 7 giorni la barra è attenuata.

### 7.3 La modalità *Goals*

Una card per obiettivo aperto: titolo, oggetto o oro, barra (`Widgets.ThinBar`), `340 / 500` e la percentuale, i giorni che mancano, i primi tre contributori, la nota, l'età del registro; sotto, in un chip *Closed*, quelli chiusi degli ultimi 90 giorni. Per gli ufficiali *New goal* (pulsante pieno della finestra), *Edit* e *Cancel* con **Confirm**. Un obiettivo di oggetti entra nella domanda (§4.1) per quanto manca. Un **avviso** `goals.reached` (livello `normal`, una volta per obiettivo, chiave `<id>`) a tutti quando un obiettivo è raggiunto; il fornitore `goals` del Centro azioni non c'è (un obiettivo non chiede un'azione al singolo).

## 8. Domanda, desideri e bacheca: che cosa si vede accanto

- La **scheda del membro** (SPEC-05) aggiunge, con `econ` acceso, una sezione *Market*: i suoi ordini aperti come compratore e come artigiano, i suoi desideri, i suoi annunci aperti.
- Il **catalogo delle ricette** (SPEC-06 §2.4) dice per ogni ricetta quanti ordini aperti ha ("2 open orders") e offre *Add to shopping list*.
- La vista *Bank* non cambia: gli obiettivi stanno nella vista *Market* e leggono i suoi registri.

## 9. Le aste con un ufficiale come host (M13.7, solo descritte)

M13.7 si fa **solo se il proprietario lo chiede dopo M13.6** (SPEC-10 Q49): qui c'è il disegno, non un piano di codice, e `v0.13.0` non ne ha nulla.

- **Che cosa**: un'asta di gilda di un oggetto (dalla banca di gilda o offerto da un membro), con offerte in oro dei membri, una durata e un vincitore. Pagamento e consegna restano **a mano** (ECO-01): l'asta dice chi ha vinto e a quanto, nient'altro.
- **Perché un host**: le offerte arrivano da molti client insieme e devono avere un ordine unico; con la sincronizzazione per autore ogni client potrebbe vedere un vincitore diverso. Un solo **client host**, quello dell'ufficiale che apre l'asta, ha l'ultima parola: riceve le offerte in whisper (`BID`, un messaggio nuovo, con un numero crescente per offerente), le accetta nell'ordine in cui le riceve, e pubblica lo stato (`AUC`: offerta più alta, offerente, ora di chiusura) su `GUILD`. Ogni altro client mostra solo ciò che l'host ha pubblicato.
- **Regole**: un'offerta sotto quella pubblicata più il rilancio minimo si rifiuta; un'offerta negli ultimi 60 s allunga la chiusura di 60 s (al massimo 10 volte); nessuna offerta automatica, nessun deposito, nessuna penale. Se l'host va offline l'asta si **ferma** (nessun passaggio a un altro host: due host sarebbero due verità) e riprende quando torna, con la chiusura spostata; un'asta ferma da più di un'ora si annulla.
- **Fiducia**: lo stato si accetta solo dall'host dell'asta, ufficiale (NET-12); le offerte solo di prima mano. Il registro di un'asta chiusa è un record dell'host, tenuto 30 giorni.
- **Che cosa non è**: non è un sistema di loot a offerte (GDKP: la gilda non lo propone, SPEC-10 Q30), non è un'asta del gioco, non tiene saldi. La prima domanda per il proprietario è se la gilda la vuole; la seconda, se un sistema di prezzi d'oro tra membri si accorda con le regole del manuale della gilda.
- **Traffico da misurare** prima di farla: un'asta vivace sono decine di `AUC` in pochi minuti su `GUILD`; servirebbe un limite (uno stato ogni 2 s, solo l'ultimo in coda con la stessa chiave) e una misura nel simulatore contro il budget di SPEC-09 §7.

## 10. Traffico

### 10.1 Stima

Per la gilda di 50 client di [SPEC-02 §4](SPEC-02-network-protocol.md#4-sincronizzazione):

| Parte | Dove viaggia | Stima |
|---|---|---|
| Lista della spesa, inventario, materiali, prezzi, domanda, avanzamento degli obiettivi | da nessuna parte | 0 |
| `orders` | `GUILD`, riepilogo `ec` | un ordine circa 200 B sul filo, la parte circa 120 B; ogni ordine 3–5 revisioni in tutto; qualche ordine al giorno per gilda: meno di **2 B/min** per client |
| `wish` | `GUILD`, riepilogo `ec` | un record da 100 a 500 B; scritto da un clic (o da *Ask the guild*): meno di **1 B/min** |
| `board` | `GUILD`, riepilogo `ec` | un annuncio circa 180 B, una risposta circa 100 B; qualche annuncio al giorno: meno di **2 B/min** |
| `goals` | `GUILD`, riepilogo `ec` | qualche record al mese: trascurabile |
| Riepilogo `ec` | `HELLO`, `BHELLO`, `DIGEST` | 11 byte per autore che ha record di M13, solo da chi ha `econ` acceso |

**Il primo scambio.** Il giorno in cui si accende `econ` nessun record di M13 esiste: nascono dai clic, sparsi nei giorni dopo. M13 **non si somma** ai primi scambi di M10–M12 e il limite **non sale** (ECO-07): a gilda allineata la media al massimo **450 B/min** e il client più carico **2 KB/min**; per il primo scambio restano i tetti accettati con SPEC-10 Q26 e Q39 ([SPEC-09 §7](SPEC-09-quality-release.md#7-budget-di-traffico-condiviso-m10)).

### 10.2 Il riepilogo `ec`

Gli insiemi `orders`, `wish`, `board` e `goals` non esistono per nessun client già rilasciato (fino alla `v0.12.0`): per la regola di SPEC-02 §4 ("un insieme che un client già rilasciato non conosce non entra mai in un tipo di riepilogo esistente") hanno un **tipo di riepilogo loro**, uno solo per i quattro (chiave di `"$" .. GUID`), in `ec` del `HELLO` e del `DIGEST` e in `ecb` del `BHELLO` (1 blocco), come il catalogo delle ricette (`rc`). Si manda solo con `econ` acceso (anche vuoto, così chi conosce gli insiemi si distingue da chi no); invio, richiesta e ritrasmissione sono quelli di §4.2 e §4.3. I quattro insiemi nascono insieme in `v0.13.0` e si accendono insieme: un insieme che arriva dopo (le aste di M13.7) ha un riepilogo suo.

### 10.3 Misure

Ogni passo che scrive un insieme lo misura nel simulatore (`Tests/test_sync_sim.lua`, lo scenario di M10.8: 50 client, 45 minuti, accessi e uscite), con un carico più alto del reale: M13.2 un ordine nuovo ogni 5 minuti per tutta la gilda con tutti i passaggi; M13.3 un desiderio cambiato ogni 3 minuti; M13.5 un annuncio ogni 3 minuti e una risposta ogni 5. Il test fa rispettare i limiti di sopra e controlla che un client senza `econ` non riceva né mandi nulla di M13 oltre ai `REC` su `GUILD`, che ignora.

## 11. *What I share*, aspetto, diagnostica, demo

- **What I share** ([SPEC-11 §5](SPEC-11-data-trust.md#5-pannello-cosa-condivido-m76)), con `ShareModel.Add` e `def.feature = "econ"`:
  - **Craft orders** / *Ordini di crafting* (`orders`): a chi *the whole guild*; il contenuto: i propri ordini e le proprie parti di artigiano, con stato, prezzo e nota; nessun interruttore (gli ordini si fanno con un clic);
  - **Wishlist** / *Lista dei desideri* (`wish`): *the whole guild*; le voci con quantità e scadenza;
  - **Buy and sell posts** / *Annunci compro/vendo* (`board`): *the whole guild*; gli annunci e le risposte;
  - **Bags, bank and mail counts** / *Conteggi di borse, banca e posta*: *only on this computer*; la nota dice: "Your alts' counts stay on this computer. Ask the guild and Ask the bank send only the missing materials.";
  - **Shopping list** / *Lista della spesa*: *only on this computer*;
  - per gli ufficiali, **Guild goals** / *Obiettivi di gilda* (`goals`): *the whole guild*.
- **Aspetto**: tutto secondo [ui-style §9](ui-style.md#9-le-regole-di-material-3-adr-0027) (Material 3, [ADR 0027](../adr/0027-material-3-rules-adapted-to-accord.md)). Le modalità della vista *Market* sono una fila di chip; i filtri sono chip; ogni tabella è una `Widgets.DataTable` con la riga scelta in `secondary-container`; al più **un pulsante pieno** per vista o dialog (*Place order*, *Post*, *New goal*); i pulsanti ripetuti sulle righe sono tonali (32 punti); le barre *posseduti/necessari* e degli obiettivi sono `Widgets.ThinBar`; lo stato di un ordine ha il suo token (`accent-text` *requested*, `text-2` *accepted* e *in progress*, `ok` *ready* e *delivered*, `text-3` *cancelled*), quello di un annuncio pure (`accent-text` aperto, `ok` concluso, `text-3` ritirato o scaduto); le etichette *WTS* e *WTB* sono badge informativi (16 % della tinta, non `err`); le conferme (*Confirm*, *Ask the guild*) sono dialog. `Tests/test_ui_m3.lua` apre le pagine nuove.
- **`/accord debug`**: per `orders`, `wish`, `board` e `goals` il numero di record e i rifiuti per motivo; per l'inventario quante parti e personaggi sono letti, se la posta è parziale; per i materiali quante ricette sono in cache e quante il gioco non ha dato, e i nomi dei campi dello schema visti (come i campi di `GetRecipeInfo`, SPEC-06 §1.5); per Auctionator il livello e le funzioni trovate. Mai nomi, GUID, oggetti o testi (SPEC-09 §6).
- **Demo** (M7.4, `Data/Demo.lua`, solo con `econ` acceso): M13.2 cinque ordini in stati diversi (uno con la consegna confermata da una parte sola); M13.3 tre liste dei desideri; M13.4 una lista della spesa di tre ricette con un intermedio, un inventario inventato di due personaggi e una banca di gilda, senza prezzi (Auctionator non c'è nella demo); M13.5 sei annunci e un affare a metà; M13.6 due obiettivi, uno raggiunto. Nella demo nulla si manda e l'inventario vero non si tocca.
- **Backup** (M7.5): nessuna parte di M13; ordini, desideri, annunci e obiettivi tornano dalla sincronizzazione (li tengono gli altri client).

## 12. Test per passo

| Passo | File | Casi |
|---|---|---|
| M13.2 | `Tests/test_orders.lua` | solo il compratore scrive l'ordine e solo l'artigiano la sua parte, anche contro un client falsificato e un ufficiale (ORD-01); contenuto bloccato e passaggi solo in avanti (`locked`); la parte che arriva prima dell'ordine aspetta (`wait`); gli stati ricavati, uguali su ogni client; *delivered* solo con le due conferme, una sola resta *ready* (criterio); scadenza di un *requested* e di un ordine con `by`; chi esce dalla gilda; i promemoria di M3 offerti come ordini, mai pubblicati da soli, una volta (criterio); limiti e ritmo; righe del Centro azioni e avvisi una volta; nessuna funzione che sposta oggetti o oro chiamata (ECO-01); traffico (§10.3); interruttore spento |
| M13.3 | `Tests/test_demand.lua`, `Tests/test_wishlist.lua` | la domanda somma ordini aperti e obiettivi e cambia quando un ordine si chiude (criterio); materiali sconosciuti contati a parte; una voce dei desideri scade da sola (criterio); forma, proprietario, ritmo; *I have some* non manda nulla; traffico; interruttore spento |
| M13.4 | `Tests/test_inventory.lua`, `Tests/test_reagents.lua`, `Tests/test_shopping.lua` | posseduti giusti per le borse, la banca e un alt (criterio), con la posta e senza, con un alt di un altro reame che non conta; banca di gilda solo nella sua colonna; posta parziale e in contrassegno; lettura dopo `BAG_UPDATE_DELAYED`; materiali dal gioco finto con i campi del client moderno e con campi mancanti; cache e build nuova; la scomposizione cambia i totali (criterio), solo la parte mancante, 4 livelli, nessun giro; *Ask the guild* scrive solo i mancanti; *Ask the bank* compila solo ciò che manca e la banca mostra (criterio); prezzi con un Auctionator finto, senza, e con un'API che dà errore; inventario mai in un record o in un messaggio; interruttore spento |
| M13.5 | `Tests/test_board.lua` | un affare confermato da una parte sola resta aperto (criterio); concluso con le due conferme e non si riapre; ritiro prima della seconda conferma; gli annunci scadono da soli (criterio); contenuto bloccato; non ci si risponde da soli; nascondere un autore; traffico; interruttore spento |
| M13.6 | `Tests/test_goals.lua` | l'avanzamento è la somma dei depositi dei registri nell'intervallo (criterio), uguale per due client con gli stessi registri; prelievi non sottratti; chiuso quando raggiunto o alla fine (criterio); un membro che vede meno schede; solo ufficiali scrivono (`authority`); al massimo 5 aperti; l'avviso una volta; interruttore spento |

## 13. Cosa resta da verificare nel client

Nella prova di M13.8 (`docs/checklists/M13.md`):

- il criterio di uscita: un membro ordina un crafting, l'artigiano lo accetta e tutti e due lo segnano consegnato; un obiettivo di gilda mostra l'avanzamento dai registri della banca;
- `C_TradeSkillUI.GetRecipeSchematic` su Forever: se risponde, con quali campi (`reagentSlotSchematics`, `quantityRequired`, `reagentType`, `outputItemID`, `quantityMin`), per le ricette non imparate, con la finestra della professione chiusa, e per una professione che il personaggio non ha (SPEC-10 R21, Q45);
- le borse e la banca: gli indici delle borse della banca su Forever (`Characterbanktab`, le borse 6–12 o `CharacterBankTab_1`…), la banca dell'account (`Accountbanktab`) se esiste, e che `PLAYER_LOGOUT` lasci il tempo di salvare le borse;
- la posta: la firma di `GetInboxItem` globale, il contrassegno in `GetInboxHeaderInfo`, il limite dei messaggi mostrati e `MAIL_INBOX_UPDATE` dopo che si toglie un oggetto (SPEC-10 R22);
- Auctionator su Forever: se c'è, con quale cartella e versione, e se `Auctionator.API.v1` ha `GetAuctionPriceByItemID`, `GetAuctionAgeByItemID` e `RegisterForDBUpdate` (R24);
- la doppia conferma di un affare e di un ordine tra due computer, con un `/reload` in mezzo;
- i registri della banca per un obiettivo: un deposito fatto da un membro compare nell'avanzamento dopo la visita di chi ha Accord, e le ore arrotondate ai bordi dell'intervallo (R23);
- che nessuna finestra del gioco (commercio, posta, asta, ordini di crafting del gioco) si apra o cambi per M13;
- l'aspetto della vista *Market*, della pagina *Shopping list* e delle loro finestre nei tre temi.

Il sistema degli ordini di crafting del gioco (`C_CraftingOrders`, nel dump) **non si usa**: piazzare un ordine lì muove oro e materiali (ECO-01), e non si sa se su Forever è attivo (`ShouldShowCraftingOrderTab`); gli ordini di Accord sono solo della gilda.
