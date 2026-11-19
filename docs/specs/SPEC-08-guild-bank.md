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
