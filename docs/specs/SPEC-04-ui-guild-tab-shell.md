# SPEC-04: Scheda Accord e struttura dell'interfaccia

## 1. La tab nella finestra Gilda

La `CommunitiesFrame` ha sulla destra le tab Chat, Roster, Guild Benefits e Guild Info. Accord aggiunge **una quinta tab** con la propria icona ([ADR 0003](../adr/0003-accord-tab-in-the-guild-window.md)).

| ID | Requisito |
|---|---|
| GT-01 | La tab è un pulsante dell'addon, figlio della `CommunitiesFrame`, ancorato sotto l'ultima tab visibile di Blizzard, con lo stesso aspetto e un tooltip "Azeroth Accord". |
| GT-02 | Compare solo quando il club selezionato è la gilda (`C_Club.GetGuildClubId()`), e si nasconde nella modalità ridotta della finestra. |
| GT-03 | Il clic mostra il pannello Accord sopra l'area dei contenuti e segna la tab come selezionata; il clic su una tab di Blizzard nasconde il pannello (osservato con `hooksecurefunc` / `HookScript`). |
| GT-04 | L'addon non chiama `SetDisplayMode` e non sostituisce funzioni di Blizzard. |
| GT-05 | Se la `CommunitiesFrame` cambia struttura (Compat non trova le tab) la tab non compare e resta la finestra autonoma; `/accord debug` lo segnala. |
| GT-06 | In combattimento il pannello si apre e si chiude normalmente: non contiene azioni protette. |

Realizzazione (`UI/GuildTab.lua`, M1.8):

- La tab si crea quando `Blizzard_Communities` (caricato su richiesta) arriva, o all'accesso se è già caricato. Il modello del pulsante è quello di Blizzard (`CommunitiesFrameTabTemplate`) se il client lo ha, altrimenti un pulsante semplice con l'icona; un modello mancante non dà errori.
- L'ancoraggio è sotto l'ultima tab di Blizzard visibile nell'ordine Chat, Roster, Guild Benefits, Guild Info; si aggiorna quando una di loro si mostra o si nasconde.
- Il pannello copre `CommunitiesFrame.Inset` (o un rettangolo di riserva) qualche livello sopra la finestra e intercetta i clic. Da M6.12 è riempito col colore `bg` del tema (una texture quadrata dell'addon, così gli angoli dell'area di Blizzard restano coperti) e non ha barra del titolo; il badge della tab (richieste della banca) è un cerchio `accent` col numero in `on-accent`.
- Ganci usati, e solo questi: `HookScript("OnClick" / "OnShow" / "OnHide")` sulle quattro tab, `HookScript("OnShow" / "OnHide")` sulla finestra, `hooksecurefunc(CommunitiesFrame, "SetDisplayMode" / "SelectClub")`. I test offline verificano che nessun'altra funzione o script di Blizzard cambi e che l'addon non chiami mai `SetDisplayMode`.
- La capacità `guildTab` in `/accord debug` dice se la tab è agganciata, con quale modello, o perché no.

## 2. Il pannello

