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
| Solo gli ufficiali | La storia del roster osservata dagli ufficiali (ingressi, uscite, cambi di grado e di livello, note pubbliche), tenuta per sempre: solo sul canale degli ufficiali, e solo sul computer dell'ufficiale che osserva finché quel canale non è provato (vedi *Roster di gilda*) |
| Solo gli ufficiali | Le assenze dichiarate: una data di rientro, senza motivo. L'addon di un membro manda la propria in whisper agli ufficiali in linea; gli ufficiali impostano le altre e se le passano. Le fasce di inattività scelte dagli ufficiali viaggiano allo stesso modo. L'inattività di ogni giocatore è calcolata dall'addon di ogni ufficiale e non si salva mai |
| Solo gli ufficiali | Le note degli ufficiali: una nota più lunga su un personaggio scritta dagli ufficiali, tenuta per sempre (anche dopo che il giocatore esce dalla gilda). Solo sul canale degli ufficiali, e solo sul computer dell'ufficiale che la scrive finché quel canale non è provato; mai esportate, mai nel tuo backup; cancellate quando l'ufficiale viene retrocesso |
| Solo ufficiali | La coda della revisione guidata e gli account segnati come rivisti: restano solo sul computer di quell'ufficiale, non vengono mai inviati e si cancellano se l'ufficiale è retrocesso |

L'elenco dei personaggi, il BattleTag e il nome Discord sono **sempre condivisi** con la tua gilda: è così che gli alt vengono raggruppati e i contatti mostrati senza chiedere. Non c'è un interruttore per spegnerlo. I contatti ricevuti da altri giocatori vengono controllati (un BattleTag deve avere la forma di un BattleTag, un nome Discord deve essere un semplice nome utente) e mostrati come testo semplice, mai come link.

L'elenco dei personaggi contiene, per ognuno dei tuoi personaggi nel reame (dentro la gilda o no): nome, classe, livello, se è in gilda e quale è il tuo main. Per un personaggio fuori dalla gilda contiene anche il **nome della sua gilda** (o che non ne ha) e il **giorno** dell'ultimo accesso con l'addon, così la tua gilda vede dove sono i tuoi alt; l'ora non si condivide. Un personaggio che cancelli o rinomini viene ripulito da solo dopo 30 giorni, quando il gioco conferma che non lo conosce più. **Impostazioni → Cancella i dati della gilda** dimentica in qualunque momento ciò che l'addon conserva su una gilda nel tuo computer ([[Impostazioni|Settings-it]]).

I minuti passati in gruppo con compagni di gilda sono registrati dalla versione del roster in poi (vedi *Like e indice sociale*), per giorno e per coppia di personaggi, e conservati 90 giorni.

## Nessuno può scrivere i tuoi dati

Ogni dato condiviso indica il personaggio che l'ha scritto, e il gioco stesso dice a ogni addon chi ha mandato un messaggio. L'addon di un compagno accetta i tuoi personaggi, contatti e ricette solo da te (o da un tuo personaggio) e passa i dati di un altro membro solo quando vengono da un ufficiale. I like e le decisioni sulla banca si accettano solo dagli ufficiali. Un addon modificato può quindi mentire solo su se stesso.

Un addon rotto o modificato non può nemmeno bloccare il tuo: un messaggio troppo grande, danneggiato o della forma sbagliata si scarta, e l'addon di un compagno che manda troppo, o che continua a mandare dati che non può mandare, viene ignorato per 10 minuti. Intanto i tuoi messaggi continuano a partire, e dopo i dati della gilda si riparano da soli. `/accord debug` dice quanti addon sono ignorati in quel momento, mai quali.

## Gruppi

> Dalla `v0.9.0`.

Un [[gruppo|Groups-it]] che pubblichi (tipo, attività, livelli, posti, ruoli cercati, la tua nota e il ritrovo, mai una posizione) va solo alla tua gilda, e il computer di ogni membro lo elimina 10 minuti dopo la fine. Una **candidatura** (il tuo ruolo, il livello e un commento facoltativo) va in sussurro solo al capo di quel gruppo, e così la risposta: nessun altro lo sa. Restano sui due computer finché il gruppo non si chiude, e non entrano nei backup né nelle esportazioni. I filtri salvati restano sul tuo computer.

## L'elenco dei tuoi addon

> Dalla `v0.9.0`.

