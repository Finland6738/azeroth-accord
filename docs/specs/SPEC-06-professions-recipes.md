# SPEC-06: Professioni e ricette

## 1. Fonti

[ADR 0010](../adr/0010-native-data-first-shared-data-as-fallback.md): adattatore con due fonti.

| Fonte | API | Copre |
|---|---|---|
| Nativa | `C_TradeSkillUI.IsGuildTradeSkillsEnabled`, `C_GuildInfo.QueryGuildMemberRecipes(guid, skillLine)`, `GetGuildMemberRecipes`, `C_GuildInfo.QueryGuildMembersForRecipe`, evento `GUILD_RECIPE_KNOWN_BY_MEMBERS`, `GetNumGuildTradeSkill` / `GetGuildTradeSkillInfo` **[verificare]** S3 | tutti i membri, anche senza addon |
| Condivisa | `TRADE_SKILL_SHOW` / `TRADE_SKILL_LIST_UPDATE` → `C_TradeSkillUI.GetAllRecipeIDs`, `GetRecipeInfo(id).learned`, `GetBaseProfessionInfo` **[verificare]** S4 | membri con l'addon, aggiornata quando aprono la finestra della professione |

### 1.1 Stato della scelta tra le fonti

I risultati della sonda in gioco (M0.4, controllo S3) **non sono ancora disponibili**: non si sa se i server Forever riempiono la directory delle ricette di gilda. Per questo:

- la fonte nativa è implementata dietro un controllo di capacità (`guildRecipesNative`, SPEC-01 §5): è usabile solo se `IsGuildTradeSkillsEnabled()` risponde `true` e le funzioni `QueryGuildMemberRecipes` e `GetGuildMemberRecipes` esistono; la capacità passa a `available` alla prima risposta letta;
- le liste condivise dagli addon (M3.2 e M3.3) sono un **ripiego completo che funziona da solo**: senza fonte nativa ogni vista mostra le liste condivise e nient'altro;
- **la scelta definitiva sarà confermata dai risultati di M0.4**: se la fonte nativa non risponde, resta il ripiego; se risponde, vince la nativa (ADR 0010) e la condivisa riempie i vuoti.

### 1.2 La fonte nativa (`Data/Recipes.lua`)

- Una richiesta chiede **un membro e una professione**: `C_GuildInfo.QueryGuildMemberRecipes(guid, skillLine)`; l'evento `GUILD_RECIPE_KNOWN_BY_MEMBERS` non ha contenuto, quindi le richieste vanno **una alla volta** e la risposta si attribuisce alla richiesta in corso.
- Ritmo: coda di al massimo 20 richieste senza duplicati, almeno 2 secondi tra due richieste, una risposta che non arriva entro 8 secondi si scarta; dopo 5 richieste senza risposta di fila la fonte riposa 10 minuti.
- Cache solo in memoria: una risposta resta valida 15 minuti (chi riapre la vista non costa nulla), al massimo 300 risposte, mai scritte su disco.
- Forma della risposta **[verificare]** S3: `GetGuildMemberRecipes` non ha firma nel dump. Si legge come primo valore la linea di abilità, poi una lista di spellID (o un insieme `{[id] = true}`). Una risposta a **bitfield** (stringa di bit) viene riconosciuta ma non decodificata: dopo due risposte illeggibili la fonte nativa si spegne (`guildRecipesNative` = `missing`, con il motivo) e restano le liste condivise.
- Una risposta per un'altra linea di abilità, o senza richiesta in corso (l'ha chiesta la finestra di Blizzard), si ignora.

### 1.3 La scansione delle proprie ricette (`Data/RecipeScan.lua`)

