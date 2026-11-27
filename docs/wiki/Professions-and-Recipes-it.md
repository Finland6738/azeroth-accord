# Professioni e ricette

*English: [[Professions and Recipes|Professions-and-Recipes]]*

> Disponibile dalla versione delle professioni (milestone M3): elenchi di ricette, **chi può creare** e **Chiedi di crearlo**.

## Le ricette della gilda

La vista **Professioni** (`/accord professions`, o la scheda **Professioni**) si apre sulle **ricette della gilda**: scegli una professione nell'elenco sopra la tabella e vedi **tutte le ricette di quella professione**, imparate da qualcuno della gilda o no. Ogni riga ha l'icona e il nome della ricetta (nella lingua del tuo gioco) e **quanti personaggi della gilda possono crearla** ("2 possono crearlo", o "ancora nessuno"). Le ricette sono ordinate per nome. WoW Forever non dice agli addon il livello di abilità che una ricetta richiede, quindi la vista non lo mostra.

- **Clicca una ricetta** per vedere **chi può crearla**, subito sotto: prima i personaggi online, gli alt di uno stesso giocatore insieme, con **Chiedi di crearlo** accanto a chi è online. Un altro clic la chiude.
- **Clicca un personaggio** per aprire **le sue ricette** di quella professione: quelle che ha imparato e, attenuate e segnate "non imparata", quelle che gli mancano. L'elenco sopra la tabella filtra *Imparate da …* o *Non imparate da …*. **Torna alle ricette della gilda** riporta indietro.
- Il secondo elenco sopra la tabella parte su *Qualcuno può crearla*: all'inizio vedi solo le ricette che qualcuno della gilda sa creare. Scegli *Tutte le ricette* per vedere tutta la professione, oppure *Nessuno può ancora crearla*, o le ricette che conosci o non conosci. La scelta resta quando passi a un'altra professione. La casella di ricerca filtra per nome.
- Passa il mouse su una ricetta per vedere il suggerimento del gioco, subito accanto al nome.
- La riga sotto il titolo dice chi ha condiviso l'elenco completo e quanto è vecchio.

L'elenco completo viene dal gioco stesso: lo condivide il primo compagno di gilda che apre la finestra di quella professione con Azeroth Accord, e si condivide di nuovo solo quando il gioco mostra qualcosa di nuovo. Fino ad allora la vista mostra solo le ricette che qualcuno della gilda conosce, e lo dice. Niente viene da un elenco spedito con l'addon.

## Aprire le ricette di un membro

Nella tabella del **Roster**, le celle **Professione 1** e **Professione 2** mostrano la professione e il suo livello (`Alchimia 285/300` quando il massimo è noto). Passa il mouse su una cella per vedere **da dove viene l'informazione** (il gioco, o l'addon del membro e quanto è vecchia) e cliccala: la vista **Professioni** si apre sull'elenco delle ricette di quel membro. Le righe delle professioni della **scheda del membro** fanno lo stesso.

L'elenco è una tabella con le colonne *Ricetta*, *Dettagli* e *Stato*: un'icona e il nome di ogni ricetta che il membro conosce, ordinate per nome, con il suggerimento del gioco quando passi il mouse su una ricetta. Sopra vedi il membro (nel colore della classe), la professione e il livello, **da dove viene l'elenco e quanto è vecchio** (per esempio "Fonte: condivisa dall'addon del membro, 3 g fa") e quante ricette corrispondono. Scorri gli elenchi lunghi con la rotella del mouse; l'elenco resta al suo posto quando arrivano nuovi dati.

- **Cerca**: scrivi nella casella di ricerca in alto nel pannello per filtrare per nome della ricetta.
- **Categoria**: l'elenco sopra la tabella offre *Ricette che conosco* e *Ricette che non conosco* (confrontate con il tuo elenco della stessa professione, dopo che hai aperto quella professione) e, quando il gioco le dice, le categorie delle ricette. Le ricette che conosci anche tu sono segnate "la conosci".
- **Torna al roster** riporta alla tabella, e **Chi può creare** apre la ricerca qui sotto.
- Quando la gilda ha l'elenco completo della professione, l'elenco del membro mostra **tutte le ricette** della professione, e quelle che il membro non ha imparato sono attenuate e segnate "non imparata".

