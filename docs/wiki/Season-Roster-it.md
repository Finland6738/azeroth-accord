# Roster della season

*English: [[Season roster|Season-Roster]]*

> **Dalla `v0.10.0`**: nessuna versione precedente lo contiene. Niente di questa pagina è stato controllato nel gioco vero. Quello che segue descrive come dovrebbe funzionare.

Il roster della season **non è un'iscrizione e non è un registro delle presenze**. Dice che cosa gioca ogni raider per tutta la season, perché il loot segue la specializzazione dichiarata:

- **MS1**, obbligatoria: la tua specializzazione principale, con il suo ruolo (tank, healer, dps in mischia o dps a distanza);
- **MS2**, facoltativa: una seconda specializzazione che accetti di giocare per tutta la season, se il raid ne ha bisogno;
- **OS**, facoltativa: una specializzazione che ti piacerebbe giocare, che il raid non chiederà;
- **una nota**, per esempio quando puoi giocare; oppure **Non ancora sicuro**.

Dichiarare è facoltativo.

## La vista Season

Aprila con la sua scheda o con `/accord season`.

- **In alto**: la **fonte** del roster della season (*Accord* o *FDCP*), la scelta della season e **Apri FDCP** quando Finland Dragon Credit Points è caricato sul tuo computer. La fonte è una sola scelta per tutta la gilda: gli ufficiali e il Guild Master la cambiano con un clic, tutti gli altri la vedono bloccata (vedi [[Addon di raid e di loot|Raid-and-Loot-Addons-it]]).
- **Gli ufficiali e il Guild Master** scrivono un nome e premono **Apri season**: la season comincia oggi, e quella aperta fino ad allora si chiude. **Chiudi season** chiude quella corrente senza aprirne un'altra. Nessun altro apre o chiude una season.
- **La tua dichiarazione**: scegli MS1 e il suo ruolo, MS2 e OS (o *nessuna*), scrivi una nota se vuoi e premi **Dichiara**; oppure premi **Non ancora sicuro**. Un secondo clic conferma, perché la dichiarazione vale per tutta la season.
- **L'elenco**: una tabella con tutte le dichiarazioni della season scelta: nome, classe, MS1, MS2, OS e la nota. Clicca il titolo di una colonna per ordinarla; anche i conteggi per ruolo sono una tabella.

## Ruoli, mancanze e chi non ha dichiarato

Per la season corrente, tutti vedono sopra l'elenco:

- **Ruoli secondo MS1**: quanti raider sono tank, cure, dps in mischia e a distanza, e accanto quanti **ne aggiungerebbe MS2** (raider con MS2 in quel ruolo e MS1 in un altro). OS non conta mai.
- **Mancanze**: quando gli ufficiali hanno impostato una composizione obiettivo, quanti **ne mancano** per ogni ruolo e quanti di questi coprirebbe MS2. Ogni ruolo si conta da sé: un raider che passa a MS2 lascia il ruolo di MS1.
- Le risposte **Non ancora sicuro** sono elencate a parte e non contano in nessun ruolo.
- **Senza dichiarazione**: sotto l'elenco, i membri che non hanno dichiarato, un nome per account (un account che ha dichiarato con un personaggio non compare per i suoi alt). Non contano mai come mancanza, con o senza Accord.

Una season vecchia, scelta nel menu, mostra solo le sue dichiarazioni, senza conteggi.

## La composizione obiettivo

Gli ufficiali e il Guild Master scelgono la dimensione del raid (10, 20, 25 o 40), scrivono quanti tank, cure, dps in mischia e a distanza vogliono (un campo vuoto vale 0; la somma non può superare la dimensione) e premono **Imposta**. L'obiettivo è uno per tutta la gilda, arriva a ogni membro e resta finché un ufficiale non lo cambia, anche con FDCP come fonte.

## Esportazione

Gli ufficiali e il Guild Master premono **Esporta** per avere le dichiarazioni della season mostrata in **CSV** (per un foglio di calcolo) o come testo per **Discord** (quelli lunghi sono divisi in più messaggi). Il testo è già selezionato: premi Ctrl+C. Esce dal gioco, come dice l'avviso sopra. Chi non ha dichiarato non è nell'esportazione.

