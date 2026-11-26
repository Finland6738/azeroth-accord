# Giro dell'interfaccia

*English: [[Interface Tour|Interface-Tour]]*

## La scheda Accord

Apri la finestra della gilda (tasto predefinito `J`). Sotto le quattro schede del gioco (Chat, Roster, Vantaggi della gilda, Info gilda) ce n'è una quinta con il logo di Accord: **Accord**. Il suo suggerimento dice *Azeroth Accord*.

![La finestra della gilda con la scheda Accord selezionata: una quinta scheda sotto le quattro del gioco, il pannello con le schede delle viste in alto, i filtri e il Roster](../specs/mockups/previews/accord-tab-roster.webp)

![La stessa schermata con note numerate: la scheda, lo stato della sincronizzazione, la navigazione, i filtri, le colonne ordinabili, una riga e Stacca](../specs/mockups/img/01-accord-tab.webp)

*Anteprime di progetto, non screenshot: sono disegnate dal layout e dai testi dell'addon (qui in inglese), con personaggi e oggetti inventati, perché l'addon non è ancora stato provato nel gioco ([tutte le anteprime](https://github.com/Finland6738/azeroth-accord/blob/main/docs/specs/mockups/previews/README.md), anche in italiano).*

- Cliccarla mostra il pannello di Accord sopra il contenuto della finestra della gilda, nei colori del tema, e finché è aperto **anche la finestra intorno ha il tema**: una cornice tematica con il nome della tua gilda, una croce tematica e le cinque schede a lato come tessere arrotondate (quella aperta ha il colore d'accento). Cliccare una qualsiasi scheda del gioco rimette l'aspetto del gioco e torna al suo contenuto; chiudere la finestra chiude il pannello.
- Quando ci sono richieste alla banca che aspettano gli ufficiali, la scheda porta un piccolo segno rotondo con il loro numero.
- La scheda si vede solo quando la tua **gilda** è la comunità selezionata, e non nella finestra piccola (ridotta) della gilda.
- Il pannello non ha nulla di protetto: si apre e si chiude anche in combattimento e non cambia mai come funzionano le schede del gioco: l'addon rende soltanto trasparente la grafica della finestra del gioco finché il pannello è aperto e la rimette dopo.
- Se un aggiornamento del gioco cambia la finestra della gilda al punto che la scheda non si può collocare, la scheda semplicemente non compare: usa `/accord` per la finestra autonoma, e `/accord debug` dice perché.

## Il pannello

- **Schede** in alto: **Centro azioni**, **Roster**, **Professioni**, **Reputazione**, **Banca**, **Gruppi**, **Season**, **Eventi**, **Disponibilità**, **Addon della gilda**, **Impostazioni** (e **Ufficiali** per gli ufficiali). Le schede che non stanno accanto alla casella di ricerca sono dietro **Altro**, l'ultima scheda: cliccala e scegli una vista; mostra la somma dei loro numeri, e la vista aperta tiene sempre la sua scheda. La scheda aperta è luminosa, con una breve linea sotto che scivola sulla scheda che clicchi. L'ultima scheda aperta è ricordata per ogni personaggio. La scheda **Banca** mostra un piccolo numero quando ci sono richieste alla banca che aspettano un ufficiale.
- A destra delle schede: una casella **Cerca**, mentre la vista aperta può cercare (ciò che scrivi va a quella vista) e, nella finestra della gilda, **Stacca**, che sposta il pannello in una finestra sua, più grande.
- Nella finestra della gilda una linea sottile in basso mostra lo **stato della sincronizzazione**, per esempio *3 compagni di gilda con Accord online · aggiornato 2 min fa* (la finestra autonoma lo mostra sotto il titolo).
- Se una vista non riesce a disegnarsi, mostra invece un breve messaggio e le altre schede continuano a funzionare; cliccare di nuovo la sua scheda riprova.
- **Novità della `v0.9.0`:** le viste [[Centro azioni|Action-Center-it]], [[Gruppi|Groups-it]] e [[Addon della gilda|Guild-Addons-it]].
- **Dalla `v0.10.0`** (il prossimo rilascio): le viste [[Season|Season-Roster-it]], [[Eventi|Events-it]] e [[Disponibilità|Availability-it]].
- **Le viste del primo rilascio, `v0.8.0`**: **Roster**, **Professioni**, **Reputazione**, **Banca**, **Impostazioni**. La vista **Roster** arriva con la versione del roster e la vista **Impostazioni** (vedi [[Impostazioni|Settings-it]]; la stessa pagina è nella finestra delle impostazioni del gioco) con la versione di rilascio; vedi [[Roster di gilda|Guild-Roster-it]]. La vista **Professioni** (l'elenco delle ricette di un membro, aperto dal roster) arriva con la versione delle professioni; vedi [[Professioni e ricette|Professions-and-Recipes-it]]. La vista **Reputazione** (i like, una riga per giocatore ordinata per like, con il pulsante Like; il tuo indice sociale; la mappa dei gruppi per gli ufficiali; *Qualcuno di nuovo* con cui giocare) arriva con la versione della reputazione; vedi [[Like e indice sociale|Likes-and-Social-Index-it]]. La vista **Banca** (la banca di gilda scheda per scheda, il suo denaro, un elenco di oggetti con ricerca) arriva con la versione della banca (gli ufficiali vedono sulla scheda anche il numero di richieste in attesa); vedi [[Banca di gilda|Guild-Bank-it]]. Gli ufficiali hanno anche la scheda **Ufficiali**, con i giocatori inattivi e la cronologia del roster (vedi [[Roster di gilda|Guild-Roster-it]]).

## I temi

Il pannello ha tre temi, scelti in **Impostazioni → Aspetto** (vedi [[Impostazioni|Settings-it]]): **Nebula**, quello scuro predefinito, **Aurora**, uno chiaro, e **Accord**, scuro con il verde e l'oro del logo. Cambiano solo i colori: ogni vista ha lo stesso aspetto nei tre temi, e la scelta si vede subito.

![Il Roster nel tema chiaro Aurora](../specs/mockups/previews/roster-aurora.webp)

![La scheda del membro nel tema Accord](../specs/mockups/previews/member-card-accord.webp)

*Anteprime di progetto, non screenshot: sono disegnate dal layout e dai testi dell'addon (qui in inglese), con personaggi e oggetti inventati, perché l'addon non è ancora stato provato nel gioco ([tutte le anteprime](https://github.com/Finland6738/azeroth-accord/blob/main/docs/specs/mockups/previews/README.md), anche in italiano).*

## La finestra autonoma

![La finestra autonoma: lo stesso pannello in una finestra che puoi spostare e ridimensionare, qui sui Like della vista Reputazione](../specs/mockups/previews/window-standalone.webp)

`/accord`, la voce del Compartimento AddOn, un tasto assegnato o **Stacca** aprono lo stesso pannello in una finestra propria, nei colori del tema:

- la **barra del titolo** in alto: il logo tondo di Accord, **AZEROTH ACCORD**, sotto lo stato della sincronizzazione, **Riaggancia** e il pulsante di chiusura. **Riaggancia** si vede mentre la finestra della gilda è aperta sulla tua gilda: rimette il pannello nella finestra della gilda e chiude questa. (L'addon non apre mai da solo la finestra della gilda del gioco.)
- sotto, le stesse **schede** e la stessa casella **Cerca** della finestra della gilda;
- trascina la barra del titolo per spostare la finestra e il segno nell'angolo in basso a destra per ridimensionarla. Si apre a 920 × 600 e non si può rimpicciolire sotto 720 × 460; ricorda posizione e dimensione per ogni personaggio. Esc la chiude.

Cliccare la scheda Accord della finestra della gilda mentre questa finestra è aperta sposta il pannello lì e chiude la finestra, così il pannello non è mai in due posti. Vedi [[Comandi|Commands-it]].
