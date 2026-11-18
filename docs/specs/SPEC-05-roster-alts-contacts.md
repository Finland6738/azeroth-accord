# SPEC-05: Roster esteso, alt e contatti

## 1. Tabella dei membri

| Colonna | Fonte | Note |
|---|---|---|
| Nome | `GetGuildRosterInfo` | colore della classe; icona "main" o "alt" |
| Livello, classe, grado, zona | `GetGuildRosterInfo` | |
| Ultimo accesso | `GetGuildRosterLastOnline` | "online" in evidenza |
| Professione 1, Professione 2 | `C_Club.GetMemberInfo` → `profession1Name/Rank`, `profession2Name/Rank` **[verificare]** S2; altrimenti i dati condivisi | cella cliccabile → ricette ([SPEC-06](SPEC-06-professions-recipes.md)) |
| Like | libro dei like ([SPEC-07](SPEC-07-reputation-social.md)) | da M4 |
| Indice sociale | [SPEC-07](SPEC-07-reputation-social.md) | da M4 |
| Battle.net, Discord | `contacts` | icona copia |
| Addon | ha l'addon, versione | piccola icona |

- ROS-01: ordinamento per ogni colonna, ricerca per nome, filtri per online, classe, grado, professione, "solo main".
- ROS-02: vista **raggruppata per account**: una riga per account (il main) con gli alt sotto, espandibili.
- ROS-03: il roster si aggiorna su `GUILD_ROSTER_UPDATE` e chiede `C_GuildInfo.GuildRoster()` al massimo ogni 15 s.

Realizzazione (`Data/Roster.lua`, M2.1):

- Un solo elenco di membri, unito da quattro fonti ([ADR 0010](../adr/0010-native-data-first-shared-data-as-fallback.md)): *roster* (`GetGuildRosterInfo` + `GetGuildRosterLastOnline`), *club* (`C_Club.GetMemberInfo`: professioni, Discord, `memberId`, `bnetAccountId`, agganciato per GUID, altrimenti per nome), *condiviso* (i record `recipes` riempiono le professioni che il server non dà; i record `accounts` dicono chi ha l'addon e in che versione) e *proprio* (le professioni del giocatore, sempre native). Ogni professione porta la sua `source` (`native`, `shared`, `own`), così l'interfaccia dice da dove viene il dato.
- Costo: un passaggio sul roster e uno sul club, poi unioni per tabella hash: nessuna chiamata si ripete (1000 membri = 1000 `GetGuildRosterInfo` e 1000 `C_Club.GetMemberInfo`). Senza `GetGuildRosterInfo` il roster si costruisce dal solo club, con la classe ricavata dall'ID.
- L'elenco si ricostruisce **solo quando serve**: `GUILD_ROSTER_UPDATE`, i record condivisi e il cambio di gilda lo segnano "sporco"; chi lo legge lo ricostruisce, e mentre una vista lo osserva (`Roster:Watch`) una raffica di eventi dà una sola ricostruzione dopo 1 s (evento `ROSTER_UPDATED` sul Bus).
- ROS-03: `C_GuildInfo.GuildRoster()` si chiede al massimo ogni 15 s (`Roster:Request`), anche quando una vista inizia a osservare.
- Le capacità `clubProfessions` e `clubDiscord` (S2) passano a `available` appena un membro ha quei campi pieni; se nessuno li ha restano `unknown` e valgono i dati condivisi.

## 2. Scheda membro

Clic su un nome → scheda a destra (o sopra la tabella nella tab stretta): nome, classe, livello, grado, nota pubblica e (se visibile) nota ufficiali, professioni con link alle ricette, **personaggi dello stesso account**, contatti, like ricevuti, indice sociale con i compagni principali, versione dell'addon.

## 3. Personaggi dello stesso account

[ADR 0006](../adr/0006-account-token-and-always-shared-character-list.md):

- ACC-01: all'accesso con l'addon il personaggio si aggiunge a `chars` dell'account (SavedVariables per account).
- ACC-02: l'elenco si condivide **sempre** con la gilda (D3), insieme al main.
- ACC-03: la scheda mostra **tutti** i personaggi dell'account sul reame, anche quelli fuori gilda, con l'indicazione "in guild" / "not in guild".
- ACC-04: un personaggio cancellato o rinominato sparisce quando il suo account lo segnala (controllo all'accesso di ogni personaggio: i GUID che non rispondono a `C_PlayerInfo` per 30 giorni vengono tolti).
- ACC-05: per chi non ha l'addon si legge come suggerimento una nota pubblica nel formato `alt: <nome>` o `main: <nome>`, mostrata come "dichiarato nella nota".

## 4. Contatti

- CON-01: BattleTag letto con `BNet_GetBattleTagSelf()` **[verificare]** S8 e sempre condiviso (D3).
- CON-02: Discord dal campo nativo `discordInfo` se il server lo riempie **[verificare]** S2, altrimenti scritto dal giocatore nelle impostazioni (solo nome utente).
- CON-03: un clic sul contatto apre una casella con il testo già selezionato da copiare.
- CON-04: pulsante **Add BattleTag friend** con `C_Club.SendBattleTagFriendRequest(guildClubId, memberId)`, che funziona anche senza addon dall'altra parte **[verificare]** S8.