## Testo di reclutamento

> **Novità della `v0.12.0`**. Niente di questa parte è stato controllato nel gioco vero.

Gli ufficiali e il Guild Master premono **Testo di reclutamento** nella vista Season, oppure scrivono `/accord recruit`, e ottengono un annuncio costruito con ciò che la gilda ha già:

- il nome della gilda, la fazione e il reame;
- una descrizione: il primo paragrafo sotto la prima intestazione della pagina **Informazioni sulla gilda** del manuale (vedi [[Manuale di gilda|Guild-Handbook-it]]), quando chi scrive il manuale ha salvato la pagina;
- **Cerchiamo**: i ruoli che mancano secondo MS1 rispetto alla composizione obiettivo, dal roster della season di Accord o dal pool di FDCP. Quello che MS2 coprirebbe si cerca comunque;
- una **riga in più** che puoi scrivere (per esempio gli orari dei raid) e un **contatto**: *Sussurra a <il tuo personaggio>*, oppure un testo tuo. Queste due righe restano sul tuo computer.

Scegli **Riga di chat** (una sola riga di al massimo 255 byte: si accorcia prima la descrizione, poi la riga in più) o **Discord** (più righe, al massimo 1900 caratteri). Il testo è selezionato: premi **Ctrl+C** e pubblicalo tu. **Accord non lo pubblica mai**, in nessun canale. La finestra dice perché una parte manca (nessuna season aperta, nessuna composizione obiettivo, nessuna mancanza, nessun paragrafo in *Informazioni sulla gilda*) e riscrive il testo quando cambiano la season, l'obiettivo, la fonte o la pagina.

## Le regole

- **Solo la tua voce.** Ogni raider scrive solo la propria dichiarazione. Nessuno scrive o cambia quella di un altro, ufficiali compresi; una dichiarazione falsificata per un altro giocatore è rifiutata da ogni Accord.
- **Bloccata per la season.** Per **30 minuti** dopo la prima dichiarazione puoi correggere un errore. Poi MS1, MS2 e OS restano bloccate fino alla prossima season. La **nota** si può sempre cambiare (*Salva la nota*). *Non ancora sicuro* può diventare una vera dichiarazione **una volta**.
- **Un personaggio per account.** Il tuo account dichiara un personaggio per season. Se alla gilda arrivano le dichiarazioni di due tuoi personaggi, tutti vedono la più vecchia.
- **Una nuova season parte vuota.** Niente si copia dalla season precedente. **Le season vecchie restano leggibili** nella scelta della season: si tengono quella corrente e le 3 precedenti.
- **Condivisa con la gilda.** Season e dichiarazioni arrivano a ogni membro con Accord, come gli altri dati della gilda, e la tua dichiarazione è elencata in *Cosa condivido* (vedi [[Privacy e dati|Privacy-and-Data-it]]).

## Con FDCP come fonte

Quando gli ufficiali scelgono **FDCP** per il roster della season, Accord non chiede dichiarazioni e non ne accetta da te: dichiari in FDCP. La vista mostra la season e il pool di FDCP, letti dalla sua interfaccia pubblica, oppure perché non c'è niente e il pulsante **Apri FDCP**. Conteggi, mancanze, l'elenco di chi non ha dichiarato e l'esportazione vengono allora dal pool di FDCP: i suoi main **inattivi** non si contano, un main vale anche per i suoi alt e, poiché FDCP mostra MS2 e OS solo agli ufficiali, un membro vede i conteggi per MS1 senza la copertura di MS2. Le dichiarazioni già tenute in Accord sono nascoste, non cancellate: se gli ufficiali tornano ad Accord ricompaiono.

In fondo, **Addon di raid e di loot nella gilda** mostra quali di questi addon hanno i membri, come spiegato in [[Addon di raid e di loot|Raid-and-Loot-Addons-it]].