- **Schede** in alto (da M6.12; prima era una navigazione a sinistra): Roster, Professions, Reputation, Bank, Settings, con l'indicatore da 2 pt sotto la scheda attiva ([`ui-style.md` §3](ui-style.md#3-le-viste-come-schede)). Le schede delle milestone non ancora pronte non compaiono: ogni vista si registra (`Shell:RegisterView`) quando esiste; senza viste (M1) il pannello mostra un testo di benvenuto. La vista scelta per ultima si ricorda per personaggio. Una vista che solleva un errore alla costruzione mostra un testo di errore al suo posto e non toglie le altre; un nuovo clic sulla sua scheda riprova ([SPEC-09 §5](SPEC-09-quality-release.md#5-rifinitura-e-prestazioni-m63)). Il conteggio di una vista (le richieste della banca in attesa) è un badge sulla sua scheda, non più "(n)" nel nome.
- **A destra delle schede**: la ricerca (nome, professione, oggetto), visibile mentre la vista aperta sa cercare, e il testo va a quella vista; nella finestra Gilda il pulsante **Pop out** che apre la stessa vista nella finestra autonoma più larga. **Stato della sincronizzazione** (ultimo aggiornamento, membri con l'addon online): nella finestra Gilda in una riga sottile in fondo al pannello, nella finestra autonoma sotto il titolo.
- **Tabelle**: intestazioni cliccabili per ordinare, colonne scelte dal giocatore (salvate per personaggio), righe virtuali (solo quelle visibili sono disegnate) per gilde di 1000 membri.
- **Fonte e età dei dati** sempre visibili dove servono (per esempio "Bank tab 2 · seen 3 h ago by <name>").

## 3. Finestra autonoma

Stesso pannello in una finestra mobile e ridimensionabile, aperta da `/accord`, dall'AddOn Compartment, da un tasto rapido o dal pulsante Pop out. Ricorda posizione e dimensione per personaggio (920 × 600 la prima volta, minimo 720 × 460, massimo 1600 × 1000; una dimensione salvata fuori da questi limiti si riporta dentro), si chiude con Esc. Il contenuto è uno solo e passa da un contenitore all'altro: Pop out lo sposta dalla tab alla finestra; un clic sulla tab, o **Pop in** nella barra del titolo, lo riporta e chiude la finestra (che così non resta aperta e vuota). Pop in compare solo mentre la finestra Gilda è aperta sulla gilda: l'addon non apre mai la finestra di Blizzard. Senza gilda `/accord` dice "You are not in a guild." e non apre nulla; uscendo dalla gilda finestra e pannello si chiudono.

Da M6.12 la finestra è un frame dell'addon senza modello di Blizzard ([`ui-style.md` §3](ui-style.md#3-le-viste-come-schede)): pannello del tema con raggio 12 e ombra, barra del titolo da 52 pt (logo rotondo, "AZEROTH ACCORD" in Orbitron, stato della sincronizzazione sotto, Pop in, chiudi; si trascina dalla barra), le schede sotto, la maniglia di ridimensionamento in basso a destra con un'icona dell'addon.

## 4. Comandi

| Comando | Effetto |
|---|---|
| `/accord` o `/acc` | apre o chiude la finestra autonoma |
| `/accord roster`, `professions`, `reputation`, `bank` | apre quella vista (`professions` si apre sulla ricerca "who can craft", [SPEC-06 §2.2](SPEC-06-professions-recipes.md); `reputation` sulla classifica dei like, [SPEC-07 §2.3](SPEC-07-reputation-social.md#23-interfaccia-dei-like-uireputationlua-m43)) |
| `/accord settings` | apre la vista Settings ([§6](#6-impostazioni-m61)) |
| `/accord debug` | rapporto di diagnostica in una casella già selezionata, da copiare con Ctrl+C ([SPEC-09 §6](SPEC-09-quality-release.md#6-diagnostica-e-segnalazioni-m64)) |
| `/accord help` | elenco dei comandi |

## 5. Stile

> **Aggiornamento (M6.8, [ADR 0021](../adr/0021-interface-follows-the-ecosystem-style-of-fdcp.md)).** L'aspetto "del gioco" descritto qui sotto (`UI/Skin.lua`, modelli e font del client) viene **sostituito** dallo stile della famiglia FDCP, specificato in [`ui-style.md`](ui-style.md): temi Nebula, Aurora e Accord, viste come schede, barra del titolo nella finestra autonoma, pannello con i colori del tema dentro la finestra Gilda (che resta solo osservata). Il testo seguente descrive lo stato fino a M6.7 e si riscrive quando i passi M6.13-M6.14 sono fatti. **M6.12 fatto**: la finestra, la barra del titolo, le schede e il pannello nella finestra Gilda hanno il nuovo aspetto e §2-§3 lo descrivono; le viste dentro il pannello hanno ancora l'aspetto qui sotto fino a M6.13-M6.14.

Aspetto coerente con la finestra della Gilda di Blizzard (bordi, font e colori del client), così la tab sembra nativa. Icone del client per classi, professioni e oggetti, per fileID o atlas.

**Anteprime di progetto (M6.6).** Prima che l'addon giri nel client vero, l'aspetto di ogni vista principale è mostrato in immagini disegnate dal layout e dai testi dell'addon, con la grafica originale e dati inventati ([`mockups/`](mockups/README.md)): l'aspetto è quello della finestra Gilda del gioco, non una pergamena personalizzata come in Azeroth Guild Finder. Non sono screenshot; ogni immagine lo dice nella striscia in basso. Sono incorporate nel wiki e nei README.

## 6. Impostazioni (M6.1)

La vista **Settings** (`/accord settings`) e un pannello **Azeroth Accord** nella finestra Impostazioni del gioco (registrato all'accesso con `Settings.RegisterCanvasLayoutCategory` e `RegisterAddOnCategory` quando il client li ha, altrimenti non c'è pannello e `/accord debug` lo dice) mostrano **la stessa pagina**, disegnata da un solo costruttore (`UI/Settings.lua`) con le opzioni e le azioni in `UI/SettingsModel.lua`. La pagina scorre con la rotella. Una modifica in una delle due si vede subito nell'altra (evento `SETTINGS_CHANGED` sul Bus). Il pannello del gioco costruisce la pagina solo quando viene mostrato; il suo pulsante *Defaults* non fa nulla, perché le opzioni di Accord si applicano mentre si cambiano.

| Scheda | Contenuto | Dove si salva |
|---|---|---|
| Contatti | BattleTag (letto dal gioco) e nome Discord digitato; sempre condivisi con la gilda, nessun interruttore (D3) | `account.settings.discord` |
| Personaggio principale | il main tra i personaggi dell'account sul reame (menu); guida il gruppo nel Roster raggruppato e nella scheda | `mains[<reame>]` ([SPEC-05 §3](SPEC-05-roster-alts-contacts.md)) |
| Notifiche | `notifyOfficer` (solo ufficiali: una riga in chat per ogni nuova richiesta alla banca) e `notifyDecision` (una riga quando una richiesta propria è approvata, rifiutata o consegnata); entrambe attive di default. Spegnerle non toglie nulla dal contatore sulla scheda né dalla vista Banca | `account.settings.notifyOfficer`, `account.settings.notifyDecision` |
| Colonne del Roster | le colonne che la tabella mostra e il ritorno a quelle predefinite; la colonna del nome non si spegne | `char.ui.columns` (per personaggio) |
| Dati salvati | dimensione stimata dell'account, del personaggio e della gilda corrente, e per ogni insieme di dati della gilda numero di record e dimensione (nessun nome) | — |
| Cancella i dati della gilda | due clic (il primo mostra quanto si libera e si ritira dopo 8 secondi): dimentica i dati della gilda corrente e li richiede ai compagni | — |

**Cancella i dati della gilda** (`GuildKey:Clear`) toglie dalla tabella della gilda corrente tutto tranne ciò che **solo questo computer sa** e la gilda non può rimandare: le chiavi dei like dell'ufficiale (`salts`: perderne l'unica copia permetterebbe di dare di nuovo un like già dato, [ADR 0007](../adr/0007-likes-one-per-account-irreversible-anonymous.md)), la memoria dei like dati dall'account (`likes`) e la tabella `bank` (storico del denaro osservato alla banca e avvisi già mostrati, così un reinvio non viene annunciato di nuovo). Non tocca mai il token dell'account, i personaggi, il main, le impostazioni, le impostazioni del personaggio né i dati di un'altra gilda, e si rifiuta con i dati salvati in sola lettura (schema più nuovo). Poi emette di nuovo `GUILD_CHANGED` con la stessa chiave: i moduli si azzerano e ripartono come dopo un cambio di gilda (HELLO, richiesta dei dati, roster).
