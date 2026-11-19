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
