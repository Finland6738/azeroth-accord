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
- PRO-05: pulsante **Request craft** su una ricetta di un membro: apre un messaggio sussurrato precompilato con il link della ricetta (lo invia il giocatore); in M13 diventa un ordine registrato.
- PRO-06: il proprio elenco di ricette si pubblica quando cambia (hash diverso), al massimo una volta ogni 10 minuti per professione.

### 2.1 Realizzazione dell'elenco delle ricette (M3.4)

- **Cella e tooltip** (PRO-01): le celle `Profession 1/2` del roster mostrano `Alchemy 285/300` (il massimo c'è se lo dà la lista condivisa; la fonte nativa dà solo il grado). Un pulsante invisibile sopra la cella (solo se il membro ha quella professione) mostra al passaggio la fonte e l'età e, al clic, apre la vista **Professions** su quel membro (`RecipeView:OpenFor`). Le righe della professione nella scheda del membro fanno lo stesso. Se il gioco non dà l'id della professione si cerca per nome tra le liste condivise del membro; altrimenti la vista lo dice (PRO-03).
- **Vista** (PRO-02, `UI/Professions.lua`, modello in `UI/RecipeModel.lua`): intestazione con Indietro, `<membro> - <professione> <grado>/<massimo>`, fonte e età; righe virtuali (una `Kit.DataTable` con le colonne *Recipe*, *Details*, *Status* e il pulsante, M6.13) con icona e nome (da `C_Spell.GetSpellInfo`: un nome non ancora caricato si mostra come `Recipe <id>`, si chiede al client con `RequestLoadSpellData` e la vista si ridisegna una volta sola quando arriva `SPELL_DATA_LOAD_RESULT`); tooltip = il tooltip del gioco per il link della ricetta; ricerca = la casella di ricerca del pannello (nome o id); **Category** (un `Kit.Select`) con "ricette che conosco / che non conosco" (confronto con la propria lista della stessa professione) e le categorie che il client dice (`GetRecipeInfo(id).categoryID`, `GetCategoryInfo` **[verificare]** S4); un nome colorato per difficoltà se il client la dà (`relativeDifficulty`).
- **Senza lista** (PRO-03): al posto delle righe un messaggio che dice perché e cosa chiedere (in attesa della risposta, nessuno online che abbia la lista, il membro non usa l'addon, la professione non è nota); la vista chiede la lista a ogni fonte (`Recipes:Ensure`) e si riempie da sola quando arriva.
- Il livello di difficoltà e le categorie dipendono da quanto il client dà per le ricette di altri: dove non lo dà la vista non li mostra (nessun errore).

### 2.2 "Who can craft" (M3.5, PRO-04)

- La vista **Professions** si apre sulla ricerca "who can craft"; la casella di ricerca del pannello prende il nome di un oggetto o di una ricetta (almeno 2 caratteri; un link di oggetto o di incantesimo incollato vale il suo nome tra parentesi). `/accord professions` apre questa vista. Ogni modalità tiene il proprio testo nella casella: tornando indietro si ritrova quello giusto.
- **Indice inverso** (`Data/Crafters.lua`): da ogni lista nota (`Recipes:AllLists`: le risposte native, che vincono, e i record condivisi, compresa la propria scansione) a ricetta → membri. Solo membri della gilda (il record di chi è uscito si ignora). Si ricostruisce con calma dopo un cambiamento (`RECIPES_UPDATED`, `ROSTER_UPDATED`): con 400 membri e 2 liste da 300 ricette la prima ricerca costa circa 250 ms e le successive pochi millisecondi.
- **Risultato**: le ricette il cui nome contiene il testo (prima il nome esatto, poi quelli che iniziano col testo, poi gli altri, per nome), al massimo 40, e sotto ognuna i membri che la conoscono: **online prima**, poi per nome, con i personaggi di uno stesso account vicini (l'account con qualcuno online per primo; gli alt rientrati sotto il primo). Al massimo 120 personaggi per ricetta. Ogni riga dice professione, grado e fonte con l'età; "Online only" tiene solo chi è online adesso.
- Il nome di una ricetta è il nome dell'incantesimo, che per la maggior parte dei mestieri è anche il nome dell'oggetto creato; i nomi non ancora caricati si chiedono al client (al massimo 150 richieste ogni 5 secondi) e la ricerca li conta come "in caricamento".
- La ricerca copre i membri **di cui si conosce la lista**: quelle condivise dai loro addon e le risposte native già ricevute in questa sessione (aprire le ricette di un membro chiede la sua). Un clic su un membro apre la sua lista (Back torna alla ricerca). La richiesta nativa "chi conosce questa ricetta" (`QueryGuildMembersForRecipe`) non si usa: la sua risposta non ha forma documentata **[verificare]** S3; si valuterà con i risultati di M0.4.

- **Aspetto (M6.13, [`ui-style.md`](ui-style.md) §3).** Le due modalità hanno la stessa intestazione (*Back*, *Who can craft* e il titolo, con la fonte sotto) e la stessa tabella. Nella lista di un membro la barra ha il `Kit.Select` della categoria; in "who can craft" il **chip** *Online only*. Il testo al posto delle righe (nessuna lista, in caricamento, nessun risultato) è il testo vuoto della tabella. La lista tiene il punto di scorrimento quando i dati cambiano (la tabella non torna in cima), e torna in cima con un altro membro, un'altra ricerca o un altro filtro. Il pulsante *Request craft* è un `Kit.Button` secondario nell'ultima colonna; il tooltip di una ricetta resta quello del gioco per il link dell'incantesimo (`Kit.Tooltip.Item`), quello di un artigiano è il tooltip dell'addon.

### 2.3 Richiesta di creazione (M3.6, PRO-05)

- Un pulsante **Request craft** compare su ogni ricetta dell'elenco di un membro e su ogni persona sotto una ricetta di "who can craft", **solo se il membro è online** e non è il giocatore. Non compare sulla riga d'intestazione della ricetta, sui membri offline (un sussurro non li raggiungerebbe) né sulle proprie ricette.
- Il clic apre la casella della chat con `/w <nome> Hello! Could you craft <link> for me? Thank you!` (`Recipes:OpenCraftRequest`, `Compat.Chat.OpenWhisper(nome, testo)`): **l'addon non invia nulla**, il giocatore legge, cambia se vuole e preme Invio. Il link è quello dell'incantesimo della ricetta (`C_Spell.GetSpellLink`, altrimenti costruito dal nome); una ricetta senza nome non si può chiedere. Il testo è nella lingua dell'interfaccia del giocatore. Un messaggio di chat ha al massimo 255 caratteri: più lungo non si apre.
- `CRAFT_REQUESTED(guid, recipeId)` va sul Bus (per M13, quando la richiesta diventerà un ordine registrato). Nessun dato di una richiesta viene salvato né condiviso.

## 3. Dimensioni

Una professione ha qualche centinaio di ricette: come spellID ordinati codificati a differenze occupano circa 1,5 byte per ricetta, circa 2 caratteri in Base64 ([SPEC-03 §3](SPEC-03-data-model.md#3-ricette-recipes)). Una gilda di 200 membri con 2 professioni e in media 150 ricette ciascuna sta intorno ai 120 KB in SavedVariables, 300 KB nel caso peggiore di liste da 400 ricette; un record non supera 8 KB e un messaggio con 400 ricette pesa circa 1 KB dopo la compressione.
