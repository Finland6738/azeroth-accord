# SPEC-08: Banca di gilda

[ADR 0009](../adr/0009-guild-bank-snapshots-and-officer-approved-requests.md).

## 1. Cosa offre il gioco

| API | Quando funziona |
|---|---|
| `GetNumGuildBankTabs`, `GetGuildBankTabInfo(tab)` | con la banca aperta **[verificare]** S9 |
| `QueryGuildBankTab(tab)`, `GetGuildBankItemInfo(tab, slot)`, `GetGuildBankItemLink(tab, slot)` | con la banca aperta, solo le schede visibili al grado |
| `GetGuildBankMoney`, `GetGuildBankWithdrawMoney` | con la banca aperta |
| `QueryGuildBankLog(tab)`, `GetNumGuildBankTransactions`, `GetGuildBankTransaction` | registro degli oggetti, storia limitata |
| `GetNumGuildBankMoneyTransactions`, `GetGuildBankMoneyTransaction` | registro del denaro |
| Eventi `GUILDBANKFRAME_OPENED`, `GUILDBANKBAGSLOTS_CHANGED`, `GUILDBANKLOG_UPDATE`, `GUILDBANK_UPDATE_MONEY`, `GUILDBANKFRAME_CLOSED` | |

Non esiste una lettura a distanza: la vista è fresca quanto l'ultima visita di un membro con l'addon.

## 2. Foto della banca

- BANK-01: a `GUILDBANKFRAME_OPENED` l'addon interroga, una alla volta e con una pausa, ogni scheda visibile, il denaro e i registri, e salva una foto per scheda con l'ora.
- BANK-02: la foto viaggia su `GUILD` se la scheda è visibile a tutti i gradi; su `OFFICER` se solo agli ufficiali; altrimenti non viaggia (domanda Q4).
- BANK-03: vince la foto più recente per scheda; ogni scheda mostra "seen <tempo> ago by <nome>".
- BANK-04: vista **Bank**: schede come nel gioco (griglia 14×7) e vista elenco con ricerca, raggruppamento per oggetto e quantità totale; tooltip dell'oggetto.

## 3. Registri e donazioni

- BANK-10: le voci di registro si uniscono nel tempo, senza doppioni (chiave: tipo, nome, oggetto, quantità o importo, ora arrotondata), così lo storico supera quello del gioco.
- BANK-11: **donazioni**: depositi di denaro e di oggetti per membro (account) su 30 giorni, 365 giorni e da sempre; classifica visibile a tutti (domanda Q5).
- BANK-12: denaro della gilda nel tempo (grafico semplice dalle foto).

## 4. Richieste

