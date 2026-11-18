# SPEC-10: Rischi e domande aperte

## 1. Rischi

| # | Rischio | Probabilità | Impatto | Risposta |
|---|---|---|---|---|
| R1 | La tab nella `CommunitiesFrame` causa taint o si rompe a un aggiornamento del client | media | medio | solo hook in osservazione, finestra autonoma sempre disponibile (S1) |
| R2 | Il server non riempie professioni e ricette native | media | basso | fonte condivisa (ADR 0010) |
| R3 | `OFFICER` non consegna i messaggi addon | bassa | medio | dati riservati non condivisi; il salt dei like passa in whisper tra ufficiali |
| R4 | Pochi membri installano l'addon | media | alto | valore dato anche dai dati nativi; la gilda del proprietario come primo pubblico |
| R5 | Restrizioni degli addon più dure (valori segreti nei gruppi, lockdown) | media | medio | Compat, coda, registrazione locale |
| R6 | Crescita delle SavedVariables in gilde grandi | bassa | medio | limiti di conservazione, codifica compatta, diagnostica delle dimensioni |
| R7 | Lettura sociale dell'indice ("classifica dei giocatori") | media | medio | testo che spiega cosa misura; mappa completa solo per ufficiali (Q3) |

## 2. Domande aperte per il proprietario

| # | Domanda | Proposta |
|---|---|---|
| Q1 | Nomi tecnici: cartella `AzerothAccord`, prefisso `AzAccord`, comandi `/accord` e `/acc` | come proposto |
| Q2 | Icona della tab: icona del client (per esempio uno stendardo o una stretta di mano) o disegno originale? | icona del client in V1 |
| Q3 | Mappa dei gruppi e indice degli altri: visibili a tutti o solo a ufficiali e GM? | indice personale e totale dei like per tutti; mappa completa per ufficiali e GM |
| Q4 | Banca: le schede che un grado non vede nel gioco restano nascoste anche nell'addon? | sì, si rispettano i permessi del gioco |
| Q5 | Classifica delle donazioni visibile a tutti o solo agli ufficiali? | a tutti, per riconoscere chi aiuta |
| Q6 | Il sistema di loot personalizzato della gilda: in V2 serve una descrizione per integrarlo | da raccogliere prima di pianificare V2 |
