# Centro azioni

*English: [[Action Center|Action-Center]]*

> **Novità della `v0.9.0`**. Nulla di questa pagina è stato verificato nel gioco vero.

Il **Centro azioni** è un solo elenco delle cose che **ti aspettano**: non serve guardare ogni vista per trovarle. Si apre con la sua scheda, la prima del pannello Accord, o con `/accord inbox`.

Non salva nulla di suo e non decide niente al posto tuo. Ogni riga viene letta dalla vista a cui appartiene: **fai clic** per aprire quella vista e agire lì. Quando la cosa è fatta, la riga sparisce.

## Che cosa compare

| Riga | Chi la vede | Il clic apre | Sparisce quando |
|---|---|---|---|
| *Richiesta in banca: …* e *Da consegnare: …* | ufficiali e Guild Master | la casella **In arrivo** della [[Banca di gilda|Guild-Bank-it]], su quella richiesta | la richiesta è decisa, consegnata, annullata o scade |
| *In attesa di un ufficiale: …* e *Approvata: …* | tu, per le tue richieste | le tue richieste nella vista Banca | la richiesta è chiusa |
| *Hai chiesto a … di creare …* | tu, dopo **Chiedi di crearlo** | l'elenco delle ricette di quel membro | premi **Fatto**, o dopo 7 giorni |
| *3 promozioni da fare nel gioco* (anche retrocessioni, rimozioni e note) | ufficiali e Guild Master | la pagina **Coda** della [[scheda Ufficiali|Guild-Roster-it]] | in coda non resta nulla di quel tipo |
| *Rientro di … (assente fino al …)* | ufficiali e Guild Master, dal giorno del rientro ai tre giorni dopo | la pagina **Inattivi** | tre giorni dopo il rientro |
| *La tua assenza finisce il …* | tu, nei tre giorni prima della fine | la card **Assenza** delle [[Impostazioni|Settings-it]] | dopo il rientro |
| *… vuole unirsi come …* | tu, come capo di un [[gruppo|Groups-it]] | la pagina **Il mio gruppo** di Gruppi | accetti o rifiuti, o il gruppo si chiude |
| *Raduno PvP: …* e *Raduno nel mondo: …* *(dalla `v0.10.0`)* | tutti, finché il [[raduno|Events-it]] è aperto | la pagina **Raduni** di Eventi | il raduno finisce o viene chiuso |
| *La prova di … è finita il …: decidi* e *… è uscito dalla gilda durante la prova* *(nascosto finché M12 non è completo)* | gli ufficiali e il Guild Master, dal giorno della fine | la pagina **Prove** della [[scheda Ufficiali|Guild-Roster-it]], su quella prova | un ufficiale chiude o proroga la prova |
| *Lista di benvenuto: 2 di 4 fatte* *(nascosto finché M12 non è completo)* | tu, da nuovo membro | la [lista di benvenuto](#lista-di-benvenuto), in cima alla stessa pagina | tutte le voci sono fatte, premi **Chiudi lista**, o 30 giorni dopo l'ingresso |

Un ufficiale che chiede qualcosa alla banca vede la richiesta due volte: da decidere, e come proprio promemoria.

Una richiesta di creazione è solo un sussurro che invii tu (vedi [[Professioni e ricette|Professions-and-Recipes-it]]): l'addon non avvisa l'artigiano. La riga è un **promemoria tuo**, tenuto sul tuo computer e mai inviato a nessuno, al massimo 20. Resta anche se decidi di non inviare il sussurro: premi **Fatto** per toglierlo. Gli ordini visibili all'artigiano arrivano con una milestone successiva (M13).

## Lista di benvenuto

> *Nascosta finché M12 non è completo.* Niente di tutto questo è stato verificato nel gioco vero.

Se sei appena entrato in gilda, in cima al Centro azioni compare la carta **Benvenuto** e una riga in chat te lo dice. Elenca fino a quattro cose da fare; ognuna **si spunta da sola** quando è fatta, e resta spuntata. Clicca una voce per andare dove si fa.

| Voce | È fatta quando | Non compare quando | Il clic apre |
|---|---|---|---|
| *Leggi le informazioni e le regole della gilda* | hai letto le due pagine del [[manuale|Guild-Handbook-it]] (o quella che c'è) | la gilda non ne ha scritta nessuna | la prima pagina non letta |
| *Scegli il tuo main* | hai scelto il main, o il tuo account ha un solo personaggio | | la carta del **personaggio principale** nelle [[Impostazioni|Settings-it]] |
| *Aggiungi il tuo nome Discord* | il tuo nome Discord è salvato (o lo dà il gioco) | | la carta **Contatti** delle Impostazioni |
| *Dichiarati per la season* | il tuo account è nel [[roster della season|Season-Roster-it]], anche come *Non so ancora* (con FDCP: un tuo personaggio è nel suo pool) | non c'è una season aperta, o la fonte è FDCP e non è caricato | la vista Season, o FDCP |

- **Chi la riceve**: un personaggio entrato **dopo** che Accord vedeva già la gilda. L'addon lo sa quando ha visto il tuo personaggio cambiare gilda, o quando il registro della gilda del gioco mostra il tuo ingresso negli ultimi 14 giorni (non è ancora verificato che il gioco offra quel registro agli addon). Chi era già in gilda quando la gilda ha cominciato a usare Accord non la riceve, e nemmeno un alt di un account già in gilda. La carta può comparire dopo qualche minuto, quando il tuo computer ha ricevuto i dati della gilda.
- **Chiudi lista** la chiude per sempre su quel personaggio. Sparisce anche da sola 30 giorni dopo l'ingresso, e dall'accesso successivo quando è tutto fatto.
- `/accord welcome` apre la lista in ogni momento, a chiunque.
- Resta **sul tuo computer**: non si manda nulla, e gli ufficiali non vedono che cosa hai spuntato.

## Ordine e colori

Ogni riga ha un pallino colorato per l'urgenza:

- **Adesso** (rosso): qualcuno ti aspetta ora, o la cosa scade entro un giorno, per esempio un candidato al tuo [[gruppo|Groups-it]];
- **Da fare** (colore del tema): tocca a te;
- **Promemoria** (grigio): aspetti gli altri, o è solo da ricordare.

Prima le più urgenti; a parità, ciò che aspetta da più tempo. Il numero sulla scheda conta le righe **Adesso** e **Da fare**, e il tooltip dell'addon nel Compartimento AddOn dice *Centro azioni: N da fare*.

I filtri in alto mostrano **Tutto** o un solo tipo: *Gruppi*, *Banca*, *Creazioni*, *Ufficiali e assenze* (e *Raduni*, dalla `v0.10.0`). Quando un tipo ha più di 50 righe, un'ultima riga dice *e altre N*; l'elenco ne tiene al massimo 200. Se non c'è nulla dice *Non c'è niente in attesa.*

## Avvisi

> **Novità della `v0.9.0`**. Nulla degli avvisi è stato verificato nel gioco vero; in particolare quali suoni offre il gioco.

La seconda pagina del Centro azioni, **Avvisi**, è la cronologia di ciò che l'addon ti ha detto, dal più recente. Il nome della pagina mostra quanti non ne hai **letti**: *Avvisi (3)*.

- Un avviso è letto quando ci fai **clic** (si apre anche la vista a cui si riferisce) o con **Segna tutti come letti**. Nessuno si segna letto da solo.
- I filtri mostrano **Tutto** o solo i **Non letti**. **Svuota** cancella la cronologia: clic, poi di nuovo clic entro 8 secondi.
- La cronologia tiene al massimo 200 avvisi e 30 giorni, sul tuo computer, una per gilda. Mostra gli avvisi di questo personaggio e quelli per tutto il tuo account.
- *muto* segna un avviso che hai spento: non è comparso in chat né sullo schermo, ma resta qui.

| Avviso | Chi lo riceve | Mostrato di predefinito |
|---|---|---|
| *Nuova richiesta alla banca di …* | ufficiali e Guild Master | una riga in chat |
| *La tua richiesta alla banca (…) è stata approvata / rifiutata / consegnata* | tu, per le tue richieste | una riga in chat |
| *Rientro di … (assente fino al …)* | ufficiali e Guild Master | solo qui |
| *Hai ricevuto … like* (il numero, mai chi) | tu | solo qui |
| *… vuole unirsi come …* | il capo di un [[gruppo|Groups-it]] | una riga in chat e un riquadro a schermo |
| *… ti ha accettato* / *ha rifiutato la tua candidatura* | chi si è candidato | una riga in chat e un riquadro a schermo |
| *Nuovo gruppo: …* | tu, per un gruppo adatto ai tuoi filtri | **spento** (solo qui) |
| *… chiama un raduno PvP alle …* (o nel mondo) *(dalla `v0.10.0`)* | tutti tranne chi chiama | una riga in chat |
| *La prova di … è finita il …: decidi* *(nascosto finché M12 non è completo)* | gli ufficiali e il Guild Master, una volta per prova il giorno della fine | una riga in chat |

### Chat, schermo o suono

Nelle [[Impostazioni|Settings-it]], card **Notifiche**, scegli per gli avvisi della banca e per quelli dei gruppi quello che vuoi tra:

- **Riga in chat**: una riga che comincia con `Accord:`. Gli avvisi che arrivano insieme escono insieme, al massimo tre righe e *e altri N*.
- **Avviso sullo schermo**: un riquadro in alto sullo schermo per 6 secondi. Clic per aprire la sua vista, clic destro per chiuderlo. Uno alla volta; quando ne aspettano molti sono riassunti in un riquadro.
- **Suono**: un suono del gioco, al massimo uno ogni 10 secondi. È spento di predefinito.

I due interruttori per le richieste nuove e per le decisioni sono quelli di prima, con lo stesso predefinito (acceso). Con tutte e tre le uscite spente gli avvisi vanno solo nella cronologia.

### Niente inondazioni

- La prima volta che l'addon gira in una gilda, ciò che c'è già non viene annunciato.
- Nei primi minuti dopo l'accesso gli avvisi dello stesso tipo sono raggruppati (*5 nuove richieste alla banca*) e mostrati una volta, quando quel tempo finisce (al massimo 5 minuti dopo l'accesso).
- Più di 20 avvisi dello stesso tipo in un minuto diventano uno solo.
- Dopo 30 avvisi in una sessione gli altri vanno solo nella cronologia, e una riga dice *Altri avvisi in /accord inbox*.

## Ore di quiete

> **Novità della `v0.9.0`**. Nulla delle ore di quiete è stato verificato nel gioco vero.

Un avviso **aspetta** invece di comparire in chat, sullo schermo o con un suono:

- mentre sei **in combattimento**, sempre;
- mentre sei in una **spedizione, incursione, campo di battaglia, arena o scenario**: l'interruttore *Anche in spedizioni, incursioni e campi di battaglia*, acceso di predefinito, che vale anche con le ore di quiete spente;
- nelle tue **ore di quiete**: l'interruttore *Ore di quiete*, **spento di predefinito**, con *Dalle* e *Alle* (23:00 e 8:00 se non li cambi), secondo l'ora del tuo computer. *Dalle* 23:00 *Alle* 8:00 vuol dire dalle 23:00 alle 7:59.

Si impostano nelle [[Impostazioni|Settings-it]], card **Notifiche**. La cronologia della pagina **Avvisi** ha subito ogni avviso, anche mentre aspetta.

Quando nulla li trattiene più, gli avvisi in attesa escono **una volta sola, nell'ordine di arrivo**: 3 secondi dopo il combattimento, 5 secondi dopo l'uscita dall'istanza, entro un minuto dalla fine delle ore di quiete. Escono insieme: al massimo tre righe in chat e *e altri N*, un solo riquadro sullo schermo e un solo suono. Un avviso che hai letto nel frattempo, che non è più vero o che ha aspettato più di 12 ore resta solo nella cronologia. Lo stesso gli avvisi in attesa se ricarichi l'interfaccia o esci dal gioco.

## Riepilogo all'accesso

> **Novità della `v0.9.0`**. Nulla del riepilogo all'accesso è stato verificato nel gioco vero.

Pochi secondi dopo l'**accesso** (non dopo un `/reload`), l'addon dice che cosa è cambiato **dall'ultima sessione** in questa gilda:

| Riga | Che cosa conta | Un clic apre |
|---|---|---|
| *2 nuovi membri: …* | chi è entrato, con al massimo tre nomi | il Roster |
| *1 membro uscito: …* | chi non è più in gilda | il Roster |
| *3 cose ti aspettano* | le righe **Adesso** e **Da fare** della pagina **In arrivo** | la pagina **In arrivo** |
| *Hai ricevuto 2 like* | **solo il numero, mai chi li ha dati** | Reputazione |
| *Banca: +120o, 14 movimenti* | la differenza dell'oro di gilda e le voci nuove dei registri della banca che puoi vedere | la Banca |
| *5 avvisi non letti* | gli avvisi che non hai letto | la pagina **Avvisi** |

Una riga c'è solo se non è zero. **Se non è cambiato nulla non compare nulla**: né riga in chat, né scheda, né suono. Le cose che aspettavano già all'ultima sessione non fanno comparire il riepilogo da sole; sono contate quando c'è qualcosa di nuovo.

- Le righe sono nella scheda **Dall'ultima sessione**, in cima alla pagina **In arrivo**. Fai clic su una per aprire la sua vista. **Chiudi** toglie la scheda; altrimenti resta fino al prossimo accesso.
- Una riga in chat le riassume con i soli numeri: *Accord: dall'ultima sessione: 2 nuovi membri, 2 like. /accord inbox*. Aspetta durante il combattimento, nelle istanze e nelle ore di quiete. Per spegnerla: [[Impostazioni|Settings-it]], card **Notifiche**, *Riepilogo all'accesso*.
- Ciò che i membri hanno fatto mentre eri via arriva sul tuo computer nei primi minuti: la scheda si completa per circa due minuti e mezzo dopo l'accesso. Se all'inizio non c'era niente da dire, la riga in chat esce alla fine di quel tempo. Ciò che arriva più tardi non è nel riepilogo.
- Con più di 50 persone tra entrate e uscite, o dopo più di 90 giorni di assenza, le righe del roster danno solo i numeri.
- La prima volta in una gilda non c'è riepilogo: l'addon si limita a ricordare come stanno le cose.