- BANK-20: un membro crea una richiesta: **Withdraw** (oggetto dalla banca o denaro, quantità, motivo), **Deposit** (oggetto che offre), **Donation** (promessa di denaro o oggetti).
- BANK-21: le richieste aperte sono visibili a tutta la gilda; l'autore può annullarle.
- BANK-22: solo gli ufficiali le portano a **approved**, **rejected** (con motivo) e **fulfilled**; gli altri client accettano questi passaggi solo da ufficiali.
- BANK-23: notifica agli ufficiali online (icona sulla tab con il numero di richieste aperte) e al richiedente quando cambia lo stato.
- BANK-24: la consegna resta manuale (posta, scambio o prelievo dell'ufficiale); quando una foto o un registro mostra il movimento corrispondente l'addon propone "mark as fulfilled".

## 5. Cattura (`Data/Bank.lua`, M5.1)

- Alla `GUILDBANKFRAME_OPENED` la cattura legge il numero di schede (se la banca non lo dice ancora riprova fino a 3 volte, ogni 1,5 s), poi **una interrogazione alla volta** con una pausa di 1 s (`QueryGuildBankTab`), aspettando `GUILDBANKBAGSLOTS_CHANGED` (al massimo 4 s). Solo le schede **visibili al grado** (`isViewable` di `GetGuildBankTabInfo`) si leggono; poi il denaro (`GetGuildBankMoney`). I permessi del grado (visibile, deposito, prelievi) restano in memoria per la vista. Chiudere la banca a metà ferma la cattura; senza eventi né oggetti una scheda non si pubblica (una banca lenta non cancella una foto buona); una scheda vuota si pubblica solo dopo che almeno un evento ha mostrato che la banca consegna dati.
- **Una foto per autore e scheda**: id `<GUID>:t<scheda>`, campi `kind = "tab"`, `tab`, `name`, `icon`, `rank` (indice di grado di chi l'ha letta), `restricted` (solo se chi legge è ufficiale), `it` (oggetti come testo `slot.itemID.quantità[.variante]` separati da virgole, le varianti sono incanto, gemme e suffisso con `_`), `n`, `h` (impronta). Il denaro è `<GUID>:money`. In vista vince la più recente per scheda (BANK-03, M5.3). Una foto invariata si ripubblica solo dopo 30 minuti (l'età resta vera senza un messaggio a ogni visita); una cambiata subito.
- **Permessi (domanda Q4, proposta)**: il gioco non dice a un client quali gradi vedono una scheda, solo se il proprio la vede. Perciò una foto porta il `rank` di chi l'ha letta e si mostra ai membri di quel grado o superiori; la foto di un **ufficiale** è `restricted` (solo ufficiali, solo su `OFFICER`). Conseguenza: una scheda aperta a tutti arriva ai membri solo se l'ha letta un membro.
- Capacità `bankTabs` (`Compat`): `unknown` finché la banca non si è aperta, `available` dopo la prima scheda letta. **Non verificato nel client reale** (S9): se `GetGuildBankTabInfo` dà il nome delle schede non visibili, il formato dei campi, il tempo tra la richiesta e l'evento, e se la banca limita le interrogazioni ravvicinate.

## 6. Sincronizzazione e permessi (M5.2)

- Le foto viaggiano come ogni record: su `GUILD` dopo 5 s dall'autore, per riepilogo `HELLO` e invio in whisper da un ufficiale se l'autore non c'è ([SPEC-02 §4](SPEC-02-network-protocol.md#4-sincronizzazione)). Le foto di un ufficiale (`restricted`) vanno solo su `OFFICER` e tra ufficiali con `OHELLO`; i client dei membri le rifiutano. Un client falsificato non può scrivere la foto di un altro (l'id comincia con l'autore) né una foto riservata a nome di un ufficiale (mittente e autore devono essere ufficiali).
- `Bank:Tabs()` dà, per ogni scheda, la foto più recente **che questo grado può vedere** (BANK-03): la propria; una riservata solo se si è ufficiali; altrimenti solo se il proprio grado è quello di chi l'ha letta o superiore (indice minore o uguale). Una foto senza `rank` è per gli ufficiali. Ogni scheda dice chi l'ha letta e quando. Il denaro (`Bank:Money()`) è visibile a tutti.
- Limite noto: una scheda aperta a tutti ma letta da un ufficiale resta agli ufficiali finché non la legge un membro (l'addon non sa quali gradi la vedono, domanda Q4).

## 7. Vista Bank (`UI/Bank.lua`, M5.3)

- Modalità con un pulsante ciascuna (le prossime tappe ne aggiungono con `View.AddMode`): **Tabs** e **Items**. `/accord bank` apre la vista.
- **Tabs**: un pulsante per scheda (solo quelle che il grado può vedere, §6), il denaro della gilda con la sua età, l'età della scheda e chi l'ha letta ("seen 2 h ago by Bob", BANK-03) e la scheda come nel gioco: 14 colonne da 7 caselle (la casella *n* sta nella colonna ⌈*n*/7⌉), con icona, quantità e il tooltip dell'oggetto al passaggio del mouse (l'oggetto è `item:<id>` più incanto, gemme e suffisso della variante).
- **Items**: una riga per oggetto su tutte le schede visibili, con il totale e le schede in cui sta ("Consumables x20, Cloth x40"); la casella di ricerca del pannello filtra per nome, numero dell'oggetto o nome della scheda (una ricerca scritta in *Tabs* porta all'elenco). Il nome di un oggetto che il client non ha ancora caricato si chiede una volta (`C_Item.RequestLoadItemDataByID`) e la riga si completa a `GET_ITEM_INFO_RECEIVED`; finché manca la riga dice "item N (loading...)" ed è in fondo.
- Senza dati la vista dice che il gioco mostra la banca solo alla cassaforte e che le schede che il grado non vede restano nascoste (Q4).
- `Compat.Item` (nuovo): `Info`, `Icon`, `Request` su `C_Item`, con `GetItemInfo` come ripiego. Non verificato nel gioco: che `C_Item.GetItemInfo` dia il nome dopo la richiesta e che l'icona sia nota subito.

## 8. Registri, donazioni e denaro (`Data/BankLog.lua`, `UI/BankLog.lua`, M5.4)

