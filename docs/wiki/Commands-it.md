# Comandi

*English: [[Commands|Commands]]*

Scrivili nella casella della chat. `/acc` funziona ovunque funzioni `/accord`.

| Comando | Cosa fa |
|---|---|
| `/accord` | Apre o chiude la finestra di Accord (devi essere in una gilda) |
| `/accord inbox` | Apre il **Centro azioni**, l'elenco di ciò che ti aspetta (vedi [[Centro azioni|Action-Center-it]]) *(M9.2, dalla `v0.9.0`)* |
| `/accord groups` | Apre la vista **Gruppi**, il cercagruppi della gilda (vedi [[Gruppi|Groups-it]]) *(M9.7, dalla `v0.9.0`)* |
| `/accord roster` | Apre la vista Roster |
| `/accord professions` | Apre la vista Professioni su **chi può creare** (vedi [[Professioni e ricette|Professions-and-Recipes-it]]) |
| `/accord reputation` | Apre la vista Reputazione: i like di ogni giocatore e il pulsante Like, il tuo indice sociale, la mappa dei gruppi (ufficiali), *Qualcuno di nuovo* con cui giocare *(M4)* |
| `/accord bank` | Apre la vista Banca *(M5)* |
| `/accord settings` | Apre la vista Impostazioni: nome Discord, personaggio principale, avvisi, colonne del Roster, dati salvati (vedi [[Impostazioni|Settings-it]]) |
| `/accord away 2026-12-31` | Dichiara che sei assente fino a quel giorno (lo vedono solo gli ufficiali); `/accord away off` la cancella, `/accord away` la mostra (vedi [[Roster di gilda|Guild-Roster-it]]) *(M8.3)* |
| `/accord about` | Apre la pagina Info delle Impostazioni: crediti, link da copiare, licenza. `/accord about chat` scrive invece i crediti in chat (vedi [[Informazioni e crediti|About-it]]) |
| `/accord backup` | Apre la card **Backup** della pagina Impostazioni: esporta i tuoi dati in un testo, o importali su un altro computer (vedi *Backup e ripristino* in [[Impostazioni|Settings-it]]) |
| `/accord demo` | Riempie ogni vista con una **gilda inventata**, per provare l'addon senza gilda o per mostrarlo. Non si invia e non si salva nulla; scrivilo di nuovo per uscire (vedi [Modalità demo](#modalità-demo)) |
| `/accord debug` | Apre un rapporto di diagnostica, già selezionato: premi Ctrl+C e incollalo in una segnalazione. Non contiene nomi di giocatori, gilde, BattleTag o Discord |
| `/accord help` | Elenca i comandi in chat |

Una vista che non è ancora nella tua versione risponde "Questa parte arriva presto".

Altri modi per aprire la finestra:

- il **Compartimento AddOn** (il pulsante dell'elenco degli addon accanto alla minimappa): clic su *Azeroth Accord* (ha il logo dell'addon, come la finestra);
- un **tasto assegnato**: *Opzioni → Assegnazione tasti → AddOn → Azeroth Accord*, "Apri o chiudi Azeroth Accord";
- la **scheda Accord** della finestra della gilda, poi **Stacca** per la finestra più grande; **Riaggancia**, nella barra del titolo di quella finestra, rimette il pannello nella finestra della gilda mentre è aperta.

`/accord <vista>` apre la finestra sulla scheda di quella vista (o cambia scheda, se il pannello è già aperto nella finestra della gilda). Esc chiude la finestra.

## Modalità demo

`/accord demo` trasforma l'addon in una visita guidata: ogni vista (Roster, scheda del compagno, Professioni e ricette, Reputazione con i like e la mappa dei gruppi, Banca con registri e richieste, Impostazioni) si riempie con una **gilda inventata**, "Demo Guild", di 60 membri con nomi inventati, 20 giocatori con l'addon, tre professioni, una banca e le sue richieste. Funziona senza gilda e senza connessione, quindi è anche il modo di vedere l'addon prima di entrare in una gilda.

- Una striscia in cima al pannello dice **Demo: gilda inventata. Non si invia né si salva nulla.** e ha il pulsante *Esci dalla demo*; la barra del titolo e la riga sotto il pannello dicono *Demo* al posto del numero di compagni.
- **Non si invia nulla**: né un messaggio alla gilda, né un sussurro, né un invito. Ciò che la gilda ti manda intanto si ignora (la sincronizzazione lo ripara pochi secondi dopo l'uscita). Un messaggio che era già in attesa di partire aspetta, e parte dopo la demo.
- **Non si salva nulla**: lavori su una copia dei tuoi dati, quindi un like, una richiesta alla banca, un principale o un tema scelti nella demo spariscono quando finisce. I tuoi dati veri, la tua gilda vera e le tue impostazioni vere tornano esattamente com'erano. Anche un `/reload` o l'uscita dal gioco chiudono la demo: non resta mai accesa.
- Nella gilda inventata sei un ufficiale, quindi si vedono anche le viste degli ufficiali (la scheda della banca solo per ufficiali, le decisioni sulle richieste, la mappa dei gruppi).
- I nomi di professioni e ricette li dà il gioco; se il gioco non conosce un incantesimo, la vista mostra il suo numero.

Scrivi di nuovo `/accord demo` (o `/accord demo off`, o premi *Esci dalla demo*) per uscire.
