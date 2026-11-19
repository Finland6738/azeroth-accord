# SPEC-05: Roster esteso, alt e contatti

## 1. Tabella dei membri

| Colonna | Fonte | Note |
|---|---|---|
| Nome | `GetGuildRosterInfo` | colore della classe; icona "main" o "alt" |
| Livello, classe, grado, zona | `GetGuildRosterInfo` | |
| Ultimo accesso | `GetGuildRosterLastOnline` | "online" in evidenza |
| Professione 1, Professione 2 | `C_Club.GetMemberInfo` → `profession1Name/Rank`, `profession2Name/Rank` **[verificare]** S2; altrimenti i dati condivisi | cella cliccabile → ricette ([SPEC-06](SPEC-06-professions-recipes.md)) |
| Like | libro dei like ([SPEC-07](SPEC-07-reputation-social.md)): totale dell'account, verde se gli hai dato il like, grigio se il tuo like è in attesa | da M4.3, tra le colonne predefinite |
| Indice sociale | [SPEC-07](SPEC-07-reputation-social.md): l'indice, un trattino sotto le 5 ore | da M4.5, solo per chi vede l'indice degli altri (ufficiali e GM finché Q3 è aperta) |
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

Tabella (`UI/RosterModel.lua`, `UI/Roster.lua`, M2.3):

- Il **modello** non ha frame ed è provato da test: colonne (`name` sempre visibile; `likes`, `social` e `contacts` compaiono solo quando esiste il loro modulo, da M4 e M2.5), testo di ogni cella, ordinamento per ogni colonna (un valore mancante, per esempio nessuna professione, va sempre in fondo; a parità conta il nome), ricerca per nome e per professione, filtri online / classe / grado / professione / solo main, vista per account (ROS-02).
- **Vista per account**: una riga per account con il main in testa, il numero di alt e un pulsante `+` / `-`; gli alt sotto sono ordinati come ogni elenco e comprendono i personaggi fuori gilda (grigi, "not in guild"). Un account compare se **almeno un** suo membro soddisfa ricerca e filtri; "solo main" mostra la sola riga del main. Gli account si ordinano per il valore del main (per "ultimo accesso" vale il membro più recente dell'account).
- **Righe virtuali**: tanti frame quanto è alta la tabella più uno, riempiti di nuovo a ogni scorrimento (rotella o clic sulla barra); 1000 membri non creano 1000 frame.
- Scelte salvate per personaggio in `char.ui` (`columns`, `sort`, `grouped`); la vista osserva il roster mentre è visibile (`Roster:Watch`). Il clic su una riga seleziona il membro ed emette `ROSTER_SELECT(guid, entry)` sul Bus (la scheda di M2.4).

## 2. Scheda membro

Clic su un nome → scheda a destra (o sopra la tabella nella tab stretta): nome, classe, livello, grado, nota pubblica e (se visibile) nota ufficiali, professioni con link alle ricette, **personaggi dello stesso account**, contatti, like ricevuti, indice sociale con i compagni principali, versione dell'addon.

Realizzazione (`UI/MemberCard.lua`, M2.4):

- Il clic su una riga della tabella (`ROSTER_SELECT` sul Bus) apre la scheda **a destra** della tabella in un pannello largo almeno 760 px (la tabella cede 274 px), **sopra** la tabella in uno stretto (la tab della finestra Gilda), con un pulsante *Back*. La scheda è un frame a sé dentro la vista Roster, segue i dati (si ridisegna a `ROSTER_UPDATED` e `ACCOUNTS_UPDATED`) e si chiude se il membro esce dal roster o se cambia la gilda.
- `Card.Describe(voce)` è una funzione pura e coperta dai test: titolo e sottotitolo (livello e classe), sezioni **Details** (zona, online o ultimo accesso, grado, nota pubblica, nota ufficiali, addon e versione), **Professions** (ognuna con la fonte: "from the game", "shared by the member, 3 d ago", "read from your own character"; se mancano, il testo spiega perché), **Characters of the same account** e le sezioni che aggiungono i passi successivi con `Card.AddSection(id, ordine, fn)` (contatti in M2.5, like e indice sociale in M4); una sezione che dà errore si ignora.
- **Nota ufficiali** solo se `CanViewOfficerNote()` dice di sì, anche quando il client consegna il testo comunque. Senza quell'API la nota non si mostra.
- **Personaggi dello stesso account** (ACC-03): tutti gli altri personaggi del gruppo, il main con l'etichetta "main", quelli fuori dalla gilda in grigio con "not in guild", quelli dedotti da una nota con "declared in the note"; ogni riga è un pulsante che apre la scheda di quel personaggio (anche di uno fuori gilda, descritto da ciò che l'account elenca). Il main legge "This is the main character."

