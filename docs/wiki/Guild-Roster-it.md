# Roster di gilda

*English: [[Guild Roster|Guild-Roster]]*

> Disponibile dalla versione del roster (milestone M2). Le colonne Like e Sociale arrivano con la milestone M4 (Like: il totale del giocatore, verde quando gli hai dato un like, grigio finché il tuo like è in attesa; Sociale: l'indice sociale, un trattino sotto le 5 ore di gioco di gruppo, mostrato solo agli ufficiali e al Maestro di gilda). Le celle delle professioni aprono le ricette del membro dalla versione delle professioni (milestone M3): vedi [[Professioni e ricette|Professions-and-Recipes-it]].

La vista **Roster** è una tabella di tutti i membri: nome, livello, classe, grado, zona, ultimo accesso, **professione 1** e **professione 2**, like, indice sociale, Battle.net e Discord. Clicca l'intestazione di una colonna per ordinare (un secondo clic inverte; il titolo della colonna ordinata è nel colore d'accento con una freccia, e i membri senza nulla in quella colonna vanno sempre in fondo); usa la casella di ricerca in alto a destra delle schede (nome o professione) e i filtri: i pulsanti *Online*, *Solo main* e *Per account* (accesi finché sono attivi) e gli elenchi *Classe*, *Grado* e *Professione* (la prima voce di ognuno mostra di nuovo tutto); *Colonne* apre un elenco di caselle per scegliere quali colonne mostrare, e le tue scelte sono ricordate per ogni personaggio. Quando il pannello è stretto i filtri continuano su una seconda riga. La tabella resta veloce con una gilda di 1000 membri.

## La tabella

![La tabella del Roster: colonne ordinabili, filtri per online, solo main, classe, grado e professione, e la scelta delle colonne](../specs/mockups/previews/roster-table.webp)

Clicca un titolo per ordinare, cliccalo di nuovo per invertire. Ogni nome ha un quadratino del colore della classe, e il nome è scritto in quel colore (nel tema chiaro il nome resta scuro e solo il quadratino porta il colore). **Per account** raggruppa la tabella per giocatore: il main in testa, un clic su + mostra gli alt.

![Il Roster raggruppato per account: il main di Brynn con due alt mostrati sotto](../specs/mockups/previews/roster-grouped.webp)

## Da dove viene un valore

Accanto a un valore che non arriva direttamente dal gioco, Accord mostra una piccola **etichetta** grigia con la sua fonte: `gioco` (letto adesso dal gioco), un'età come `3 g fa` (condiviso dall'addon di un altro giocatore, cambiato l'ultima volta 3 giorni fa), `tu` (letto dal tuo personaggio) oppure `nota` (dichiarato nella nota pubblica del membro: Accord non può verificarlo). Passa il mouse sopra per vedere chi ha riportato il valore. L'etichetta compare nella scheda del membro (professioni, contatti, personaggi dell'account, versione dell'addon), nelle celle delle professioni della tabella (nel tooltip), sopra l'elenco delle ricette, nel totale dei like e su ogni scheda della banca di gilda. Un valore condiviso che non cambia da molto tempo è **attenuato** e il tooltip lo dice: 7 giorni per una scheda della banca, 60 per professioni e ricette, 30 per la versione dell'addon, 180 per BattleTag e Discord. L'età è "da quanto il valore non cambia", non "da quanto qualcuno l'ha controllato".

## La scheda del membro

