# Addon di raid e di loot

*English: [[Raid and loot addons|Raid-and-Loot-Addons]]*

> **Non ancora in un rilascio.** Niente di questa pagina è disponibile in una versione rilasciata, `v0.9.0` compresa: nessuna vista **Raid**, nessun `/accord raid`, nessun *Loot (FDCP)* nella scheda del membro, nessun riconoscimento di altri addon. Il riconoscimento (passo M10.2) e la lettura di Finland Dragon Credit Points (passo M11.7) sono nel codice, spenti finché le milestone M10 e M11 non sono complete. Niente è stato provato nel gioco vero. Quello che segue descrive come funzionerà.

Accord **non ha un motore del loot né le presenze**. Quei dati li tengono gli addon di raid e di loot della tua gilda, e Accord lavora **con** loro, mai contro:

- **Una fonte per ogni dato.** Il roster della season (MS1, MS2, OS) con la formazione e la panchina appartiene a un solo addon per tutta la gilda, e così i dati del loot (i crediti e il posto in coda di un membro, le regole del loot). Gli **ufficiali** scelgono quella fonte una volta per la gilda, e l'Accord di ogni membro segue la stessa scelta. Finché non scelgono, il roster della season è quello di Accord e non c'è una fonte del loot.
- **Solo lettura.** Accord non scrive mai i dati di un altro addon, non legge mai i suoi file salvati e non lo carica, accende o spegne mai.

## Gli addon che Accord conosce

| Addon | Tipo | Cosa fa Accord |
|---|---|---|
| **Finland Dragon Credit Points** (FDCP) | loot e roster del raid | lo riconosce; lo legge dalla sua API pubblica (livello 1) |
| Gargul, RaidCore, WLC, Forever Loot Manager, NostalgiaForeverLC, RollForMe | loot | lo riconosce (livello 0) |

I nomi delle cartelle degli addon diversi da FDCP vengono dalle loro pagine pubbliche e si confermano nel gioco prima di fidarsene. Gli addon di gestione della gilda che non riguardano il loot o il roster del raid sono lasciati fuori di proposito.

## Livelli

- **Livello 0, riconoscimento.** Accord vede che l'addon è caricato sul tuo computer, e la sua versione.
- **Livello 1, lettura.** Accord legge ciò che l'addon pubblica per gli altri addon. Solo FDCP pubblica un'interfaccia del genere (`FinlandDragonCreditPointsAPI`), e Accord la legge solo quando la sua versione è una che Accord conosce (la versione 1). Con un'altra versione Accord torna al livello 0 e niente si rompe: aggiorna Accord.
- Non c'è un livello 2: Accord non manda mai niente a un altro addon.

`/accord debug` ha una sezione **Integrations** con ciò che è stato trovato sul tuo computer e una sezione **FDCP** con lo stato delle notifiche (senza nomi). Quali di questi addon hanno gli *altri* membri viene dall'elenco [[Addon della gilda|Guild-Addons-it]] (`v0.9.0`): la vista Raid lo mostra (sotto).

## La vista Raid

Si apre con la sua scheda o con `/accord raid`.

- **In alto, le fonti della gilda**: *Roster della season* (Accord o FDCP) e *Loot* (Nessuno o FDCP). Gli ufficiali e il Maestro di gilda le cambiano con un clic, e la scelta arriva a ogni membro con Accord. I membri vedono la stessa scelta, bloccata. **Apri FDCP** apre la finestra di FDCP finché FDCP è caricato sul tuo computer.
- **Lo stato di FDCP**: la sua versione e da dove vengono i suoi dati sul tuo computer, o perché non c'è niente: FDCP non installato o spento, una versione della sua interfaccia che questo Accord non conosce, FDCP che sta ancora leggendo il roster della gilda, o nessun dato della season per ora.
- **Roster della season**: la season e il suo pool, una riga per main con classe, ruolo, MS1, MS2 e OS, e *in prova* o *inattivo*.
- **Formazione e panchina**: la serata di raid aperta in FDCP, con chi è nel raid e chi è in panchina.
- **Loot**: i tuoi crediti e il tuo posto nella coda del loot, e un **riassunto in sola lettura delle regole del loot di FDCP** (preset, priorità, crediti all'inizio, come si assegnano gli oggetti, il costo per qualità dell'oggetto, i moltiplicatori delle risposte, chi entra tardi, la panchina). Le regole si cambiano in FDCP, mai in Accord. La pagina del loot del manuale di gilda mostrerà lo stesso riassunto accanto al suo testo (M11).

- **Addon di raid e di loot in gilda**, in fondo: per ogni addon della tabella qui sopra, che cosa Accord ha trovato sul tuo computer (caricato, spento, installato o non installato, la versione, livello 0 o 1, e se il nome della sua cartella è già confermato) e, dall'elenco [[Addon della gilda|Guild-Addons-it]], quanti membri che condividono l'elenco dei propri addon lo hanno caricato, su quanti, con le versioni. **Gli ufficiali e il Maestro di gilda** vedono anche chi lo ha, con la versione e i personaggi; tutti gli altri vedono i conteggi e la propria voce. Se l'elenco degli addon è spento, nessuno condivide ancora un elenco, o tu non condividi il tuo, una riga lo dice.

Con **Accord** come fonte del roster della season, la vista dice che le dichiarazioni di Accord arrivano con una versione successiva (M10).

## Sulla scheda del membro

Con FDCP scelto per il loot, la scheda del membro ha una sezione **Loot (FDCP)**: i crediti del membro e il suo posto nella coda del loot, come li mostra FDCP. Un alt mostra i crediti del suo main. Un main inattivo ha i crediti ma non il posto.

## Client degli ufficiali e dei membri

FDCP non dà gli stessi dati a ogni client, e Accord lo dice invece di mostrare elenchi vuoti:

| | Client di un ufficiale | Client di un membro |
|---|---|---|
| Season e pool | ogni main, con MS1, MS2 e OS | i main che giocano, solo con MS1 |
| Formazione e panchina | la serata aperta | non sui client dei membri |
| Crediti e posto | sì | sì, dalla tabella mandata da un ufficiale |
| Regole del loot | le regole della gilda | i valori predefiniti del preset Patto di FDCP (le regole della gilda sono sui client degli ufficiali) |

**Le presenze non si mostrano mai**: FDCP le tiene per i suoi ufficiali e non le condivide con altri addon, e Accord non conta nessuna presenza ai raid. Accord non salva e non manda niente di ciò che legge da FDCP.
