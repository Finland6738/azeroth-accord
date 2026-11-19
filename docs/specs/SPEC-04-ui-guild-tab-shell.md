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
- Il pannello copre `CommunitiesFrame.Inset` (o un rettangolo di riserva) qualche livello sopra la finestra e intercetta i clic.
- Ganci usati, e solo questi: `HookScript("OnClick" / "OnShow" / "OnHide")` sulle quattro tab, `HookScript("OnShow" / "OnHide")` sulla finestra, `hooksecurefunc(CommunitiesFrame, "SetDisplayMode" / "SelectClub")`. I test offline verificano che nessun'altra funzione o script di Blizzard cambi e che l'addon non chiami mai `SetDisplayMode`.
- La capacità `guildTab` in `/accord debug` dice se la tab è agganciata, con quale modello, o perché no.

## 2. Il pannello

- **Navigazione** a sinistra, dentro il pannello: Roster, Professions, Reputation, Bank, Settings. Le voci delle milestone non ancora pronte non compaiono: ogni vista si registra (`Shell:RegisterView`) quando esiste; senza viste (M1) il pannello mostra un testo di benvenuto. La vista scelta per ultima si ricorda per personaggio.
- **Barra superiore**: ricerca globale (nome, professione, oggetto), stato della sincronizzazione (ultimo aggiornamento, membri con l'addon online), pulsante **Pop out** che apre la stessa vista nella finestra autonoma più larga.
- **Tabelle**: intestazioni cliccabili per ordinare, colonne scelte dal giocatore (salvate per personaggio), righe virtuali (solo quelle visibili sono disegnate) per gilde di 1000 membri.
- **Fonte e età dei dati** sempre visibili dove servono (per esempio "Bank tab 2 · seen 3 h ago by <name>").

## 3. Finestra autonoma

Stesso pannello in una finestra mobile e ridimensionabile, aperta da `/accord`, dall'AddOn Compartment, da un tasto rapido o dal pulsante Pop out. Ricorda posizione e dimensione per personaggio (minimo 640 × 400), si chiude con Esc. Il contenuto è uno solo e passa da un contenitore all'altro: Pop out lo sposta dalla tab alla finestra, un clic sulla tab lo riporta. Senza gilda `/accord` dice "You are not in a guild." e non apre nulla; uscendo dalla gilda finestra e pannello si chiudono.

## 4. Comandi

| Comando | Effetto |
|---|---|
| `/accord` o `/acc` | apre o chiude la finestra autonoma |
| `/accord roster`, `professions`, `reputation`, `bank` | apre quella vista (`professions` si apre sulla ricerca "who can craft", [SPEC-06 §2.2](SPEC-06-professions-recipes.md); `reputation` sulla classifica dei like, [SPEC-07 §2.3](SPEC-07-reputation-social.md#23-interfaccia-dei-like-uireputationlua-m43)) |
| `/accord settings` | apre la vista Settings ([§6](#6-impostazioni-m61)) |
| `/accord debug` | rapporto di diagnostica in una casella già selezionata, da copiare con Ctrl+C |
| `/accord help` | elenco dei comandi |

## 5. Stile

Aspetto coerente con la finestra della Gilda di Blizzard (bordi, font e colori del client), così la tab sembra nativa. Icone del client per classi, professioni e oggetti, per fileID o atlas.

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
