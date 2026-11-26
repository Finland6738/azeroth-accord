# Disponibilità

*English: [[Availability|Availability]]*

> **Dalla `v0.10.0`**, il prossimo rilascio: è completo nel codice e non ancora pubblicato; nessuna versione precedente lo contiene. Niente di questa pagina è stato controllato nel gioco vero. Quello che segue descrive come dovrebbe funzionare.

La mappa della disponibilità risponde a una domanda: **quando giocano di solito i membri della gilda?** Aiuta a scegliere giorno e ora di un raid o di un evento.

## Che cosa si misura

**Solo il tempo in cui sei online.** Mentre uno dei tuoi personaggi è connesso, Accord conta i minuti, per ora della settimana sull'orologio del reame, nelle ultime **8 settimane**. Contano anche i personaggi del tuo account in altre gilde, o senza gilda: dicono quando giochi.

Non si guarda nient'altro: né dove sei, né che cosa fai, né il tuo gruppo, e **niente sui raid**. Accord non tiene presenze: quelle spettano all'addon di raid o di loot della gilda.

Per ognuna delle 168 ore della settimana il risultato è uno di quattro **livelli**, sulle settimane misurate fin lì (fino a 8). Una settimana conta per un'ora quando sei stato online almeno 10 minuti di quell'ora.

| Livello | Significato |
|---|---|
| mai | nessuna settimana |
| meno di una settimana su quattro | di rado |
| fino a metà delle settimane | a volte |
| più della metà delle settimane | di solito |

Il conteggio parte quando installi la versione con questa vista: nelle prime settimane la mappa dice poco.

## La vista

Si apre dalla sua scheda o con `/accord availability`.

- **Gilda**: una riga per giorno (da lunedì), una colonna per ora. Ogni casella dice quanti membri sono **di solito online** in quell'ora (fino a metà delle settimane, o più), tra quelli che condividono; più è scura, più sono. I membri si contano per account, quindi gli alt sono una persona sola.
- **La mia**: la tua mappa, con i quattro livelli in quattro tonalità (la più chiara è "mai").
- **Clicca una casella** per leggerla sotto la griglia: giorno e ora, il tuo livello, il conteggio e la frequenza.

## Chi vede che cosa

- **Tutti** vedono quanti membri sono online in ogni ora.
- **Chi** sono, Accord lo mostra solo a **ufficiali e Guild Master**, e a ognuno la propria voce. È una regola dell'interfaccia: le mappe arrivano a tutta la gilda.

## La condivisione

**Condividi quando gioco di solito** è **acceso di default**. L'interruttore è nella pagina *Cosa condivido* e nella card dei Contatti delle [[Impostazioni|Settings-it]].

- Acceso: i tuoi 168 livelli e il numero di settimane misurate si mandano alla gilda quando cambiano: al massimo una volta al giorno nella prima settimana, poi **al massimo una volta a settimana**. Una mappa si tiene 30 giorni.
- Spento: la mappa condivisa si **ritira** (la sostituisce un record vuoto) e non si manda più niente. La tua mappa continua a contare sul tuo computer, quindi la vedi ancora in *La mia*.

I minuti contati non lasciano mai il tuo computer: partono solo i livelli. Non fanno parte del [[backup|Settings-it]].

## Con Finland Dragon Credit Points

Quando FDCP è la fonte del roster della season della gilda, gli ufficiali vedono in più, sotto la casella scelta, i membri che hanno **dichiarato** quel giorno in FDCP. È etichettato come dichiarazione per giorni interi, non come misura, e non si somma mai ai conteggi. Vedi [[Addon di raid e di loot|Raid-and-Loot-Addons-it]].
