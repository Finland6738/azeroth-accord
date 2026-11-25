# Centro azioni

*English: [[Action Center|Action-Center]]*

> **Non ancora in un rilascio.** Il Centro azioni (passo M9.2) è nel codice, spento finché la milestone M9 non è completa: arriva con la `v0.9.0`. Nulla di questa pagina è stato verificato nel gioco vero.

Il **Centro azioni** è un solo elenco delle cose che **ti aspettano**: non serve guardare ogni vista per trovarle. Si apre con la sua scheda, la prima del pannello Accord, o con `/accord inbox`.

Non salva nulla di suo e non decide niente al posto tuo. Ogni riga viene letta dalla vista a cui appartiene: **fai clic** per aprire quella vista e agire lì. Quando la cosa è fatta, la riga sparisce.

## Che cosa compare

| Riga | Chi la vede | Il clic apre | Sparisce quando |
|---|---|---|---|
| *Richiesta in banca: …* e *Da consegnare: …* | ufficiali e Guild Master | la casella **In arrivo** della [[Banca di gilda|Guild-Bank-it]], su quella richiesta | la richiesta è decisa, consegnata, annullata o scade |
| *In attesa di un ufficiale: …* e *Approvata: …* | tu, per le tue richieste | le tue richieste nella vista Banca | la richiesta è chiusa |
| *Hai chiesto a … di creare …* | tu, dopo **Chiedi di crearlo** | l'elenco delle ricette di quel membro | premi **Fatto**, o dopo 7 giorni |
| *3 promozioni da fare nel gioco* (anche retrocessioni, rimozioni e note) | ufficiali e Guild Master | la pagina **Coda** della [[scheda Ufficiali|Guild-Roster-it]] | in coda non resta nulla di quel tipo |
| *Rientro di … (assente fino al …)* | ufficiali e Guild Master, dal giorno del rientro ai tre giorni dopo | la pagina **Inattivi** | tre giorni dopo il rientro |
| *La tua assenza finisce il …* | tu, nei tre giorni prima della fine | la card **Assenza** delle [[Impostazioni|Settings-it]] | dopo il rientro |

Un ufficiale che chiede qualcosa alla banca vede la richiesta due volte: da decidere, e come proprio promemoria.

Una richiesta di creazione è solo un sussurro che invii tu (vedi [[Professioni e ricette|Professions-and-Recipes-it]]): l'addon non avvisa l'artigiano. La riga è un **promemoria tuo**, tenuto sul tuo computer e mai inviato a nessuno, al massimo 20. Resta anche se decidi di non inviare il sussurro: premi **Fatto** per toglierlo. Gli ordini visibili all'artigiano arrivano con una milestone successiva (M13).

## Ordine e colori

Ogni riga ha un pallino colorato per l'urgenza:

- **Adesso** (rosso): qualcuno ti aspetta ora, o la cosa scade entro un giorno. Nessuna riga lo usa ancora: i primi saranno i candidati al tuo gruppo, in un passo successivo di M9;
- **Da fare** (colore del tema): tocca a te;
- **Promemoria** (grigio): aspetti gli altri, o è solo da ricordare.

Prima le più urgenti; a parità, ciò che aspetta da più tempo. Il numero sulla scheda conta le righe **Adesso** e **Da fare**, e il tooltip dell'addon nel Compartimento AddOn dice *Centro azioni: N da fare*.

I filtri in alto mostrano **Tutto** o un solo tipo: *Banca*, *Creazioni*, *Ufficiali e assenze*. Quando un tipo ha più di 50 righe, un'ultima riga dice *e altre N*; l'elenco ne tiene al massimo 200. Se non c'è nulla dice *Non c'è niente in attesa.*

## Non ancora qui

La cronologia degli avvisi, le ore di quiete e il riepilogo all'accesso sono i prossimi passi di M9.