- Quando si apre la finestra di una professione (o la sua lista cambia: `TRADE_SKILL_SHOW`, `TRADE_SKILL_LIST_UPDATE`) la scansione parte 2 secondi dopo l'ultimo evento di una raffica e legge: la professione aperta (`GetBaseProfessionInfo`, abbinata per id o per nome a una professione del personaggio, così l'id è quello del roster), l'elenco degli id (`GetAllRecipeIDs`, altrimenti `GetFilteredRecipeIDs`) **[verificare]** S4 e per ogni id `GetRecipeInfo(id).learned`.
- Si tengono solo le ricette imparate. Se il client non dà mai il campo `learned` si contano tutte come conosciute; se non dà nessuna informazione sulle ricette non si legge nulla (non si pubblica un'ipotesi). La lista **filtrata** segue la ricerca della finestra e può essere parziale: una scansione da lì può solo **aggiungere** ricette a quelle già pubblicate, mai toglierne.
- Si pubblica un record `recipes` (SPEC-03 §3) quando l'impronta (`h`) cambia, al massimo **una volta ogni 10 minuti per professione** (PRO-06): una modifica che arriva prima aspetta e parte con lo stato più recente allo scadere dei 10 minuti. È sempre condiviso, senza impostazione.
- Anche Cooking, First Aid e Fishing hanno un record (la cucina serve a "who can craft"), ma non compaiono nelle celle di professione del roster, che mostra le due professioni primarie.

### 1.4 Sincronizzazione delle liste condivise e vista unificata

- Il record `recipes` viaggia con la sincronizzazione normale per autore (SPEC-02 §4): ogni modifica locale esce come `REC` su `GUILD` dopo 5 secondi, e chi arriva dopo la riceve dall'account dell'autore o da un ufficiale. Il simulatore (`Tests/test_recipe_sync.lua`) mostra che la lista di 400 ricette di un membro raggiunge 20 client in meno di 10 secondi con circa 1,3 KB in tutto per la gilda, e che un accesso tardivo la riceve entro il costo di 8 KB di SPEC-02 §4.
- **Richiesta su richiesta**: quando una vista apre le ricette di un membro, `Recipes:Ensure(guid, skillLine)` chiede a ogni fonte che può rispondere: la fonte nativa (§1.2) e, se la lista condivisa manca o ha più di 6 ore, la richiesta su misura di SPEC-02 §4.7. Restituisce lo stato di ciascuna (`queued`, `cached`, `unavailable`, `have`, `sent`, `recent`, `nobody`, `own`…), così la vista può dire "nessuno che abbia la lista è online" (PRO-03).
- `Recipes:Lookup(guid, skillLine)` è l'unico punto di lettura delle viste: la risposta nativa se c'è (con anche l'età della lista condivisa), altrimenti la lista condivisa (per il personaggio del giocatore, la propria scansione, fonte `own`), altrimenti nulla. `Recipes:ProfessionsOf(guid)` elenca le professioni di cui il membro ha condiviso una lista. L'evento `RECIPES_UPDATED(guid, skillLine, fonte)` avvisa le viste quando arriva una lista, nativa o condivisa.

## 2. Requisiti

- PRO-01: la cella della professione nel roster mostra nome e grado (per esempio `Alchemy 285/300`) e, al passaggio del mouse, la fonte e l'età.
- PRO-02: il clic apre l'**elenco delle ricette** di quel personaggio per quella professione: icona, nome dell'oggetto, livello di difficoltà, tooltip dell'oggetto, ricerca e filtri per categoria.
- PRO-03: se la ricetta del membro è sconosciuta (nessuna fonte) la vista lo dice e suggerisce di chiedergli di aprire la professione con l'addon.
- PRO-04: la vista **Professions** offre la ricerca "**who can craft …**": nome dell'oggetto o della ricetta → elenco dei membri che la conoscono, online prima, raggruppati per account.
- PRO-05: pulsante **Request craft** su una ricetta di un membro: apre un messaggio sussurrato precompilato con il link della ricetta (lo invia il giocatore); in V2 diventa un ordine registrato.
- PRO-06: il proprio elenco di ricette si pubblica quando cambia (hash diverso), al massimo una volta ogni 10 minuti per professione.

## 3. Dimensioni

Una professione ha qualche centinaio di ricette: come spellID ordinati codificati a differenze occupano circa 1,5 byte per ricetta, circa 2 caratteri in Base64 ([SPEC-03 §3](SPEC-03-data-model.md#3-ricette-recipes)). Una gilda di 200 membri con 2 professioni e in media 150 ricette ciascuna sta intorno ai 120 KB in SavedVariables, 300 KB nel caso peggiore di liste da 400 ricette; un record non supera 8 KB e un messaggio con 400 ricette pesa circa 1 KB dopo la compressione.