![L'elenco delle ricette di un compagno: la fonte e l'età dell'elenco, la ricerca, un menu delle categorie, i colori della difficoltà, il suggerimento del gioco e Chiedi di crearlo](../specs/mockups/previews/professions-recipes.webp)

## Quando non c'è un elenco

Se il gioco non dà l'elenco e l'addon del membro non l'ha condiviso, il pannello dice perché e cosa fare: nessuno che abbia l'elenco è online (chiedi al membro di aprire la finestra della professione con Azeroth Accord, si condivide subito), il membro non usa l'addon, oppure l'elenco è in richiesta. Quando apri le ricette di un membro e l'addon non ha ancora il suo elenco, lo chiede con un sussurro (al membro se è online, altrimenti a un ufficiale) e l'elenco compare qualche secondo dopo.

## Le tue ricette

Le tue ricette si condividono quando apri la finestra della professione con l'addon: Azeroth Accord legge l'elenco un paio di secondi dopo che la finestra si apre (o cambia) e lo pubblica ai compagni che hanno l'addon. La stessa lettura dà alla gilda anche l'**elenco completo** della professione (vedi *Le ricette della gilda*). Una finestra che mostra le ricette di un altro (un link di professione dalla chat) non si legge mai. Si ripubblica solo quando qualcosa è cambiato (una nuova ricetta, un nuovo livello di abilità), e al massimo una volta ogni 10 minuti per professione. Anche Cucina, Primo soccorso e Pesca sono condivise, così "chi può creare" trova il tuo cuoco; non compaiono nelle colonne delle professioni del roster, che mostrano le due professioni principali.

## Chi può creare

Apri la vista **Professioni** (`/accord professions`, o la scheda **Professioni**), clicca **Chi può creare** e scrivi il nome di un oggetto o di una ricetta nella casella di ricerca a destra delle schede (almeno due lettere; puoi anche incollare il link di un oggetto). La vista elenca le ricette che corrispondono e, sotto ognuna, i membri che possono crearla: **prima i membri online**, poi per nome, con i personaggi di un giocatore insieme (gli alt un po' più a destra). Ogni riga dice la professione e il livello e da dove viene l'elenco e quanto è vecchio. Il pulsante **Solo online** (acceso finché è attivo) tiene solo i membri online adesso. Clicca un membro per vedere tutte le sue ricette; **Torna alla ricerca** riporta alla ricerca, e **Ricette della gilda** alle ricette della gilda.

La ricerca copre i membri **di cui l'elenco delle ricette è noto**: gli elenchi condivisi dai compagni che usano Azeroth Accord e quelli che il gioco ti ha dato quando hai aperto le ricette di un membro. Se non si trova nessuno, apri le ricette di qualche membro (l'addon le chiede) e cerca di nuovo.

![Chi può creare: i compagni che conoscono ogni ricetta, prima gli online, con la fonte e l'età del loro elenco e un pulsante Chiedi di crearlo](../specs/mockups/previews/professions-who-can-craft.webp)

*Anteprime di progetto, non screenshot: sono disegnate dal layout e dai testi dell'addon (qui in inglese), con personaggi e oggetti inventati, perché l'addon non è ancora stato provato nel gioco ([tutte le anteprime](https://github.com/Finland6738/azeroth-accord/blob/main/docs/specs/mockups/previews/README.md), anche in italiano).*

## Chiedi di crearlo

Accanto a ogni ricetta di un membro **online** (nel suo elenco, o sotto la ricetta in *Chi può creare*) c'è un pulsante **Chiedi di crearlo**. Apre la casella della chat con un sussurro a quel membro già scritto, con il link della ricetta: *"Ciao! Potresti creare [ricetta] per me? Grazie!"*. **Azeroth Accord non lo invia mai**: lo leggi, lo cambi se vuoi e premi Invio. Il pulsante non si vede per i membri offline (un sussurro non li raggiungerebbe), per le tue ricette e sulla riga di intestazione di una ricetta. Dalla `v0.9.0` il [[Centro azioni|Action-Center-it]] tiene un promemoria della richiesta per 7 giorni, solo sul tuo computer.

## Se manca qualcosa

- **L'elenco di un membro non c'è**: il gioco non dà sempre gli elenchi delle ricette, e l'addon di un membro condivide il suo solo dopo che apre la finestra della professione con Azeroth Accord. Il pannello lo dice, e chiede da solo l'elenco finché è online qualcuno che lo ha.
- **Una ricetta compare come "Ricetta 1234"**: il gioco non ha ancora dato il suo nome; compare tra un attimo.
- **"Chi può creare" non trova nessuno**: cerca tra i membri di cui l'elenco è noto. Apri le ricette di qualche membro (l'addon le chiede) e cerca di nuovo.

Vedi anche le [[Domande frequenti|FAQ-it]].
