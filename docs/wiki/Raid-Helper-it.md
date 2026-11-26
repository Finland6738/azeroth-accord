# Eventi di Raid-Helper

*English: [[Raid-Helper events|Raid-Helper]]*

> **Dalla `v0.10.0`**, il prossimo rilascio: è completo nel codice e non ancora pubblicato; nessuna versione precedente lo contiene. Niente di questa pagina è stato controllato nel gioco vero, e l'esportazione di Raid-Helper non è ancora stata provata con un evento reale. Quello che segue descrive come dovrebbe funzionare.

Molte gilde raccolgono le iscrizioni ai raid con il bot **Raid-Helper** su Discord. Accord può portare nel gioco un evento di questo tipo: un ufficiale copia l'esportazione dell'evento e la incolla. Accord **non contatta mai Discord né Raid-Helper**: un addon non ha accesso a internet, e dal tuo computer non parte niente verso di loro.

## 1. Copiare l'esportazione

- **JSON** (consigliato): apri `https://raid-helper.xyz/api/v4/events/<id dell'evento>` nel browser, seleziona tutto il testo e copialo. L'id dell'evento è l'id del messaggio dell'evento su Discord.
- **CSV**: copia l'esportazione CSV dell'evento da Raid-Helper. La prima riga deve nominare le colonne: un nome (`Name`, `Discord name` o `User`) e almeno una tra classe, ruolo o stato.

## 2. Incollarla in Accord

Solo ufficiali e Guild Master. Nella vista **Eventi** (`/accord events`, vedi [[Eventi|Events-it]]) premi **Importa da Raid-Helper**, incolla con `Ctrl+V` e premi **Controlla**.

Accord dice che cosa ha letto: il titolo, la data e l'ora, quanti membri ha abbinato e quali nomi non corrispondono a nessuno. Poi premi **Importa**.

- Un CSV non ha titolo né data: scrivili nei due campi della casella (la data come `AAAA-MM-GG HH:MM`, nell'ora del reame). Gli stessi campi sostituiscono quelli di un'esportazione JSON, se devi correggerli.
- L'ora di un'esportazione JSON viene trasformata nell'**ora del reame**. Controllala, soprattutto intorno al passaggio all'ora legale o solare.
- Un testo che non è un'esportazione di Raid-Helper, che è tagliato o troppo grande (oltre 200 KB o 200 iscrizioni) viene rifiutato con un messaggio. Accord legge soltanto il testo: non esegue mai niente di ciò che contiene.
- Importare di nuovo lo stesso evento sostituisce l'importazione precedente.

| In Raid-Helper | In Accord |
|---|---|
| Iscritto con una classe | Iscritto |
| Late | In ritardo (conta come iscritto) |
| Bench, o in coda di attesa | Panchina (conta come iscritto) |
| Tentative | Forse |
| Absence | Assenza |

## 3. Abbinare i nomi ai membri

Ogni iscrizione viene abbinata a un membro della gilda, in quest'ordine:

1. un abbinamento che hai già fatto a mano;
2. il **nome Discord** nei contatti del membro (quello che mostra il gioco, o quello scritto nelle impostazioni);
3. un nome di personaggio della gilda uguale al nome Discord.

Maiuscole, una `@` iniziale e un `#0000` finale non contano. Tutti i personaggi di un giocatore contano come uno: l'iscrizione va al personaggio della classe con cui si è iscritto, altrimenti a quello della sua dichiarazione della season, altrimenti al suo personaggio principale. Un nome che vale per due giocatori non viene abbinato a nessuno.

Raid-Helper mostra il **soprannome sul server Discord**, che può essere diverso dal nome scritto in Accord. Sotto **Non abbinati a un membro** scegli il nome, scrivi il nome del personaggio del membro e premi **Abbina**. Accord lo ricorda per gli eventi successivi. Se hai ricaricato il gioco dopo l'importazione, incolla di nuovo l'esportazione per aggiungere l'iscrizione.

## 4. Che cosa vede la gilda

- **Ogni membro** vede il proprio stato su Discord (iscritto, in ritardo, panchina, forse o assenza).
- **Gli ufficiali** vedono anche tutte le iscrizioni abbinate, i ruoli accanto al [[roster della season|Season-Roster-it]] e alla composizione obiettivo, chi si è iscritto su Discord ma non nel calendario del gioco, chi si è iscritto nel calendario del gioco ma non su Discord, e chi ha risposto in modo diverso. Scegli l'evento per leggere le risposte del calendario del gioco.

## 5. Metterlo nel calendario del gioco

L'importazione **non scrive niente** nel calendario. Per farlo premi **Metti nel calendario del gioco**, leggi che cosa succederà e premi **Conferma**. Allora Accord:

- usa il tuo evento di gilda a quella data e ora, oppure crea un evento di iscrizione di gilda;
- invita i membri abbinati e ne scrive lo stato (iscritto, in ritardo e panchina come confermato; forse; assenza come rifiutato);
- **non cambia mai una risposta che un membro ha già dato nel gioco**: vale quella del gioco, e la vista mostra la differenza;
- scrive una cosa alla volta, al massimo **40 membri per conferma** (conferma di nuovo per gli altri), e si ferma al primo errore dicendo chi è rimasto fuori.

Il gioco potrebbe non permettere a un addon o al tuo grado di scrivere lo stato degli altri, di mandare inviti o di creare l'evento: su WoW Forever non è ancora stato controllato. Dove Accord non può scrivere uno stato, il membro trova nel [[Centro azioni|Action-Center-it]] una riga *Rispondi nel calendario del gioco*, e risponde lì. Se Accord non può creare l'evento, crealo nel calendario del gioco alla stessa data e ora e conferma di nuovo.

Tieni chiusa la finestra del calendario del gioco mentre Accord scrive. Se quel giorno c'è già un altro evento raid, la conferma te lo dice: Finland Dragon Credit Points collega il primo evento raid del giorno.

## 6. Ritorno su Discord

**Esporta** dà agli ufficiali le iscrizioni dell'evento (nome, classe, ruolo, risposta nel gioco, stato su Discord, e *Raid* o *Panchina* quando l'evento ha una composizione: vedi [[Eventi|Events-it]]) come testo per Discord o come CSV, da copiare e incollare.

## Che cosa viene condiviso

- La gilda riceve il titolo, la data e **solo i membri abbinati** (personaggio, stato, ruolo, classe e specializzazione). Li mandano gli ufficiali; si cancellano 2 giorni dopo l'evento.
- I **nomi non abbinati** e i tuoi **abbinamenti a mano** restano sul tuo computer e non vengono mai mandati. I nomi non abbinati si cancellano 2 giorni dopo l'evento; un abbinamento a mano si cancella quando quel personaggio lascia la gilda.
- Il testo incollato non viene salvato.
- Niente di tutto questo registra chi era a un raid.
