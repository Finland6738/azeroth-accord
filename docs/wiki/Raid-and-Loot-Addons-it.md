# Addon di raid e di loot

*English: [[Raid and loot addons|Raid-and-Loot-Addons]]*

> **In parte dalla `v0.10.0`**: il riconoscimento degli altri addon, la scelta della fonte del roster della season e la sezione *Addon di raid e di loot nella gilda* (passo M10.2), nella vista [[Season|Season-Roster-it]]. La vista **Raid**, `/accord raid`, *Loot (FDCP)* nella scheda del membro (passo M11.7) e la **pagina del loot** con la scelta dell'addon del loot della gilda (passo M11.6) sono nel codice ma **nascoste** finché la milestone M11 non è completa. Niente è stato provato nel gioco vero. Quello che segue descrive come dovrebbe funzionare.

Accord **non ha un motore del loot né le presenze**. Quei dati li tengono gli addon di raid e di loot della tua gilda, e Accord lavora **con** loro, mai contro:

- **Una fonte per ogni dato.** Il roster della season (MS1, MS2, OS) con la formazione e la panchina appartiene a un solo addon per tutta la gilda, e così i dati del loot (i crediti e il posto in coda di un membro, le regole del loot). Gli **ufficiali** scelgono una volta per la gilda, e l'Accord di ogni membro segue la stessa scelta. Finché non scelgono, il roster della season è quello di Accord e non c'è un addon del loot.
- **Solo lettura.** Accord non scrive mai i dati di un altro addon, non legge mai i suoi file salvati e non lo carica, accende o spegne mai.

## Gli addon che Accord conosce

| Addon | Tipo | Cosa fa Accord |
|---|---|---|
| **Finland Dragon Credit Points** (FDCP) | loot e roster del raid | lo riconosce; lo legge dalla sua API pubblica (livello 1) |
| Gargul, RaidCore, TLC - Loot Council, WLC, Forever Loot Manager, NostalgiaForeverLC, RollForMe | loot | lo riconosce (livello 0) |
| Qualunque altro addon di loot su CurseForge | loot | lo riconosce dalla cartella scritta da un ufficiale (livello 0) |

I nomi delle cartelle degli addon diversi da FDCP vengono dalle loro pagine pubbliche e si confermano nel gioco prima di fidarsene. Gli addon di gestione della gilda che non riguardano il loot o il roster del raid sono lasciati fuori di proposito.

## Livelli

- **Livello 0, riconoscimento.** Accord vede che l'addon è caricato sul tuo computer, e la sua versione.
- **Livello 1, lettura.** Accord legge ciò che l'addon pubblica per gli altri addon. Solo FDCP pubblica un'interfaccia del genere (`FinlandDragonCreditPointsAPI`), e Accord la legge solo quando la sua versione è una che Accord conosce (la versione 1). Con un'altra versione Accord torna al livello 0 e niente si rompe: aggiorna Accord.
- Non c'è un livello 2: Accord non manda mai niente a un altro addon.

`/accord debug` ha una sezione **Integrations** con ciò che è stato trovato sul tuo computer e una sezione **FDCP** con lo stato delle notifiche (senza nomi). Quali di questi addon hanno gli *altri* membri viene dall'elenco [[Addon della gilda|Guild-Addons-it]] (`v0.9.0`): lo mostra la vista [[Season|Season-Roster-it]] (e la vista Raid, sotto).

## La pagina del loot

La pagina **Gestione del loot** del [[manuale di gilda|Guild-Handbook-it]] mostra, sopra il testo di chi scrive, la scelta del loot della gilda. Accord il loot lo descrive e non lo calcola mai.

