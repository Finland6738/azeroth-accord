# Gruppi

*English: [[Groups|Groups]]*

> **Novità della `v0.9.0`**. Nulla di questa pagina è stato verificato nel gioco vero; in particolare l'invito mandato dall'addon, anche dentro un'istanza.

La scheda **Gruppi** è il pannello dei gruppi predefiniti del gioco, **solo per la tua gilda**: un capo pubblica un gruppo, i membri si candidano con un ruolo, il capo li accetta e vengono invitati. Si apre con l'icona **Gruppi** della barra di navigazione o con `/accord groups`. Nessuno fuori dalla gilda vede un gruppo, e partecipano solo i membri che usano l'addon.

L'icona **Gruppi** della barra di navigazione ha le pagine **Cercagruppi** (l'elenco), **Pubblica un gruppo**, **Il mio gruppo** e, dalla `v0.13.0`, [**Raduni**](Events-it#raduni-pvp-e-nel-mondo).

## Trovare un gruppo

Ogni riga mostra il tipo, l'attività, i livelli, i ruoli ancora cercati (scudo: tank, croce: healer, spada: DPS), i presenti sui posti, il capo, da quando è pubblicato, il tempo che resta e lo stato. I più recenti sono in cima. Passa il mouse su una riga per la nota e il ritrovo.

Filtri:

- i chip del **tipo**: *Tutti*, oppure *Spedizione, Incursione, Missione, Élite, PvP, Farming, Professioni, Aiuto, Altro*, anche più d'uno;
- **Ogni destinazione** o una di quelle in elenco;
- **Adatti al mio livello**, acceso all'inizio;
- i **ruoli** che la tua classe può fare: scegline uno o più per vedere solo i gruppi che li cercano ancora;
- la casella di ricerca in alto: attività, capo, nota e ritrovo.

I filtri di tipo, livello e ruolo si salvano sul tuo computer.

Un gruppo che si chiude resta in elenco, grigio, per 10 minuti: *Completo*, *Scaduto*, *Capo non in linea*, *Sostituito* o *Chiuso*.

## Candidarsi

Fai clic su una riga. Sotto l'elenco scegli un ruolo, scrivi se vuoi un breve commento (60 caratteri) e premi **Candidati**. Il ruolo è già scelto: quello che hai salvato nel Group Finder del gioco, se il gruppo lo cerca; altrimenti il tuo ruolo nel gruppo attuale; altrimenti il primo che la tua classe può fare.

La candidatura va **in sussurro solo al capo**: nessun altro sa che ti sei candidato. Il riquadro e l'elenco dicono poi *Candidato come healer, in attesa*, quindi *Accettato: aspetta l'invito* oppure *Rifiutato*. **Ritira** toglie una candidatura in attesa. Puoi averne 3 in attesa; dopo un *Rifiutato* aspetti 10 minuti prima di ricandidarti allo stesso gruppo. L'invito è quello del gioco: lo accetti tu.

## Pubblicare un gruppo

Nella pagina **Pubblica un gruppo** scegli:

- il **tipo**; per una spedizione o un'incursione l'istanza (prima quelle per il tuo livello), per gli altri poche parole (una missione, una zona, un campo di battaglia...). Un gruppo di **Aiuto** dice solo la zona, già scritta con quella in cui sei;
- i **livelli**, i **posti**, quanti sono **già nel gruppo** (vuoto: il gruppo attuale) e quanti **tank, healer e DPS** cerchi ancora, non più dei posti liberi;
- una **nota** (80 caratteri) e un **ritrovo** in parole (40): l'addon non condivide mai la tua posizione;
- per quanto il gruppo resta in elenco: 30 minuti, 1, **2** o 4 ore.

Premi **Pubblica**. Hai un solo gruppo aperto per personaggio: se ne hai già uno, il pulsante chiede un secondo clic per chiuderlo e pubblicare il nuovo. Con un gruppo aperto, **Aggiorna** cambia ruoli, presenti, livelli, nota e ritrovo, e **Chiudi il gruppo** lo chiude.

Un gruppo si chiude anche da solo quando non cerca più nessuno o il gruppo è pieno, quando il suo tempo finisce e quando esci dal gioco (un `/reload` non lo chiude).

## Il mio gruppo: le candidature

La pagina **Il mio gruppo** elenca chi si è candidato, con classe, livello, ruolo, commento e da quanto tempo; il numero delle candidature compare sulla scheda. **Accetta** invita il giocatore nel tuo gruppo e toglie uno dal ruolo che ha scelto; **Rifiuta** gli dice di no. L'addon non accetta mai nessuno da solo e non invita mai senza il tuo clic.

- Può invitare solo il capo del gruppo o dell'incursione.
- Con 5 giocatori in un gruppo e più posti nell'annuncio compare *Trasforma prima il gruppo in incursione*: l'addon non lo trasforma mai al posto tuo.

## Anche nel Group Finder del gioco

Se il gioco permette di mettere un gruppo **in privato**, **Il mio gruppo** ha un pulsante **Anche nel cercagruppi del gioco** accanto a *Chiudi il gruppo*. Un tuo clic mette lo stesso gruppo per una spedizione o un'incursione nel Group Finder del gioco come **gruppo privato**: lì lo vede la tua gilda, e anche **i tuoi amici fuori dalla gilda** (lo dice il suggerimento del pulsante). L'addon:

- non mette mai un gruppo **in pubblico**, non scrive né titolo né commento e non mette niente senza il tuo clic;
- offre il pulsante solo al capo (o a chi è da solo), fuori dal combattimento, per una spedizione o un'incursione che il Group Finder del gioco conosce;
- lo toglie nello stesso clic che chiude il gruppo della gilda (*Chiudi il gruppo*, un nuovo annuncio che lo sostituisce, un *Accetta* che lo riempie). Quando il gruppo della gilda si chiude da solo, un avviso ti chiede di toglierlo e il pulsante diventa **Togli dal cercagruppi del gioco**;
- se il gioco mostra il gruppo come pubblico, ti chiede di toglierlo e non offre più il pulsante su quella versione del gioco.

Chi si candida dal Group Finder del gioco si gestisce nella finestra del gioco. Se il gioco non permette gli annunci privati non compare né il pulsante né alcun testo: il cercagruppi della gilda resta l'unico. Se WoW Forever li permetta non è ancora stato controllato nel gioco.

## Avvisi e Centro azioni

Con il [[Centro azioni|Action-Center-it]]:

- ogni candidatura in attesa è una riga **Adesso** della pagina In arrivo, che apre **Il mio gruppo**;
- un avviso ti dice di una nuova candidatura, e della risposta del capo alla tua (di base una riga in chat e un riquadro a schermo);
- l'avviso di un **nuovo gruppo adatto a te** è **spento all'inizio**. Si accende in [[Impostazioni|Settings-it]], scheda **Notifiche**, *Nuovi gruppi adatti ai miei filtri*. Guarda i tipi dei filtri salvati, il tuo livello e i ruoli scelti (o qualunque ruolo che la tua classe può fare), e arriva al massimo una volta ogni 5 minuti. Da spento resta solo nella cronologia, segnato *muto*.

Come ogni avviso, anche questi aspettano durante il combattimento, nelle istanze e nelle ore di quiete.

## Che cosa si condivide

Il gruppo che pubblichi va alla gilda e sparisce 10 minuti dopo la fine; non entra nei backup né nelle esportazioni. Una candidatura va solo al capo e resta sui due computer finché il gruppo non si chiude. Vedi [[Privacy e dati|Privacy-and-Data-it]].
