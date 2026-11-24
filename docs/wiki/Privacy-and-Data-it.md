# Privacy e dati

*English: [[Privacy and Data|Privacy-and-Data]]*

L'addon non ha un server, non invia nulla fuori dal gioco e non raccoglie telemetria. Tutto viaggia solo verso **la tua gilda**, sui canali nascosti degli addon della gilda.

| Chi lo vede | Cosa |
|---|---|
| La tua gilda | I nomi nel registro della banca con ciò che hanno depositato o prelevato (come lo mostra il gioco) e l'elenco delle donazioni costruito da lì; l'elenco dei tuoi personaggi nel reame e il tuo main, il tuo BattleTag, il tuo nome Discord, le tue ricette, i minuti passati in gruppo con compagni di gilda, il contenuto della banca che hai visto, le tue richieste alla banca |
| La tua gilda, solo come totali | I like che ricevi |
| Tu, gli ufficiali e il Maestro di gilda | Il tuo indice sociale e i compagni con cui hai giocato di più (calcolati da ogni addon dai minuti condivisi) |
| L'ufficiale che registra il tuo like | Che il like viene da te, nel momento in cui è consegnato; poi è conservato sotto un codice che i membri non possono leggere |
| Solo gli ufficiali | Le schede della banca lette da un ufficiale (condivise solo sul canale degli ufficiali, mai nell'addon dei membri) e il codice segreto della gilda che trasforma chi vota nel codice anonimo dei like (tenuto solo dagli addon degli ufficiali, rimosso quando un ufficiale viene retrocesso) |

L'elenco dei personaggi, il BattleTag e il nome Discord sono **sempre condivisi** con la tua gilda: è così che gli alt vengono raggruppati e i contatti mostrati senza chiedere. Non c'è un interruttore per spegnerlo. I contatti ricevuti da altri giocatori vengono controllati (un BattleTag deve avere la forma di un BattleTag, un nome Discord deve essere un semplice nome utente) e mostrati come testo semplice, mai come link.

L'elenco dei personaggi contiene, per ognuno dei tuoi personaggi nel reame (dentro la gilda o no): nome, classe, livello, se è in gilda e quale è il tuo main. Per un personaggio fuori dalla gilda contiene anche il **nome della sua gilda** (o che non ne ha) e il **giorno** dell'ultimo accesso con l'addon, così la tua gilda vede dove sono i tuoi alt; l'ora non si condivide. Un personaggio che cancelli o rinomini viene ripulito da solo dopo 30 giorni, quando il gioco conferma che non lo conosce più. **Impostazioni → Cancella i dati della gilda** dimentica in qualunque momento ciò che l'addon conserva su una gilda nel tuo computer ([[Impostazioni|Settings-it]]).

I minuti passati in gruppo con compagni di gilda sono registrati dalla versione del roster in poi (vedi *Like e indice sociale*), per giorno e per coppia di personaggi, e conservati 90 giorni.

## Nessuno può scrivere i tuoi dati

Ogni dato condiviso indica il personaggio che l'ha scritto, e il gioco stesso dice a ogni addon chi ha mandato un messaggio. L'addon di un compagno accetta i tuoi personaggi, contatti e ricette solo da te (o da un tuo personaggio) e passa i dati di un altro membro solo quando vengono da un ufficiale. I like, le decisioni sulla banca e la scelta della gilda dei suoi addon di raid e di loot si accettano solo dagli ufficiali. Un addon modificato può quindi mentire solo su se stesso.

Un addon rotto o modificato non può nemmeno bloccare il tuo: un messaggio troppo grande, danneggiato o della forma sbagliata si scarta, e l'addon di un compagno che manda troppo, o che continua a mandare dati che non può mandare, viene ignorato per 10 minuti. Intanto i tuoi messaggi continuano a partire, e dopo i dati della gilda si riparano da soli. `/accord debug` dice quanti addon sono ignorati in quel momento, mai quali.

## Altri addon

Accord cerca gli addon di raid e di loot che conosce (Finland Dragon Credit Points e gli addon di loot che funzionano su WoW Forever) **solo sul tuo computer**: se ognuno è caricato e la sua versione. Non invia mai quell'elenco, non cambia, non carica e non accende mai un altro addon, e non legge mai i dati salvati di un altro addon. L'unica cosa condivisa con la gilda è la **scelta degli ufficiali** di quale addon è la fonte del roster della season e dei dati del loot (una scelta per tutta la gilda, scritta solo dagli ufficiali). Vedi *[[Addon di raid e di loot|Raid-and-Loot-Addons-it]]*.

## Cosa resta sul tuo computer

L'addon tiene i suoi dati nei file di variabili salvate del gioco (`AzerothAccord.lua` nella tua cartella WTF): un **codice account** (casuale, creato una volta, usato perché i compagni capiscano che i tuoi personaggi stanno insieme e perché un ufficiale possa registrare i tuoi like in modo anonimo), l'elenco dei giocatori a cui **hai** dato un like e i like ancora in attesa (solo sul tuo computer, mai condivisi), i tuoi personaggi, e una sezione separata per **ogni gilda** in cui sei stato, così i dati di due gilde non si mescolano mai. Se lasci una gilda, la sua sezione resta intatta finché non ci torni. `/accord debug` mostra quanto spazio occupano i dati, mai i dati stessi.
