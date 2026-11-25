# Impostazioni

*English: [[Settings|Settings]]*

Aprile con `/accord settings`, o dalla scheda **Impostazioni** del pannello. La stessa pagina è anche nella finestra delle impostazioni del gioco, sotto *Opzioni → AddOn → Azeroth Accord*. Una modifica fatta in un posto si vede subito nell'altro, e ogni modifica è salvata appena la fai.

La pagina scorre con la rotella del mouse.

![La pagina Impostazioni: la card Aspetto, poi i contatti e il personaggio principale](../specs/mockups/previews/settings.webp)

![La parte bassa della pagina: avvisi, colonne del Roster, le dimensioni dei dati salvati e Cancella i dati della gilda](../specs/mockups/previews/settings-saved-data.webp)

*Anteprime di progetto, non screenshot: sono disegnate dal layout e dai testi dell'addon (qui in inglese), con personaggi e oggetti inventati, perché l'addon non è ancora stato provato nel gioco ([tutte le anteprime](https://github.com/Finland6738/azeroth-accord/blob/main/docs/specs/mockups/previews/README.md), anche in italiano).*

## Aspetto

La prima card decide come appare Azeroth Accord. La scelta è salvata **per account**, quindi tutti i tuoi personaggi hanno lo stesso aspetto, e una modifica si vede subito, senza `/reload`.

| Opzione | Scelte | Predefinito |
|---|---|---|
| Tema | **Nebula** (scuro, viola e arancione), **Aurora** (chiaro, blu e verde acqua), **Accord** (scuro, verde e oro, i colori del logo) | Nebula |
| Effetti neon | sì / no: i bagliori dei temi scuri; spenti danno colori piatti, un po' più leggeri per il computer | sì |
| Animazioni | sì / no: dissolvenze, scorrimenti e la pressione dei pulsanti; spente rendono ogni cambiamento immediato | sì |
| Carattere | **Caratteri di Accord** (Orbitron, Outfit, JetBrains Mono) o **Carattere del gioco** | Caratteri di Accord |

Passa il mouse su un interruttore per una breve spiegazione. Un carattere che il gioco non ha ancora caricato si vede ovunque dopo `/reload` (il gioco legge i nuovi file di caratteri solo allora). I colori delle classi e degli oggetti sono quelli del gioco e non cambiano con il tema; nel tema chiaro il nome di un giocatore è scuro e il quadratino accanto porta il colore della classe.

## Contatti condivisi con la gilda

- Il tuo **BattleTag** è letto dal gioco e mostrato qui.
- Scrivi il tuo **nome Discord** (solo il nome utente, da 2 a 32 caratteri, senza spazi e senza link) e premi *Salva*. Si usa solo quando il gioco non mostra già il tuo nome Discord ai compagni.

Entrambi sono **sempre condivisi con la tua gilda**, così i compagni possono raggiungerti: non c'è un interruttore. Niente esce dalla gilda. Vedi [[Privacy e dati|Privacy-and-Data-it]].

## Personaggio principale

Scegli quale dei tuoi personaggi è il tuo **main**. Guida i tuoi personaggi nel Roster raggruppato e nella scheda del membro ([[Roster di gilda|Guild-Roster-it]]). Finché non ne scegli uno, guida il personaggio di livello più alto. Il menu elenca i personaggi del tuo account in questo reame.

## Assenza

Dì agli ufficiali quando torni: scrivi la **data di rientro** (AAAA-MM-GG, al massimo tra 180 giorni) e premi **Salva**; **Cancella** la toglie. Fino a quel giorno, compreso, gli ufficiali non ti contano tra gli inattivi. La vedono solo loro, e non si chiede il motivo. La card mostra ciò che ha dichiarato il **tuo** account. Lo stesso dalla chat: `/accord away 2026-12-31`, `/accord away off`. Vedi *Assenze dichiarate* in [[Roster di gilda|Guild-Roster-it]].

## Notifiche

| Opzione | Chi la vede | Predefinito |
|---|---|---|
| Avvisami in chat delle nuove richieste alla banca | solo gli ufficiali | sì |
| Avvisami in chat quando le mie richieste alla banca sono decise | tutti | sì |

Ogni opzione è un interruttore. Dalla `v0.9.0` la stessa card fa anche scegliere se gli avvisi della banca arrivano come riga in chat, riquadro sullo schermo o suono, e ogni avviso resta nella cronologia ([[Centro azioni|Action-Center-it]]). Avrà anche le **ore di quiete**: quando gli avvisi aspettano ([[Centro azioni|Action-Center-it]]). Sono singole righe in chat (mai un diluvio all'accesso). Spegnerle non nasconde nulla: il contatore sulla scheda Accord e la vista Banca mostrano sempre cosa è in attesa ([[Banca di gilda|Guild-Bank-it]]).

## Colonne del roster

Clicca i chip delle colonne che la tabella del Roster mostra (un chip pieno è mostrato); la colonna del nome c'è sempre. *Colonne predefinite* le rimette a posto. La scelta è salvata **per personaggio**.

## Dati salvati

Mostra quanto sono grandi i dati salvati dall'addon nel tuo computer (stime del file salvato): l'account, questo personaggio e la gilda attuale, con una riga per ogni tipo di dato della gilda e il suo numero di record. Non contiene nomi.

**Cancella i dati della gilda** dimentica tutto ciò che l'addon ha sulla gilda attuale e chiede ai compagni di rimandarlo. Cliccalo una volta per vedere quanto si libererà, poi clicca di nuovo entro 8 secondi per cancellare (altrimenti si annulla).

**Conserva** ciò che solo il tuo computer conosce e la gilda non può rimandare: i tuoi like (così non puoi dare due volte lo stesso like), la chiave dei like della gilda se sei ufficiale, lo storico del denaro della banca e quali avvisi ti sono già stati dati (dalla `v0.9.0` la cronologia degli avvisi si svuota). Non tocca mai i dati dell'account (i tuoi personaggi, il tuo main, il tuo nome Discord), le tue impostazioni o i dati di un'altra gilda. Si può usare tranquillamente quando i dati sembrano sbagliati o troppo grandi; la gilda li riempie di nuovo entro pochi minuti, quando ci sono compagni online.

## Cosa condivido

La pagina **Cosa condivido** (*What I share*), tra *Settings* e *Info* in cima al pannello, mostra tutto ciò che **questo personaggio** pubblica per la tua gilda, come è stato mandato l'ultima volta. Non indovina: ogni card legge i record che il tuo client tiene a nome di questo personaggio, gli stessi che ha mandato (o sta per mandare) ai compagni.

Ogni card dice **chi lo riceve**, **quando parte** e **cosa contiene adesso**, con quanto tempo fa è stato aggiornato e il numero di revisione.

| Card | Cosa mostra |
|---|---|
| I tuoi personaggi | i primi quattro caratteri del codice dell'account (mai il codice intero), ogni personaggio con reame, classe, livello e *In questa gilda*, *Other guild: X* o *No guild* più il giorno dell'ultimo accesso, il tuo main e la versione dell'addon |
| Contatti | il tuo BattleTag e il nome Discord; sempre condivisi, senza interruttore |
| Ricette | ogni professione: nome, grado e numero di ricette |
| Tempo giocato insieme | gli ultimi 7 giorni: quante coppie e quanti minuti per giorno. Le coppie nominano i tuoi compagni, non solo te |
| Foto della banca di gilda | le schede lette (nome, numero di oggetti), il denaro e i registri |
| Le tue richieste alla banca | le tue ultime 5 richieste e il loro stato |
| Like | quanti like ha dato il tuo account (tenuto solo su questo computer) |
| Riepilogo della sincronizzazione | la versione dell'addon e un'impronta dei record che hai, mai il loro contenuto |
| Assenza | la data di rientro che hai dichiarato; solo agli ufficiali, senza interruttore (*Cancella* la toglie) |
| Dati degli ufficiali | solo per gli ufficiali: le voci del libro dei like e le impostazioni della gilda che hai scritto |
| Strumenti per ufficiali | solo per gli ufficiali: i cambiamenti del roster osservati da questo personaggio, le assenze che hai impostato e le fasce di inattività che hai scelto; solo agli ufficiali |

Gli altri tuoi personaggi non sono elencati come pubblicati da questo: ognuno pubblica i suoi record quando accedi con lui.

### L'unico interruttore

**Registra il tempo giocato insieme** (acceso di default) è l'unica cosa che qui si può spegnere. Spento, questo client smette di contare e di pubblicare il tempo giocato insieme e non scrive record nuovi. I record già pubblicati restano finché scadono (90 giorni), e i client dei compagni continuano a osservare i gruppi in cui c'è anche questo personaggio; la card lo dice. Ricette e foto della banca non hanno interruttore perché sono la funzione stessa, e i tuoi personaggi, il BattleTag e il Discord sono sempre condivisi ([[Privacy e dati|Privacy-and-Data-it]]).

## Backup e ripristino

La card **Backup** in fondo alla pagina (o `/accord backup`) porta i **tuoi** dati su un altro computer, per esempio dopo aver reinstallato il gioco o quando giochi da un secondo PC. Quasi tutto ciò che Accord mostra torna da solo dai compagni di gilda; il backup porta ciò che conosce solo il tuo computer.

Cosa contiene:

- i tuoi personaggi (nome, classe, livello, gilda e quando sono stati visti l'ultima volta) e il main scelto su ogni reame;
- queste impostazioni: tema, effetti, animazioni, carattere, avvisi e il tuo nome Discord;
- i tuoi record in ogni gilda che conosci: l'elenco degli alt, i contatti e le liste di ricette;
- il **token dell'account**, così i tuoi like continuano come prima (lo stesso pseudonimo: un like già dato non conta due volte).

Cosa **non** contiene mai: dati di altri giocatori di qualsiasi tipo (i loro alt, contatti, ricette, like), il tempo giocato insieme, la banca (foto, registri e richieste), le impostazioni della gilda e la posizione della finestra. Sono della gilda, o di questo computer, e tornano dalla gilda.

**Esporta** apre una casella con tutto il testo già selezionato: premi **Ctrl+C**, poi incollalo in un file di testo che conservi. È una sola riga lunga che comincia con `AZACCORD1:`.

> **Tieni questo testo per te: contiene il token del tuo account.** Chi pubblica il tuo token blocca i tuoi like finché non smette. Non incollarlo in una chat, in un forum o in una segnalazione.

**Importa**, sull'altro computer: entra con un personaggio qualsiasi dell'account, apri la card, premi **Importa**, incolla il testo (**Ctrl+V**) e premi **Controlla**. Non cambia ancora nulla. Un testo valido mostra cosa cambierebbe: il token (resta o è sostituito), i personaggi che aggiunge, il main, ogni impostazione diversa (vecchia → nuova) e, per ogni gilda, quanti tuoi record ripristina e quanti restano perché questo computer ne ha già una versione più nuova. Un record non viene mai sostituito da uno più vecchio. Premi **Importa** per applicarlo, o **Annulla** per tornare indietro. Poi Accord ripubblica i tuoi record.

Un testo viene rifiutato, e non cambia nulla, quando:

| Messaggio | Perché |
|---|---|
| *Questo non è un backup di Azeroth Accord.* | il testo è vuoto, troppo lungo (oltre 256 KB) o non comincia come un backup |
| *Questo backup è stato fatto da una versione più nuova di Azeroth Accord. Aggiorna l'addon e riprova.* | il testo viene da un Accord più nuovo |
| *Il backup è danneggiato o incompleto: copia di nuovo tutto il testo.* | manca un pezzo o un carattere è cambiato nella copia |
| *Questo backup contiene dati che Accord non può usare (…). Non è cambiato nulla.* | una sua parte non è valida (il token, i personaggi, il main, le impostazioni o i record) |
| *Questo backup è di un altro account. Non è cambiato nulla.* | il token non è quello di questo computer e questo computer conosce personaggi che il backup non elenca |

Spazi e a capo aggiunti dalla copia non contano. Nella modalità demo il backup non c'è, e l'importazione non c'è mentre i dati salvati sono stati scritti da una versione più nuova di Accord (allora sono in sola lettura).