Accord condivide con la tua gilda l'**elenco degli addon che questo personaggio ha caricati** (nome della cartella, versione e titolo; mai gli addon di Blizzard, le loro impostazioni o dei file), perché la scheda [[Addon della gilda|Guild-Addons-it]] li possa contare. Conteggi e versioni li vedono tutti; **chi** usa un addon Accord lo mostra solo agli ufficiali e al Guild Master, e a te la tua voce. È una regola dell'interfaccia: gli elenchi arrivano a tutta la gilda. Un elenco si tiene 60 giorni. **Condividi l'elenco dei miei addon** è acceso di default; spegnilo (in *Cosa condivido* o nella carta dei Contatti delle Impostazioni) e i tuoi elenchi si ritirano e non se ne mandano di nuovi.

## Roster della season

> Arriva con la `v0.10.0`.

Quando dichiari per una season di raid (MS1, MS2, OS, una nota, oppure *Non ancora sicuro*), la dichiarazione arriva a tutta la gilda ed è elencata in *Cosa condivido*. Solo il tuo account può scriverla. Si tengono la season corrente e le 3 precedenti; quelle più vecchie si cancellano. Vedi [[Roster della season|Season-Roster-it]].

## Eventi

> Arriva con la `v0.10.0`.

Quando ti iscrivi a un evento della gilda da Accord, la tua risposta va nel **calendario del gioco**, come se avessi risposto nel gioco. Il **ruolo** che scegli per l'evento, che il calendario del gioco non può tenere, arriva a tutta la gilda ed è elencato in *Cosa condivido*; così le tue risposte agli eventi tenuti solo in Accord (quando un client non ha il calendario del gioco). Solo il tuo account può scriverli, e si cancellano 2 giorni dopo l'evento. Accord non registra presenze. Vedi [[Eventi|Events-it]].

Quando un ufficiale importa da Discord un evento di **Raid-Helper**, la gilda ne riceve il titolo, la data e **solo i membri abbinati** (personaggio, stato, ruolo, classe e specializzazione), fino a 2 giorni dopo l'evento. I nomi che non corrispondono a nessuno e gli abbinamenti a mano dell'ufficiale restano sul suo computer e non vengono mai mandati; i nomi non abbinati si cancellano 2 giorni dopo l'evento. Accord non contatta mai Discord né Raid-Helper. Vedi [[Eventi di Raid-Helper|Raid-Helper-it]].

La **composizione** di un raid scritta da un ufficiale (chi è nel raid, chi in panchina, chi gioca la MS2) arriva alla gilda fino a 2 giorni dopo l'evento. È un piano, non un registro di chi c'era. Vedi [[Eventi|Events-it]].

## Quando giochi di solito

> Arriva con la `v0.10.0`.

Accord conta, sul tuo computer, i minuti in cui il tuo account è online per ora della settimana nelle ultime 8 settimane, e nient'altro: nessun luogo, nessuna attività, nessun raid e nessuna presenza. La gilda riceve, per ogni ora, uno di quattro livelli e il numero di settimane misurate, tenuti 30 giorni. Tutti vedono quanti membri sono online in ogni ora; **chi** sono Accord lo mostra solo agli ufficiali e al Guild Master, e a te la tua voce (è una regola dell'interfaccia: le mappe arrivano a tutta la gilda). **Condividi quando gioco di solito** è acceso di default; spento, la tua mappa si ritira e non si manda più niente, mentre la tua continua a contare sul tuo computer. Vedi [[Disponibilità|Availability-it]].

## Altri addon

A parte quell'elenco (novità della `v0.9.0`), l'addon rilasciato non cerca altri addon e non legge niente da loro. Un rilascio successivo (milestone M10 e M11) cercherà gli addon di raid e di loot che conosce **solo sul tuo computer** e condividerà con la gilda solo la scelta degli ufficiali di quale è la fonte: vedi *[[Addon di raid e di loot|Raid-and-Loot-Addons-it]]*.

## Cosa resta sul tuo computer

L'addon tiene i suoi dati nei file di variabili salvate del gioco (`AzerothAccord.lua` nella tua cartella WTF): un **codice account** (casuale, creato una volta, usato perché i compagni capiscano che i tuoi personaggi stanno insieme e perché un ufficiale possa registrare i tuoi like in modo anonimo), l'elenco dei giocatori a cui **hai** dato un like e i like ancora in attesa (solo sul tuo computer, mai condivisi), i tuoi personaggi, dalla `v0.9.0` i promemoria del [[Centro azioni|Action-Center-it]] per le richieste di creazione che hai scritto (il membro, la ricetta e l'ora; mai inviati, mai nel backup), e una sezione separata per **ogni gilda** in cui sei stato, così i dati di due gilde non si mescolano mai. Se lasci una gilda, la sua sezione resta intatta finché non ci torni. `/accord debug` mostra quanto spazio occupano i dati, mai i dati stessi.
