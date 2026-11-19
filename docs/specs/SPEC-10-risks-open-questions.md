# SPEC-10: Rischi e domande aperte

## 1. Rischi

| # | Rischio | Probabilità | Impatto | Risposta |
|---|---|---|---|---|
| R1 | La tab nella `CommunitiesFrame` causa taint o si rompe a un aggiornamento del client | media | medio | solo hook in osservazione, finestra autonoma sempre disponibile (S1) |
| R2 | Il server non riempie professioni e ricette native | media | basso | fonte condivisa (ADR 0010) |
| R3 | `OFFICER` non consegna i messaggi addon | bassa | medio | dati riservati non condivisi; il salt dei like passa in whisper tra ufficiali |
| R4 | Pochi membri installano l'addon | media | alto | valore dato anche dai dati nativi; la gilda del proprietario come primo pubblico |
| R5 | Restrizioni degli addon più dure (valori segreti nei gruppi, lockdown) | media | medio | Compat, coda, registrazione locale |
| R6 | Crescita delle SavedVariables in gilde grandi | bassa | medio | limiti di conservazione, codifica compatta, diagnostica delle dimensioni. Misurato offline in M6.3 ([SPEC-09 §5](SPEC-09-quality-release.md#5-rifinitura-e-prestazioni-m63)): 3,6 MB per 1000 membri, 400 con l'addon e 90 giorni di co-play, l'80% del quale è co-play; il numero in gioco viene dal controllo S11 |
| R7 | Lettura sociale dell'indice ("classifica dei giocatori") | media | medio | testo che spiega cosa misura; mappa completa solo per ufficiali (Q3) |

## 2. Domande aperte per il proprietario

| # | Domanda | Proposta |
|---|---|---|
| Q1 | Nomi tecnici: cartella `AzerothAccord`, prefisso `AzAccord`, comandi `/accord` e `/acc` | come proposto |
| Q2 | Icona della tab: icona del client (per esempio uno stendardo o una stretta di mano) o disegno originale? | icona del client in V1 |
| Q3 | Mappa dei gruppi e indice degli altri: visibili a tutti o solo a ufficiali e GM? | indice personale e totale dei like per tutti; mappa completa per ufficiali e GM. **Attuata così da M4.5 in attesa della risposta**: si cambia in un solo punto (`Social.OTHERS_VISIBLE_TO`, [SPEC-07 §3.2](SPEC-07-reputation-social.md#32-calcolo)) |
| Q4 | Banca: le schede che un grado non vede nel gioco restano nascoste anche nell'addon? | sì, si rispettano i permessi del gioco. **Attuata così da M5.2 in attesa della risposta**: il gioco dice a un client solo se il *proprio* grado vede una scheda, quindi una foto porta il grado di chi l'ha letta e si mostra a quel grado e a quelli superiori; la foto di un ufficiale è solo per ufficiali ([SPEC-08 §5-6](SPEC-08-guild-bank.md)) |
| Q5 | Classifica delle donazioni visibile a tutti o solo agli ufficiali? | a tutti, per riconoscere chi aiuta. **Attuata così da M5.4 in attesa della risposta**: si cambia in un solo punto (`BankLog.DONATIONS_VISIBLE_TO`, [SPEC-08 §8](SPEC-08-guild-bank.md)) |
| Q6 | Il sistema di loot personalizzato della gilda: in V2 serve una descrizione per integrarlo | da raccogliere prima di pianificare V2 |
| Q7 | Convenzione delle note pubbliche per gli alt senza addon ([SPEC-05 §3](SPEC-05-roster-alts-contacts.md), ACC-05): `main: <nome>` = "il mio main è <nome>", `alt: <nome>` = "<nome> è un mio alt". Si usa così o al contrario? | come implementato in M2.2; cambia solo chi è il main del gruppo, non il raggruppamento |
| Q8 | Fonte principale delle ricette ([SPEC-06 §1.1](SPEC-06-professions-recipes.md)): la directory nativa del gioco o le liste condivise dagli addon? | implementate entrambe: la nativa vince se risponde, la condivisa è un ripiego completo; la scelta si conferma con M0.4 e con [la prova di M3](../checklists/M3.md) |