Clicca una riga per aprire la **scheda del membro**: accanto alla tabella in un pannello largo, sopra di essa (con un pulsante *Indietro*) in uno stretto; la croce la chiude. La scheda ha il nome del membro nel colore della classe, qualche **distintivo** sotto (*online* o *fuori gilda*, *main* o *alt* quando il giocatore ha altri personaggi, e la versione dell'addon) e un riquadro per ogni sezione. Mostra zona, ultimo accesso, grado, la nota pubblica (e la nota degli ufficiali solo se il gioco ti lascia leggerla), la versione dell'addon e le professioni con la provenienza di ogni informazione (il gioco, condivisa dal membro e quanto è vecchia, o letta dal tuo personaggio); i riquadri delle professioni e degli altri personaggi riportano il loro numero. Le righe che fanno qualcosa (un link a un altro personaggio, **[Rendi questo il mio main]**, **[Dai un like]**) sono nel colore d'accento: clicca un altro personaggio nella scheda per aprire la sua scheda, o una riga di professione per vedere le ricette di quel membro. Se la scheda è più lunga della finestra, scorrila con la rotella del mouse.

![La scheda del membro accanto alla tabella: dettagli, professioni con la loro fonte, i personaggi dello stesso account, contatti, like e indice sociale](../specs/mockups/previews/member-card.webp)

![La scheda del membro con note numerate](../specs/mockups/img/02-member-card.webp)

*Anteprime di progetto, non screenshot: sono disegnate dal layout e dai testi dell'addon (qui in inglese), con personaggi e oggetti inventati, perché l'addon non è ancora stato provato nel gioco ([tutte le anteprime](https://github.com/Finland6738/azeroth-accord/blob/main/docs/specs/mockups/previews/README.md), anche in italiano).*

## Personaggi dello stesso account

Sui tuoi personaggi la scheda offre **[Rendi questo il mio main]**. La scheda elenca **tutti i personaggi dello stesso account Battle.net nel reame**, anche quelli fuori dalla gilda, per ogni membro che usa l'addon. Attiva *Per account* nella tabella per vedere una riga per giocatore con gli alt sotto (clicca **+** per mostrarli).

Un personaggio che non è in gilda compare lo stesso. Il main è quello scelto dal giocatore, altrimenti il personaggio di livello più alto.

**Alt in un'altra gilda.** Per un personaggio fuori dalla gilda la scheda e le righe raggruppate dicono dov'è: *Altra gilda: <nome> · visto 3 g fa*, oppure *Nessuna gilda · visto oggi* se il personaggio non ha gilda. La riga è letta dai personaggi di quel giocatore che sono nella tua gilda, quindi:

- è **vecchia quanto l'ultimo accesso di quell'alt** con l'addon (si mostra a giorni: *oggi*, *3 g fa*); se l'alt entra in una gilda o ne esce, lo vedi solo dopo che quell'alt ha fatto l'accesso e il giocatore ha fatto l'accesso con un personaggio della tua gilda. Una riga più vecchia di un mese è attenuata, e la sua etichetta dice chi l'ha condivisa;
- un personaggio noto solo da una nota pubblica non mostra nessuna gilda, e nemmeno uno che l'addon non ha più visto da prima di questa funzione: mostra *fuori gilda* come prima;
- **l'altra gilda non vede nulla dei dati di Accord della tua gilda.** Nell'elenco dei personaggi che la tua gilda già riceve viaggiano solo il nome della gilda e il giorno dell'ultimo accesso di quell'alt.

Per i membri senza l'addon, una nota pubblica di gilda scritta come `main: <nome>` (il mio main è quel personaggio) o `alt: <nome>` (quel personaggio è un mio alt) è mostrata come indizio, con l'etichetta *dichiarato nella nota*. Un membro che ha l'addon non viene mai spostato da una nota.

Il raggruppamento non si può falsificare: due personaggi contano come un solo giocatore solo se **entrambi** si elencano a vicenda, quindi elencare il personaggio di qualcun altro non cambia nulla.

## Contatti

La scheda mostra il **BattleTag** e il nome **Discord** dei membri che usano l'addon (il nome Discord anche per tutti quando il gioco lo fornisce, segnato *dal gioco*). **Clicca un contatto** per aprire una piccola finestra con il testo già selezionato: premi Ctrl+C per copiarlo, poi Esc (o *Chiudi*). **[Aggiungi amico BattleTag]** invia la richiesta di amicizia del gioco; funziona anche se l'altro giocatore non usa l'addon. La tabella ha una colonna *Contatti* (BT e DC) che puoi mostrare o nascondere.

Il tuo BattleTag è letto dal gioco. Scrivi il tuo **nome Discord** (solo il nome utente, fino a 32 caratteri, senza link) in [[Impostazioni|Settings-it]] (`/accord settings`); si usa quando il gioco non lo mostra già. Entrambi sono sempre condivisi con la tua gilda.

## Cronologia (solo ufficiali)

Gli ufficiali e il Guild Master vedono nella scheda del membro un riquadro **Cronologia**: ciò che gli addon degli ufficiali hanno osservato cambiare nel roster per i personaggi di quel giocatore, dal più recente. Elenca le **ultime dieci** variazioni di **ogni personaggio del giocatore in gilda**, con un link **Mostra tutto (n)** che apre tutto l'elenco nella scheda, e la riga *Membro dal <data>* dall'ingresso più vecchio che Accord ha visto (*Membro dal: sconosciuto* se non ne ha visto nessuno: la prima volta che l'addon di un ufficiale legge il roster fa solo una fotografia, quindi chi è già in gilda non "entra").

Una riga è l'ora e ciò che è successo: *è entrato nella gilda*, *è uscito dalla gilda* (il gioco non dice se il membro se n'è andato o è stato espulso), *grado Membro → Veterano*, *livello 20 → 27* e *nota pubblica: "vecchia" → "nuova"*. Le ore sono **UTC**. Passa il mouse su una riga per vedere chi l'ha osservata (tu, il nome di un compagno, o *un ex ufficiale*; mai un codice tecnico) e l'intervallo esatto: un addon vede un cambiamento solo quando legge il roster, quindi la riga dice *tra il <data> e il <data>* quando dall'ultima lettura è passato più di un giorno. I livelli guadagnati da un personaggio in un giorno sono una riga sola.

- **Due ufficiali che vedono lo stesso cambiamento fanno una riga sola.** Lo stesso cambiamento visto da due ufficiali, anche in momenti diversi, si mostra una volta, con l'intervallo più stretto e tutti gli osservatori nel tooltip.
- **Per sempre.** Nulla si cancella perché è vecchio: la cronologia, con il testo vecchio e nuovo delle note pubbliche, resta finché gli addon degli ufficiali la tengono. Se smetti di essere ufficiale, il tuo addon la cancella dal tuo computer (vedi sotto).
- **Solo ufficiali.** I membri non vedono mai il riquadro, non ricevono mai questi record e il loro addon non osserva nulla. Chi lo vede è un'unica impostazione nel codice, in attesa della decisione del proprietario ([SPEC-10 Q13](https://github.com/Finland6738/azeroth-accord/blob/main/docs/specs/SPEC-10-risks-open-questions.md)).
- **Dove sta.** Sul computer dell'ufficiale che l'ha osservato. Si condivide con gli altri ufficiali **solo sul canale degli ufficiali** (mai con la gilda, mai in whisper a un membro) e **solo dopo che l'addon ha visto quel canale portare un messaggio addon nella sessione**; fino ad allora il riquadro dice *Solo su questo computer finché il canale degli ufficiali non funziona* e mostra *Canale ufficiali: funzionante* oppure *non ancora provato*. Se smetti di essere ufficiale, con tutti i tuoi personaggi, Accord toglie questi dati dal tuo computer.
- Accord non cambia mai il roster: lo guarda soltanto. Nulla viene promosso, retrocesso o espulso dall'addon.
