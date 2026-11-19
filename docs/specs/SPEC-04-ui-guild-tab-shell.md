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
| `/accord roster`, `professions`, `reputation`, `bank` | apre quella vista (`professions` si apre sulla ricerca "who can craft", [SPEC-06 §2.2](SPEC-06-professions-recipes.md)) |
| `/accord debug` | rapporto di diagnostica in una casella già selezionata, da copiare con Ctrl+C |
| `/accord help` | elenco dei comandi |

## 5. Stile

Aspetto coerente con la finestra della Gilda di Blizzard (bordi, font e colori del client), così la tab sembra nativa. Icone del client per classi, professioni e oggetti, per fileID o atlas.