- **Cattura**: dopo le schede e il denaro la cattura interroga, sempre una alla volta con la pausa, il registro oggetti di ogni scheda visibile (`QueryGuildBankLog(scheda)`) e il registro del denaro (numero di scheda = `MAX_GUILDBANK_TABS + 1`, 7 se la costante manca **[verificare]** S9), aspettando `GUILDBANKLOG_UPDATE` (al massimo 4 s). Capacità `bankLogs`: `available` dopo il primo registro letto.
- **Record** `<GUID>:log:<scheda>` (scheda 0 = denaro): `kind = "log"`, `tab`, `rank` e `restricted` come per le foto (solo schede oggetti), `e` = voci come testo `tipo,nome,oggetto,quantità,ora` separate da `;` (per il denaro `oggetto` è 0 e la quantità è in rame), `n`, `h`. Una cattura si **unisce** al record già tenuto, non lo sostituisce: al massimo 150 voci, le più recenti, nessuna più vecchia di un anno; il registro cresce oltre quello del gioco (BANK-10). Un registro vuoto non si pubblica.
- **Ora e doppioni (BANK-10)**: il gioco dà "anni, mesi, giorni, ore fa" **[verificare]** S9; l'ora della voce è l'ora della cattura meno quell'età, arrotondata per difetto a un blocco grosso quanto l'età (un'ora fino a 2 giorni, un giorno fino a 2 mesi, una settimana oltre). Due voci sono lo **stesso evento** se tipo, nome, oggetto e quantità coincidono e le ore distano al massimo un blocco (le ore del gioco slittano da una cattura all'altra); l'unione tiene l'ora più vecchia e conta una voce tante volte quante la lista che la vede più volte (il massimo, mai la somma): lo stesso evento letto da due compagni, o in due visite, è uno; due eventi uguali nella stessa cattura sono due. L'unione è deterministica (ordine dei record per id).
- **Chi vede cosa**: le voci di una scheda seguono la regola di grado delle foto di quella scheda; il registro del denaro e la classifica sono visibili a tutti i membri (Q5, proposta: un solo interruttore `BankLog.DONATIONS_VISIBLE_TO = "everyone" | "officers"`).
- **Donazioni (BANK-11)**: solo le voci `deposit`; denaro e oggetti per **account** (i personaggi di un giocatore insieme, `Accounts:AccountKey`; il main se è in gilda; chi non è più in gilda per nome), su 30 giorni, 365 giorni e da sempre; ordine per oro o per oggetti, parità a pari posto. Prelievi e riparazioni non contano.
- **Denaro nel tempo (BANK-12)**: ogni record `money` che arriva (di qualunque autore) aggiunge un punto `{ora, rame}` alla storia locale `GuildKey:Data().bank.history` se l'importo cambia o sono passate 6 ore (500 punti al massimo); il grafico dà il valore noto alla fine di ciascuna fascia di 30 o 90 giorni.
- **Vista**: modalità **Log**, **Donations** e **Money** nella vista Bank.

## 9. Richieste (`Data/BankRequests.lua`, `UI/BankRequests.lua`, M5.5)

- **Creare** (BANK-20): modulo nella modalità **Requests**: tipo (Withdraw, Deposit, Donation), oggetto (un link incollato o il numero; vuoto per l'oro), quanti (o quanto oro, in monete intere) e motivo. Controlli: tipo valido, un deposito vuole un oggetto, quantità 1-9999, importo intero, al massimo 5 richieste aperte per personaggio, motivo pulito (senza `|` né caratteri di controllo) e al massimo 120 caratteri.
- **Vedere e annullare** (BANK-21): tutta la gilda vede tutte le richieste (per impostazione le aperte e le approvate; "Show closed ones too" mostra le altre; "Only mine"); l'autore, o un personaggio del suo account, annulla una richiesta **aperta** (pulsante Cancel).
- **Decidere** (BANK-22): solo gli ufficiali, con i pulsanti Approve, Reject (il motivo scritto nel modulo diventa la nota del rifiuto) e Fulfilled, secondo i passaggi ammessi di [SPEC-03 §7](SPEC-03-data-model.md#7-richieste-in-banca-bankreq). La decisione è una nuova revisione dello stesso id scritta dall'ufficiale; su ogni altro client si accetta solo se mittente e autore sono ufficiali (NET-12). Un client non ufficiale non può decidere né annullare richieste altrui (regola del proprietario: l'annullamento viene dall'account del richiedente). Il tooltip di una riga mostra la storia.
- **Convergenza**: vince lo stato più alto, quindi un annullamento scritto nello stesso momento di un'approvazione non divide la gilda (provato nel simulatore).
- La consegna resta manuale (BANK-24); il contatore sulla tab, la casella degli ufficiali, le notifiche e la proposta "mark as fulfilled" sono di M5.6.
