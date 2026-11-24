# Banca di gilda

*English: [[Guild Bank|Guild-Bank]]*

> Disponibile dalla versione della banca (`v0.5.0`). L'addon non è ancora stato provato nel gioco vero: le prime prove sono con la gilda del proprietario (la prova nel gioco è [docs/checklists/M5.md](https://github.com/Finland6738/azeroth-accord/blob/main/docs/checklists/M5.md), in inglese).

- Il gioco mostra la banca solo alla cassaforte. Ogni volta che un compagno con l'addon la apre, l'addon salva cosa contiene ogni scheda e lo condivide, quindi la vista **Banca** funziona ovunque. Ogni scheda mostra quanto è vecchio il suo contenuto.
- Le schede che il tuo grado non può vedere nel gioco restano nascoste anche nell'addon.
- **Registri e donazioni**: depositi e prelievi si raccolgono nel tempo; l'elenco delle donazioni mostra chi ha aiutato la gilda negli ultimi 30 giorni, nell'ultimo anno e in totale.
- **Richieste**: chiedi un oggetto o dell'oro (*Prelievo*), offri un oggetto (*Deposito*) o prometti una *Donazione*. Gli ufficiali approvano o rifiutano e la segnano come consegnata; la consegna avviene nel gioco (posta, scambio o cassaforte).

## Chi vede cosa

- Ciò che vedi alla cassaforte è condiviso con la gilda, così un compagno che non va mai alla cassaforte lo vede lo stesso, vecchio quanto la tua visita.
- Il gioco non dice all'addon quali gradi possono vedere una scheda, solo se *il tuo* grado può. Quindi una scheda che leggi è mostrata ai membri del tuo grado e superiori. Una scheda letta da un **ufficiale** è condivisa solo con gli ufficiali (sul canale degli ufficiali) e non arriva mai ai computer dei membri. Se tutti i gradi possono vedere una scheda ma solo gli ufficiali hanno aperto la cassaforte, i membri vedono quella scheda quando l'ha aperta anche un membro.

## La vista Banca

![Banca, Schede: la scheda come la disegna il gioco, il denaro della gilda e quanto è vecchia l'istantanea](../specs/mockups/previews/bank-tabs.webp)

![Banca, Oggetti: ogni oggetto una volta con il suo totale e dove si trova](../specs/mockups/previews/bank-items.webp)

Aprila con la scheda **Banca** del pannello o con `/accord bank`. Le modalità (Schede, Oggetti, In arrivo per gli ufficiali, Richieste, Registro, Donazioni, Denaro) sono i pulsanti in alto nella vista.

- **Schede**: un pulsante per ogni scheda che puoi vedere, il denaro della gilda e quanto è vecchio, e la scheda disposta come nel gioco (14 colonne di 7 slot). Sotto i pulsanti delle schede leggi *vista 2 h fa da Bob*: l'età del contenuto e il compagno il cui addon l'ha letto. Passa il mouse su un oggetto per il suo suggerimento.
- **Oggetti**: una riga per oggetto su tutte le schede che puoi vedere, con il totale e dove si trova. La casella di ricerca del pannello filtra per nome dell'oggetto, numero dell'oggetto o nome della scheda.
- Quando non c'è ancora nulla da mostrare, la vista lo dice: qualcuno deve aprire la cassaforte una volta.

## Registri, donazioni e denaro

- **Registro**: chi ha depositato o prelevato cosa, dal più recente. Il gioco tiene solo una breve storia e la mostra solo alla cassaforte; l'addon aggiunge alla storia ogni visita di un compagno con l'addon, senza elencare due volte lo stesso evento, così cresce oltre quella del gioco. Cerca per nome o oggetto.
- **Donazioni**: cosa ha depositato ogni giocatore (oro e oggetti) negli ultimi 30 giorni, negli ultimi 365 giorni o da sempre (i pulsanti in alto scelgono il periodo e l'ordine, per oro o per oggetti), tutti i personaggi di un giocatore insieme. Prelievi e riparazioni non contano. L'elenco è visibile a ogni membro (il proprietario può limitarlo agli ufficiali).
- **Denaro**: come è cambiato il denaro della gilda negli ultimi 30 giorni, da ciò che gli addon hanno visto.

![Banca, Registro: il registro della banca unito senza doppioni](../specs/mockups/previews/bank-log.webp)

![Banca, Donazioni: i depositi per giocatore in 30 giorni, 365 giorni o da sempre](../specs/mockups/previews/bank-donations.webp)

![Banca, Denaro: il denaro della gilda negli ultimi 30 giorni](../specs/mockups/previews/bank-money.webp)

## Richieste

![Banca, Richieste: il modulo e ogni richiesta della gilda con il suo stato](../specs/mockups/previews/bank-requests.webp)

![La vista Richieste con note numerate](../specs/mockups/img/03-bank-requests.webp)

Nella modalità **Richieste** della vista Banca puoi:

- **Prelievo**: chiedere un oggetto dalla banca, o dell'oro; **Deposito**: offrire un oggetto; **Donazione**: promettere oggetti o oro. Incolla il link di un oggetto (o scrivi il suo numero) nella casella dell'oggetto, o lasciala vuota per l'oro; aggiungi quanti (o quante monete d'oro) e un motivo, poi premi *Invia richiesta*. Puoi avere cinque richieste aperte alla volta. I chip *Solo le mie* e *Mostra anche le chiuse* sotto il modulo filtrano l'elenco.
- Ogni compagno vede ogni richiesta. Puoi **annullare** la tua finché è ancora aperta.
- Gli **ufficiali** rispondono con *Approva*, *Rifiuta* (la casella del motivo diventa il motivo del rifiuto) e *Consegnata*. Passa il mouse su una riga per leggere la sua storia. Solo gli ufficiali possono cambiare lo stato di una richiesta: gli altri addon ignorano qualsiasi altra cosa.
- L'addon non sposta mai oggetti o oro: dopo un'approvazione l'oggetto ti arriva per posta, scambio o alla cassaforte, come decidono gli ufficiali.

## Per gli ufficiali: la casella e gli avvisi

![Banca, In arrivo: le richieste che aspettano un ufficiale, il contatore sulla scheda e una riga in chat per ogni nuova richiesta](../specs/mockups/previews/bank-inbox.webp)

*Anteprime di progetto, non screenshot: sono disegnate dal layout e dai testi dell'addon (qui in inglese), con personaggi e oggetti inventati, perché l'addon non è ancora stato provato nel gioco ([tutte le anteprime](https://github.com/Finland6738/azeroth-accord/blob/main/docs/specs/mockups/previews/README.md), anche in italiano).*

- Un segno rotondo con un numero, nel colore d'accento del tema, compare sulla scheda Accord della finestra della gilda (e come distintivo sulla scheda Banca del pannello) quando ci sono richieste che aspettano te. I membri non lo vedono mai.
- La modalità **In arrivo** elenca ciò che aspetta un ufficiale, dalla più vecchia: le richieste aperte da approvare o rifiutare, quelle approvate da segnare come *Consegnata*. Quando il registro della banca mostra il movimento corrispondente (chi ha chiesto ha tolto l'oggetto, o l'ha depositato, o l'oro), la riga dice *Sembra consegnata*; la segni comunque tu, perché la consegna resta manuale.
- Ricevi una riga in chat quando arriva una nuova richiesta; chi ha chiesto ne riceve una quando approvi, rifiuti o consegni. Gli avvisi non si ripetono mai dopo un ricaricamento, e la prima volta che l'addon gira non annuncia le richieste che esistono già.
