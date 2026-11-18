# SPEC-06: Professioni e ricette

## 1. Fonti

[ADR 0010](../adr/0010-native-data-first-shared-data-as-fallback.md): adattatore con due fonti.

| Fonte | API | Copre |
|---|---|---|
| Nativa | `C_TradeSkillUI.IsGuildTradeSkillsEnabled`, `C_GuildInfo.QueryGuildMemberRecipes(guid, skillLine)`, `GetGuildMemberRecipes`, `C_GuildInfo.QueryGuildMembersForRecipe`, evento `GUILD_RECIPE_KNOWN_BY_MEMBERS`, `GetNumGuildTradeSkill` / `GetGuildTradeSkillInfo` **[verificare]** S3 | tutti i membri, anche senza addon |
| Condivisa | `TRADE_SKILL_SHOW` / `TRADE_SKILL_LIST_UPDATE` → `C_TradeSkillUI.GetAllRecipeIDs`, `GetRecipeInfo(id).learned`, `GetBaseProfessionInfo` **[verificare]** S4 | membri con l'addon, aggiornata quando aprono la finestra della professione |

## 2. Requisiti

- PRO-01: la cella della professione nel roster mostra nome e grado (per esempio `Alchemy 285/300`) e, al passaggio del mouse, la fonte e l'età.
- PRO-02: il clic apre l'**elenco delle ricette** di quel personaggio per quella professione: icona, nome dell'oggetto, livello di difficoltà, tooltip dell'oggetto, ricerca e filtri per categoria.
- PRO-03: se la ricetta del membro è sconosciuta (nessuna fonte) la vista lo dice e suggerisce di chiedergli di aprire la professione con l'addon.
- PRO-04: la vista **Professions** offre la ricerca "**who can craft …**": nome dell'oggetto o della ricetta → elenco dei membri che la conoscono, online prima, raggruppati per account.
- PRO-05: pulsante **Request craft** su una ricetta di un membro: apre un messaggio sussurrato precompilato con il link della ricetta (lo invia il giocatore); in V2 diventa un ordine registrato.
- PRO-06: il proprio elenco di ricette si pubblica quando cambia (hash diverso), al massimo una volta ogni 10 minuti per professione.

## 3. Dimensioni

Una professione ha qualche centinaio di ricette: come spellID ordinati codificati a differenze occupano circa 1 byte per ricetta prima della compressione. Una gilda di 200 membri con 2 professioni resta sotto i 300 KB in SavedVariables.
