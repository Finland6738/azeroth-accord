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

## 2. Il pannello

- **Navigazione** a sinistra, dentro il pannello: Roster, Professions, Reputation, Bank, Settings. Le voci delle milestone non ancora pronte non compaiono.
- **Barra superiore**: ricerca globale (nome, professione, oggetto), stato della sincronizzazione (ultimo aggiornamento, membri con l'addon online), pulsante **Pop out** che apre la stessa vista nella finestra autonoma più larga.
- **Tabelle**: intestazioni cliccabili per ordinare, colonne scelte dal giocatore (salvate per personaggio), righe virtuali (solo quelle visibili sono disegnate) per gilde di 1000 membri.
- **Fonte e età dei dati** sempre visibili dove servono (per esempio "Bank tab 2 · seen 3 h ago by <name>").

## 3. Finestra autonoma

Stesso pannello in una finestra mobile e ridimensionabile, aperta da `/accord`, dall'AddOn Compartment, da un tasto rapido o dal pulsante Pop out. Ricorda posizione e dimensione.

## 4. Comandi

| Comando | Effetto |
|---|---|
| `/accord` o `/acc` | apre o chiude la finestra autonoma |
| `/accord roster`, `professions`, `reputation`, `bank` | apre quella vista |
| `/accord debug` | rapporto di diagnostica da copiare |
| `/accord help` | elenco dei comandi |

## 5. Stile

Aspetto coerente con la finestra della Gilda di Blizzard (bordi, font e colori del client), così la tab sembra nativa. Icone del client per classi, professioni e oggetti, per fileID o atlas.