- **Sistema di loot**: tiri (MS/OS), soft reserve, loot council, DKP, crediti, o un altro con un nome vostro.
- **Addon del loot**: uno degli addon del loot qui sopra, oppure **Altro (da CurseForge)**: qualunque addon di loot pubblicato su CurseForge, con il nome, il nome della **cartella** (quella in `Interface/AddOns`) e l'indirizzo CurseForge. Si accetta solo un indirizzo `https://` su curseforge.com.
- **Gli ufficiali e il Maestro di gilda** li cambiano con **Cambia** e **Salva**. Scegliendo FDCP Accord legge anche i dati del loot di FDCP; scegliendo un altro addon o nessuno smette di farlo. È una scelta sola.
- **Su questo client**: caricato (con la versione), non caricato, non installato, o *cartella non confermata* (Accord non ha ancora visto quel nome di cartella nel gioco).
- **Download**: l'indirizzo, in una casella da copiare con Ctrl+C, se non hai l'addon caricato (chi scrive lo vede sempre). Installa addon solo da fonti di cui ti fidi.
- **Chi ce l'ha**, dall'elenco [[Addon della gilda|Guild-Addons-it]]: tutti vedono quanti membri che condividono l'elenco lo hanno caricato, con le versioni, e la propria riga. **Gli ufficiali e il Maestro di gilda** vedono anche chi lo ha, chi non ce l'ha e quanti non condividono l'elenco o non usano Accord (mai contati come mancanti). Se l'elenco è spento o nessuno lo condivide, una riga lo dice.
- **Senza addon scelto**, la pagina non mostra nulla sugli addon e non si controlla niente. Chi scrive vede il suggerimento di FDCP con il suo indirizzo, e gli ufficiali **Scegli FDCP** e **Scegli un addon del loot**.
- **Con FDCP**: i tuoi crediti e il tuo posto nella coda del loot, e un **riassunto in sola lettura delle regole del loot di FDCP**, letto da FDCP ogni volta e mai copiato nella pagina. **Apri FDCP** apre la sua finestra.

La ricerca del manuale trova anche i nomi del sistema e dell'addon del loot. Finché la pagina del loot non si può leggere (nessuno l'ha creata, è stata eliminata, o è ancora un modello e non sei tra chi scrive), **Pagina del loot** nella vista Raid mostra la stessa parte lì.

## La vista Raid

Si apre con la sua scheda o con `/accord raid`.

- **In alto**: la fonte del *Roster della season* (Accord o FDCP), che gli ufficiali e il Maestro di gilda cambiano con un clic e i membri vedono bloccata, e l'addon del loot della gilda con il pulsante **Pagina del loot**. **Apri FDCP** apre la finestra di FDCP finché FDCP è caricato sul tuo computer.
- **Lo stato di FDCP**: la sua versione e da dove vengono i suoi dati sul tuo computer, o perché non c'è niente: FDCP non installato o spento, una versione della sua interfaccia che questo Accord non conosce, FDCP che sta ancora leggendo il roster della gilda, o nessun dato della season per ora.
- **Roster della season**: la season e il suo pool, una riga per main con classe, ruolo, MS1, MS2 e OS, e *in prova* o *inattivo*.
- **Formazione e panchina**: la serata di raid aperta in FDCP, con chi è nel raid e chi è in panchina.
- **Loot**: con FDCP, i tuoi crediti e il tuo posto nella coda del loot. Il riassunto delle regole del loot di FDCP (preset, priorità, crediti all'inizio, come si assegnano gli oggetti, il costo per qualità dell'oggetto, i moltiplicatori delle risposte, chi entra tardi, la panchina) è nella pagina del loot. Le regole si cambiano in FDCP, mai in Accord.

- **Addon di raid e di loot in gilda**, in fondo: per ogni addon della tabella qui sopra, che cosa Accord ha trovato sul tuo computer (caricato, spento, installato o non installato, la versione, livello 0 o 1, e se il nome della sua cartella è già confermato) e, dall'elenco [[Addon della gilda|Guild-Addons-it]], quanti membri che condividono l'elenco dei propri addon lo hanno caricato, su quanti, con le versioni. **Gli ufficiali e il Maestro di gilda** vedono anche chi lo ha, con la versione e i personaggi; tutti gli altri vedono i conteggi e la propria voce. Se l'elenco degli addon è spento, nessuno condivide ancora un elenco, o tu non condividi il tuo, una riga lo dice.

Con **Accord** come fonte del roster della season, la vista rimanda alla vista [[Season|Season-Roster-it]], dove ogni raider dichiara.

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
