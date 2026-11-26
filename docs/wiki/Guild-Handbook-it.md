# Manuale di gilda

*English: [[Guild handbook|Guild-Handbook]]*

> **Non ancora in un rilascio.** Il manuale è nel codice ma resta spento finché la milestone M11 non è completa: non ci sono la scheda **Manuale** né il comando. La lettura (passo M11.3), la scrittura (passo M11.4), le pagine predefinite (M11.5) e la pagina del loot (M11.6) sono fatte; segue la prova in gioco (M11.8). Niente è stato provato nel gioco vero. Quello che segue descrive come dovrebbe funzionare.

Il manuale è un insieme di pagine di testo che la gilda tiene nel gioco: informazioni, regolamento, FAQ, come funzionano i raid, il roster e il loot. Le scrivono gli ufficiali (e i gradi che gli ufficiali scelgono); **le legge ogni membro con Accord**. Il tuo computer conserva le pagine ricevute, quindi le leggi anche senza nessun altro online, com'erano all'ultima sincronizzazione.

## Leggere

Si apre con la scheda **Manuale** o con `/accord handbook`. `/accord handbook rules` apre una pagina dal suo nome (quello usato dai collegamenti); senza nome si apre l'ultima pagina letta.

- **A sinistra**, le pagine nell'ordine dato dalla gilda. Un clic la apre.
- **A destra**, la pagina, con quando è stata cambiata l'ultima volta e da chi.
- **I collegamenti** nel testo aprono un'altra pagina, a volte su una sua intestazione; **Indietro** torna dove eri. Un collegamento grigio porta a una pagina che non c'è o non è pubblicata. Un collegamento alla season apre la vista [[Season|Season-Roster-it]].
- **Indirizzi web**: un clic li mette in una casella, poi premi Ctrl+C. Il gioco non può aprire un browser.
- **Ricerca**: scrivi almeno 2 caratteri nella casella di ricerca in alto a destra. Si cerca nei titoli e nelle righe delle pagine, senza badare a maiuscole e accenti; un clic su un risultato apre la pagina a quella riga.

## La pagina del loot

La pagina **Gestione del loot** mostra anche, sopra il testo, il sistema e l'addon del loot della gilda, chi ce l'ha, e le regole di FDCP quando l'addon è FDCP: vedi [[Addon di raid e di loot|Raid-and-Loot-Addons-it]].

## Pagine aggiornate

Una pagina cambiata da quando l'hai letta è segnata **Aggiornata**, e la scheda mostra quante sono. Il segno sparisce quando tieni la pagina aperta per 2 secondi, oppure con **Segna tutto come letto**. La prima volta sono tutte segnate. Le modifiche fatte dal tuo account non vengono segnate. Con il [[Centro azioni|Action-Center-it]] hai anche una riga che dice quante pagine sono aggiornate.

Quello che hai letto resta sul tuo computer, condiviso tra i tuoi personaggi: nessun altro lo viene a sapere.

## Se scrivi le pagine

Scrivono il Guild Master, gli ufficiali e i gradi che gli ufficiali scelgono. Solo loro vedono i pulsanti qui sotto. Vedono anche le pagine che sono ancora **modelli** (i membri no) e le pagine **Oltre il limite** di 20.

- **Nuova pagina** (sotto l'elenco) e **Modifica** (sotto la pagina) aprono l'editor. In combattimento non si apre.
- Le **frecce** accanto alla pagina scelta ne cambiano il posto nell'elenco.
- **Elimina** toglie una pagina per tutta la gilda; serve un secondo clic su **Conferma**.
- **Scrittori** (solo ufficiali) sceglie i gradi che scrivono oltre agli ufficiali. Se la gilda rinomina o sposta un grado scelto, va scelto di nuovo: la vista lo dice.

### Le pagine predefinite

Finché il manuale non ha mai avuto una pagina, chi scrive vede **Crea le pagine predefinite** nella vista vuota, 2 minuti dopo l'accesso (così le pagine che altri hanno già arrivano prima). Un clic crea sei **modelli**: Informazioni sulla gilda, Regolamento, Domande frequenti, Gestione dei raid, Gestione del roster e Gestione del loot, nella tua lingua. Contengono solo intestazioni, più un collegamento al [[roster della season|Season-Roster-it]] nelle pagine del roster e del loot; il roster mostrato lì viene dalla fonte scelta dagli ufficiali. Niente sulla tua gilda viene scritto al posto tuo.

I membri non vedono un modello finché chi scrive non lo compila e lo salva (**Modifica**, poi **Salva**). Il pulsante compare una volta sola: un modello eliminato, o tutti, non torna. Senza il clic non si crea niente.

### L'editor

Scrivi il titolo e il testo. Testo semplice, riga per riga:

| Scrivi | Ottieni |
|---|---|
| `# Titolo` o `## Titolo` | un'intestazione |
| `- testo` (due spazi prima: secondo livello) | un elenco puntato |
| `1. testo` | un elenco numerato |
| `[[rules]]` o `[[rules\|il regolamento]]` | un collegamento a una pagina, con parole tue |
| `[[raid#Panchina]]` | un collegamento a un'intestazione di una pagina |
| `[[season]]` | un collegamento alla vista della season |

La `|` si digita così com'è: viene salvata come `¦`. Al salvataggio i link agli oggetti, le icone e i colori si tolgono (di un oggetto resta il nome tra parentesi quadre).

- Sotto il testo vedi **quanto è lungo** rispetto al limite: 4000 byte per pagina e 32 000 per tutto il manuale (una lettera accentata vale 2). Il titolo ha 40 byte e le pagine sono al massimo 20. **Salva** è spento finché qualcosa supera un limite, e l'editor dice che cosa; ciò che incolli non viene tagliato.
- **Anteprima** mostra la pagina come la leggeranno i membri; i collegamenti a pagine che mancano sono grigi.
- **Annulla** chiede un secondo clic se hai cambiato qualcosa.
- Quello che scrivi resta come **bozza** sul tuo computer (una sola). Se il gioco si chiude, apri l'editor sulla stessa pagina e scegli **Ripristina bozza**.
- Se qualcuno ha salvato la pagina mentre scrivevi, vedi il suo testo e scegli **Tieni la mia** (la tua viene scritta sopra) o **Scarta la mia** (la tua resta tra le revisioni, segnata *persa*).

### Revisioni

**Revisioni** elenca le versioni **viste da questo computer** (quella attuale e le ultime 5): le vecchie non viaggiano mai tra giocatori. Un clic la mostra; **Ripristina** la scrive come revisione nuova, per tutti. Una pagina eliminata sta sotto **Pagine eliminate** in fondo all'elenco, e si ripristina allo stesso modo.

Se due scrittori salvano insieme la stessa revisione, resta la più recente. Solo chi si è visto sostituire il testo viene avvisato, con un avviso e una riga del [[Centro azioni|Action-Center-it]] che apre quel testo: **Ripristina** lo riscrive, **Ignora** toglie la riga.
