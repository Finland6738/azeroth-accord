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
| GT-07 | Finché il pannello è aperto la finestra Gilda è nel tema (M6.18, `UI/GuildSkin.lua`, [`ui-style.md`](ui-style.md) §3): le parti grafiche di Blizzard diventano trasparenti (alfa ripristinato quando il pannello si chiude), dietro si disegna una cornice tematica con il nome della gilda e la croce, le linguette sono tessere tematiche. Nessuna funzione di Blizzard è sostituita o chiamata (GT-04). |

Realizzazione (`UI/GuildTab.lua`, M1.8):

- La tab si crea quando `Blizzard_Communities` (caricato su richiesta) arriva, o all'accesso se è già caricato. Il modello del pulsante è quello di Blizzard (`CommunitiesFrameTabTemplate`) se il client lo ha, altrimenti un pulsante semplice con l'icona; un modello mancante non dà errori.
- L'ancoraggio è sotto l'ultima tab di Blizzard visibile nell'ordine Chat, Roster, Guild Benefits, Guild Info; si aggiorna quando una di loro si mostra o si nasconde.
- Il pannello copre `CommunitiesFrame.Inset` (o un rettangolo di riserva) qualche livello sopra la finestra e intercetta i clic. Da M6.12 è riempito col colore `bg` del tema (una texture quadrata dell'addon, così gli angoli dell'area di Blizzard restano coperti) e non ha barra del titolo; il badge della tab (richieste della banca) è un cerchio `accent` col numero in `on-accent`.
- Ganci usati, e solo questi: `HookScript("OnClick" / "OnShow" / "OnHide")` sulle quattro tab, `HookScript("OnShow" / "OnHide")` sulla finestra, `hooksecurefunc(CommunitiesFrame, "SetDisplayMode" / "SelectClub")`. I test offline verificano che nessun'altra funzione o script di Blizzard cambi e che l'addon non chiami mai `SetDisplayMode`.
- La capacità `guildTab` in `/accord debug` dice se la tab è agganciata, con quale modello, o perché no.

## 2. Il pannello