## 3. Personaggi dello stesso account

[ADR 0006](../adr/0006-account-token-and-always-shared-character-list.md):

- ACC-01: all'accesso con l'addon il personaggio si aggiunge a `chars` dell'account (SavedVariables per account).
- ACC-02: l'elenco si condivide **sempre** con la gilda (D3), insieme al main.
- ACC-03: la scheda mostra **tutti** i personaggi dell'account sul reame, anche quelli fuori gilda, con l'indicazione "in guild" / "not in guild".
- ACC-04: un personaggio cancellato o rinominato sparisce quando il suo account lo segnala (controllo all'accesso di ogni personaggio: i GUID che non rispondono a `C_PlayerInfo` per 30 giorni vengono tolti).
- ACC-05: per chi non ha l'addon si legge come suggerimento una nota pubblica nel formato `alt: <nome>` o `main: <nome>`, mostrata come "dichiarato nella nota".

Realizzazione (`Data/Accounts.lua`, M2.2):

- **Lato proprio** (ACC-01, ACC-02). Ogni personaggio che entra con l'addon si aggiunge a `AzerothAccordDB.chars[<reame>][<GUID>]` (nome, classe, livello, gilda, `added`, `seen`, `answered`). Otto secondi dopo l'accesso (a roster caricato), a ogni salita di livello e quando cambia il roster (al massimo ogni 10 minuti) il personaggio pubblica **il proprio** record `accounts` con token, elenco, main e versione; **un record identico non genera una nuova `rev`**. L'elenco è sempre condiviso (D3): non esiste nessuna impostazione per spegnerlo. L'elenco comprende i personaggi del reame e quelli visti nella stessa gilda su un altro reame, al massimo 40 e dentro il limite di dimensione dell'insieme; il personaggio stesso c'è sempre.
- **Main.** Scelta del giocatore (`Accounts:SetMain`, salvata per reame in `mains`), altrimenti il livello più alto e, a parità, il personaggio aggiunto per primo (il tempo giocato richiederebbe `/played`, che scrive in chat).
- **ACC-04, personaggi vecchi.** All'accesso ogni personaggio dell'elenco viene chiesto a `GetPlayerInfoByGUID` **[verificare]**: se risponde si aggiornano nome (rinomina) e livello; se non risponde da 30 giorni viene tolto, **ma solo dopo che l'API ha risposto almeno una volta per un personaggio diverso da quello connesso**: senza questa prova nulla viene mai tolto (un alt che non si gioca da mesi deve restare).
- **Lato altrui** (ACC-03). I gruppi si calcolano dai record della gilda con l'**elenco reciproco** ([ADR 0006](../adr/0006-account-token-and-always-shared-character-list.md), nota di M1.6): due personaggi sono dello stesso account solo se il record di ciascuno elenca l'altro (componenti connesse). Un record con l'elenco falsificato (elenca un personaggio che non lo elenca a sua volta) non unisce nulla. I personaggi **fuori dalla gilda** non possono pubblicare: compaiono come "reclamati" dai membri che li elencano (`claimed`, `inGuild = false`); un membro della gilda elencato senza reciprocità si ignora. Il token serve solo a mostrare e a collegare i contatti; se i membri di un gruppo pubblicano token diversi il gruppo è marcato `conflict`.
- **ACC-05, suggerimenti dalle note.** Per i membri senza record: `main: <nome>` nella nota pubblica = "il mio main è <nome>", `alt: <nome>` = "<nome> è un mio alt" (maiuscole indifferenti, all'inizio della nota). Il membro entra nel gruppo di quello nominato (o forma un gruppo con lui) con `hint = true`, e l'interfaccia scrive "declared in the note". Un personaggio con un proprio record non è mai spostato da una nota.
- API: `Accounts:GroupOf(guid)`, `Groups()`, `Alts(guid)`, `MainOf(guid)`, `TokenOf(guid)`; evento `ACCOUNTS_UPDATED` sul Bus.

## 4. Contatti

- CON-01: BattleTag letto con `BNet_GetBattleTagSelf()` **[verificare]** S8 e sempre condiviso (D3).
- CON-02: Discord dal campo nativo `discordInfo` se il server lo riempie **[verificare]** S2, altrimenti scritto dal giocatore nelle impostazioni (solo nome utente).
- CON-03: un clic sul contatto apre una casella con il testo già selezionato da copiare.
- CON-04: pulsante **Add BattleTag friend** con `C_Club.SendBattleTagFriendRequest(guildClubId, memberId)`, che funziona anche senza addon dall'altra parte **[verificare]** S8.

Realizzazione (`Data/Contacts.lua`, `UI/CopyBox.lua`, `UI/Settings.lua`, M2.5):

- **Record proprio** (CON-01, CON-02): un record `contacts` (id = GUID del personaggio) con `account` (token), `battleTag` (letto con `BNet_GetBattleTagSelf`, in alternativa `BNGetInfo` **[verificare]** S8) e `discord` (il nome scritto dal giocatore). Si pubblica dieci secondi dopo l'accesso, di nuovo dopo 70 s (il servizio Battle.net può partire tardi), a ogni `BN_CONNECTED` / `BN_INFO_CHANGED` e subito quando si salva il nome Discord; un record identico non genera una nuova `rev`; chi non ha né l'uno né l'altro non pubblica nulla, e chi toglie il proprio nome Discord pubblica un record svuotato per ritirare il vecchio valore. **Sempre condiviso** (D3): nessuna impostazione lo spegne.
- **Discord nativo** (CON-02): il campo `discordInfo` di `C_Club.GetMemberInfo` lo legge `Data/Roster.lua` per ogni membro, con o senza addon **[verificare]** S2; vince sul nome condiviso (ADR 0010) e la scheda scrive "(from the game)".
- **Impostazioni**: la vista *Settings* (`/accord settings`) mostra il BattleTag e ha il campo del nome Discord (2–32 caratteri, niente spazi, link, `@`, `/`, `|`); il testo dice che la condivisione è sempre attiva. Il valore sta in `AzerothAccordDB.settings.discord`.
- **Contatti di un account** (`Contacts:Of(guid)`): i record `contacts` più recenti tra i personaggi del gruppo ([SPEC-03 §2](SPEC-03-data-model.md)), BattleTag e Discord ciascuno dal più recente che sia valido.
- **Nulla di ricevuto si mostra com'è**: BattleTag e nome Discord degli altri passano per una validazione (forma del BattleTag, regole del nome Discord) e il carattere `|` si raddoppia, perché non possa aprire una sequenza di colore o di link nel testo del gioco; un valore non valido si ignora.
- **CON-03**: nella scheda un clic sul BattleTag o sul Discord apre la casella di copia (`CopyBox`): una riga con il testo già selezionato, di sola lettura, Esc la chiude.
- **CON-04**: il pulsante *[Add BattleTag friend]* compare per un membro della gilda che non è il giocatore (serve il suo `memberId` del club) quando `C_Club.SendBattleTagFriendRequest` esiste **[verificare]** S8; il clic chiama `SendBattleTagFriendRequest(club della gilda, memberId)` e scrive l'esito in chat (se il gioco rifiuta la chiamata lo dice). Funziona anche senza addon dall'altra parte.
- La colonna *Contacts* della tabella mostra "BT" e "DC".
