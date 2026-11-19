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

## 2. Requisiti

- PRO-01: la cella della professione nel roster mostra nome e grado (per esempio `Alchemy 285/300`) e, al passaggio del mouse, la fonte e l'età.
- PRO-02: il clic apre l'**elenco delle ricette** di quel personaggio per quella professione: icona, nome dell'oggetto, livello di difficoltà, tooltip dell'oggetto, ricerca e filtri per categoria.
- PRO-03: se la ricetta del membro è sconosciuta (nessuna fonte) la vista lo dice e suggerisce di chiedergli di aprire la professione con l'addon.
- PRO-04: la vista **Professions** offre la ricerca "**who can craft …**": nome dell'oggetto o della ricetta → elenco dei membri che la conoscono, online prima, raggruppati per account.
- PRO-05: pulsante **Request craft** su una ricetta di un membro: apre un messaggio sussurrato precompilato con il link della ricetta (lo invia il giocatore); in V2 diventa un ordine registrato.
- PRO-06: il proprio elenco di ricette si pubblica quando cambia (hash diverso), al massimo una volta ogni 10 minuti per professione.

## 3. Dimensioni

Una professione ha qualche centinaio di ricette: come spellID ordinati codificati a differenze occupano circa 1 byte per ricetta prima della compressione. Una gilda di 200 membri con 2 professioni resta sotto i 300 KB in SavedVariables.