- **Schede** in alto (da M6.12; prima era una navigazione a sinistra): Roster, Professions, Reputation, Bank, Raid (da M11.7; nascosta nelle release finché M10 e M11 non sono complete, interruttore `raid` di `Core/Features.lua`), Settings, con l'indicatore da 2 pt sotto la scheda attiva ([`ui-style.md` §3](ui-style.md#3-le-viste-come-schede)). Le schede delle milestone non ancora pronte non compaiono: ogni vista si registra (`Shell:RegisterView`) quando esiste; senza viste (M1) il pannello mostra un testo di benvenuto. La vista scelta per ultima si ricorda per personaggio. Una vista che solleva un errore alla costruzione mostra un testo di errore al suo posto e non toglie le altre; un nuovo clic sulla sua scheda riprova ([SPEC-09 §5](SPEC-09-quality-release.md#5-rifinitura-e-prestazioni-m63)). Il conteggio di una vista (le richieste della banca in attesa) è un badge sulla sua scheda, non più "(n)" nel nome.
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
| `/accord raid` | apre la vista Raid: le fonti della gilda e ciò che FDCP pubblica (M11.7, [ADR 0022](../adr/0022-integrations-with-raid-and-loot-addons.md)); con l'interruttore `raid` spento il comando non esiste |
| `/accord settings` | apre la vista Settings ([§6](#6-impostazioni-m61)) |
| `/accord about` | apre la pagina Info delle Impostazioni ([§7](#7-informazioni-m615)); `/accord about chat` scrive i crediti in chat |
| `/accord debug` | rapporto di diagnostica in una casella già selezionata, da copiare con Ctrl+C ([SPEC-09 §6](SPEC-09-quality-release.md#6-diagnostica-e-segnalazioni-m64)) |
| `/accord help` | elenco dei comandi |

## 5. Stile

> **Aggiornamento (M6.8, [ADR 0021](../adr/0021-interface-follows-the-ecosystem-style-of-fdcp.md)).** L'aspetto "del gioco" descritto qui sotto (`UI/Skin.lua`, modelli e font del client) viene **sostituito** dallo stile della famiglia FDCP, specificato in [`ui-style.md`](ui-style.md): temi Nebula, Aurora e Accord, viste come schede, barra del titolo nella finestra autonoma, pannello con i colori del tema dentro la finestra Gilda (che resta solo osservata). Il testo seguente descrive lo stato fino a M6.7 e si riscrive quando i passi M6.13-M6.14 sono fatti. **M6.12 fatto**: la finestra, la barra del titolo, le schede e il pannello nella finestra Gilda hanno il nuovo aspetto e §2-§3 lo descrivono. **M6.13-M6.14 fatti**: anche tutte le viste hanno il nuovo aspetto e `UI/Skin.lua` non esiste più; il testo qui sotto resta come storia dello stato fino a M6.7.

Aspetto coerente con la finestra della Gilda di Blizzard (bordi, font e colori del client), così la tab sembra nativa. Icone del client per classi, professioni e oggetti, per fileID o atlas.

**Anteprime di progetto (M6.6, ridisegnate in M6.16).** Prima che l'addon giri nel client vero, l'aspetto di ogni vista principale è mostrato in immagini disegnate dal layout e dai testi dell'addon, con la grafica originale e dati inventati ([`mockups/`](mockups/README.md)): dal M6.16 nel nuovo aspetto (Nebula, alcune in Aurora e in Accord, più la pagina Info), con il foglio di stile e i componenti di FDCP ([`ui-style.md`](ui-style.md) §8) e un foglio di confronto con le anteprime di FDCP. Non sono screenshot; ogni immagine lo dice nella striscia in basso. Sono incorporate nel wiki e nei README.

## 6. Impostazioni (M6.1)

La vista **Settings** (`/accord settings`) e un pannello **Azeroth Accord** nella finestra Impostazioni del gioco (registrato all'accesso con `Settings.RegisterCanvasLayoutCategory` e `RegisterAddOnCategory` quando il client li ha, altrimenti non c'è pannello e `/accord debug` lo dice) mostrano **la stessa pagina**, disegnata da un solo costruttore (`UI/Settings.lua`) con le opzioni e le azioni in `UI/SettingsModel.lua`. La pagina scorre con la rotella. Una modifica in una delle due si vede subito nell'altra (evento `SETTINGS_CHANGED` sul Bus). Il pannello del gioco costruisce la pagina solo quando viene mostrato; il suo pulsante *Defaults* non fa nulla, perché le opzioni di Accord si applicano mentre si cambiano.

| Scheda | Contenuto | Dove si salva |
|---|---|---|
| Aspetto (M6.14) | tema (Nebula, Aurora, Accord), effetti neon, animazioni, font (di Accord o del gioco); una modifica si vede subito e vale per tutti i personaggi dell'account ([`ui-style.md`](ui-style.md) §2) | `account.settings.theme`, `.effects`, `.animations`, `.font` |
| Contatti | BattleTag (letto dal gioco) e nome Discord digitato; sempre condivisi con la gilda, nessun interruttore (D3) | `account.settings.discord` |
| Personaggio principale | il main tra i personaggi dell'account sul reame (menu); guida il gruppo nel Roster raggruppato e nella scheda | `mains[<reame>]` ([SPEC-05 §3](SPEC-05-roster-alts-contacts.md)) |
| Notifiche | `notifyOfficer` (solo ufficiali: una riga in chat per ogni nuova richiesta alla banca) e `notifyDecision` (una riga quando una richiesta propria è approvata, rifiutata o consegnata); entrambe attive di default. Spegnerle non toglie nulla dal contatore sulla scheda né dalla vista Banca | `account.settings.notifyOfficer`, `account.settings.notifyDecision` |
| Colonne del Roster | le colonne che la tabella mostra e il ritorno a quelle predefinite; la colonna del nome non si spegne | `char.ui.columns` (per personaggio) |
| Dati salvati | dimensione stimata dell'account, del personaggio e della gilda corrente, e per ogni insieme di dati della gilda numero di record e dimensione (nessun nome) | — |
| Cancella i dati della gilda | due clic (il primo mostra quanto si libera e si ritira dopo 8 secondi): dimentica i dati della gilda corrente e li richiede ai compagni | — |

**Cancella i dati della gilda** (`GuildKey:Clear`) toglie dalla tabella della gilda corrente tutto tranne ciò che **solo questo computer sa** e la gilda non può rimandare: le chiavi dei like dell'ufficiale (`salts`: perderne l'unica copia permetterebbe di dare di nuovo un like già dato, [ADR 0007](../adr/0007-likes-one-per-account-irreversible-anonymous.md)), la memoria dei like dati dall'account (`likes`) e la tabella `bank` (storico del denaro osservato alla banca e avvisi già mostrati, così un reinvio non viene annunciato di nuovo). Non tocca mai il token dell'account, i personaggi, il main, le impostazioni, le impostazioni del personaggio né i dati di un'altra gilda, e si rifiuta con i dati salvati in sola lettura (schema più nuovo). Poi emette di nuovo `GUILD_CHANGED` con la stessa chiave: i moduli si azzerano e ripartono come dopo un cambio di gilda (HELLO, richiesta dei dati, roster).

**Aspetto (M6.14).** La pagina è una colonna di card (`Widgets.Card`) che prendono l'altezza di ciò che mostrano, con la card **Aspetto** in cima; le opzioni sì/no sono interruttori (`Widgets.Switch`), le colonne del Roster chip, il menu del main `Widgets.Menu`. La card Aspetto salva con `SettingsModel.SetLook(chiave, valore)`, che passa da `Config:Set` (`CONFIG_CHANGED`: `UI/Theme.lua` ridipinge subito) ed emette `SETTINGS_CHANGED(chiave)`; un rifiuto (dati in sola lettura) si dice sotto la card e il valore mostrato torna quello salvato. Nel pannello del gioco la pagina sta sul fondo `bg` del tema. `SettingsView.AddPage(id, def)` aggiunge una sotto-pagina accanto a *Settings* (un selettore a pillole compare dalla seconda: *Info*, M6.15).

### 6.1 Cosa condivido (M7.6)

La pagina **What I share** / **Cosa condivido** (`UI/SharePanel.lua`, `UI/ShareModel.lua`) è la seconda pagina del selettore, tra Settings e Info (`AddPage("share", …)`, ordine 15). Elenca, per ogni insieme di dati che questo personaggio pubblica, a chi va, quando parte e il contenuto dei record che il client ha mandato per ultimi; il contenuto, le righe e l'unico interruttore (`Record time played together`, `account.settings.shareCoplay`) sono in [SPEC-11 §5](SPEC-11-data-trust.md#5-pannello-cosa-condivido-m76). L'interruttore non è nella card Notifiche: ha `group = "sharing"` in `SettingsModel.OPTIONS` e si disegna solo su questa pagina.

## 7. Informazioni (M6.15)

La pagina **Info** (`UI/About.lua`) è la seconda pagina della vista Settings, dopo la pagina delle opzioni: si sceglie con il selettore (`Widgets.Segmented`) in alto, in entrambe le istanze (vista del pannello e pannello nella finestra Impostazioni del gioco), si registra con `SettingsView.AddPage("info", …)` e si costruisce la prima volta che viene mostrata. `/accord about` apre la vista Settings su Info; `/accord about chat` scrive gli stessi crediti nella chat (fuori dalla gilda, dove la vista non si apre, scrive in chat in ogni caso).

La pagina è una colonna di quattro schede (larghezza 520, come le Impostazioni), che scorre con la rotella:

1. **L'addon**: il logo (`logo_256`, 72 punti), il nome, la versione (quella del TOC, "sviluppo" quando il TOC non è ancora impacchettato) e due righe su che cosa fa.
2. **Crediti**: "Creato e progettato da Finland" e "Realizzato con la gilda italiana NEBULA", con il logo di NEBULA (64 punti) scelto dal tema, scuro in Nebula e Accord e chiaro in Aurora, che segue `Theme.Apply` senza `/reload`; sotto, la nota "Il logo di NEBULA è usato con il permesso della gilda".
3. **Link**: quattro caselle di sola lettura da copiare (il gioco non apre pagine web): il repository, le issue, la pagina di NEBULA e Ko-fi. Un clic seleziona il testo; scrivere nella casella lo rimette com'era.
4. **Licenza e note**: GPL-3.0, il rinvio a `docs/third-party.md` e l'avviso che l'addon è creato dai fan e non è né realizzato né affiliato a Blizzard Entertainment.

Ogni parola è una chiave di localizzazione (enUS e itIT); i nomi "Finland" e "NEBULA" e i link sono costanti del file, passate come argomenti. Il TOC ha `## X-Credits` e `## X-Website`. Solo i fatti decisi dal proprietario (PR #58): nessun nome reale, nessun indirizzo e-mail. Test: `Tests/test_ui_about.lua`.
