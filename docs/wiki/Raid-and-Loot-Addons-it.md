# Addon di raid e di loot

*English: [[Raid and loot addons|Raid-and-Loot-Addons]]*

> Il riconoscimento è nel codice dal passo M10.2; la lettura di Finland Dragon Credit Points arriva con il passo M11.7. Niente è ancora stato provato nel gioco vero: le prime prove sono con la gilda del proprietario.

Accord **non ha un motore del loot né le presenze**. Quei dati li tengono gli addon di raid e di loot della tua gilda, e Accord lavora **con** loro, mai contro:

- **Una fonte per ogni dato.** Il roster della season (MS1, MS2, OS) con la formazione e la panchina appartiene a un solo addon per tutta la gilda, e così i dati del loot (i crediti e il posto in coda di un membro, le regole del loot). Gli **ufficiali** scelgono quella fonte una volta per la gilda, e l'Accord di ogni membro segue la stessa scelta. Finché non scelgono, il roster della season è quello di Accord e non c'è una fonte del loot.
- **Solo lettura.** Accord non scrive mai i dati di un altro addon, non legge mai i suoi file salvati e non lo carica, accende o spegne mai.

## Gli addon che Accord conosce

| Addon | Tipo | Cosa fa Accord |
|---|---|---|
| **Finland Dragon Credit Points** (FDCP) | loot e roster del raid | lo riconosce; lo legge dalla sua API pubblica (livello 1) |
| Gargul, RaidCore, WLC, Forever Loot Manager, NostalgiaForeverLC, RollForMe | loot | lo riconosce (livello 0) |

I nomi delle cartelle degli addon diversi da FDCP vengono dalle loro pagine pubbliche e si confermano nel gioco prima di fidarsene. Gli addon di gestione della gilda che non riguardano il loot o il roster del raid sono lasciati fuori di proposito.

## Livelli

- **Livello 0, riconoscimento.** Accord vede che l'addon è caricato sul tuo computer, e la sua versione.
- **Livello 1, lettura.** Accord legge ciò che l'addon pubblica per gli altri addon. Solo FDCP pubblica un'interfaccia del genere (`FinlandDragonCreditPointsAPI`), e Accord la legge solo quando la sua versione è una che Accord conosce (la versione 1). Con un'altra versione Accord torna al livello 0 e niente si rompe: aggiorna Accord.
- Non c'è un livello 2: Accord non manda mai niente a un altro addon.

`/accord debug` ha una sezione **Integrations** con ciò che è stato trovato sul tuo computer (senza nomi). Quali addon hanno gli *altri* membri arriva più avanti, con l'elenco degli addon della gilda (M9).
