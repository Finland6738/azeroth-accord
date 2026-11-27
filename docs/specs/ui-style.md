# Stile dell'interfaccia: la famiglia di FDCP

> Specifica del passo **M6.8**. Vale per M6.9 (media e font), M6.10 (tema), M6.11 (widget), M6.12 (finestra e schede),
> M6.13 e M6.14 (viste), M6.15 (Info e crediti), M6.16 (anteprime). Decisione in
> [ADR 0021](../adr/0021-interface-follows-the-ecosystem-style-of-fdcp.md).
>
> **Dal 2026-11-27** la struttura (ruoli di colore, stati, forme, tipografia, misure dei componenti) segue le regole di
> **Material 3** di [§9](#9-le-regole-di-material-3-adr-0027) ([ADR 0027](../adr/0027-material-3-rules-adapted-to-accord.md)):
> dove §3 dice altro su misure e stati, vale §9.

## 0. Base e come si legge

La **base** è `docs/specs/ui-style.md` di Finland Dragon Credit Points (FDCP), nel repository fratello
`../finland-dragon-credit-points`: lo stesso proprietario, GPL-3.0, lo stile del sito della community NEBULA. Questo
documento **non lo ripete**: scrive solo le **differenze**. Dove qui non si dice nulla, vale FDCP così com'è: token
(§2), componenti e come si costruiscono in gioco (§3), font e licenze (§4), verdetti di fattibilità (§5), forme,
ombre, movimento e spaziatura (§2.2), texture e prestazioni (§7).

FDCP si **legge soltanto**: non si modifica mai e non diventa una libreria condivisa. I suoi file si **copiano e si
adattano** ai nomi di Accord ([ADR 0021](../adr/0021-interface-follows-the-ecosystem-style-of-fdcp.md)). Regole che
restano quelle di sempre: nessuna arte di Blizzard nel repository, nessun testo scritto nel codice (ogni stringa è
una chiave di locale, `enUS` e `itIT`), nessun colore scritto fuori da `UI/Theme.lua`.

## 1. Nomi e prefissi

| Cosa | FDCP | Azeroth Accord |
|---|---|---|
| Cartella dell'addon e percorso dei media | `FinlandDragonCreditPoints/Media/` | `AzerothAccord/Media/` (`Interface\AddOns\AzerothAccord\Media\`) |
| Tabella globale dei dati salvati | `FDCPDB` | `AzerothAccordDB` (account) e `AzerothAccordCharDB` (personaggio), come in [SPEC-03](SPEC-03-data-model.md) |
| Oggetti font (`CreateFont`) | `FDCPFont<Id>` | `AzerothAccordFont<Id>` (`Display`, `Title`, `Body`, `Medium`, `SemiBold`, `Mono`, `MonoMedium`, `Eyebrow`, `Header`…, gli stessi `<Id>` di FDCP) |
| Spazio dei nomi del codice | `FDCP.Theme`, `FDCP.Assets`… | `ns.Theme`, `ns.Assets`, `ns.Motion` e, per i widget, `ns.Widgets` (fino a M6.14 si chiamava `ns.Kit`; `ns.addon.Theme`… per i test, come in FDCP) |
| Nomi dei frame globali | `FDCP…` | `AzerothAccord…` |
| Chiavi di locale | quelle di FDCP | quelle di Accord (`Locale/enUS.lua`, `itIT.lua`); i testi nuovi di questa famiglia (temi, Aspetto, Info, crediti) hanno chiavi proprie e un test controlla che nulla arrivi a schermo senza chiave (M6.14) |
| Slash command | `/fdcp` | `/accord`, `/acc` (invariati, [SPEC-04 §4](SPEC-04-ui-guild-tab-shell.md)) |

I file media hanno gli stessi nomi di FDCP (`rr_fill_8`, `shadow`, `glow_s`, `logo_256`, `icons`…) più i loghi NEBULA
(§5). `UI/Assets.lua` resta la tabella unica di texture e font; `tools/check_addon.py` controlla che ogni file di
`Media/` sia in tabella e in `docs/third-party.md` (M6.9).

## 2. Dove si salvano le impostazioni dell'aspetto

FDCP le salva per personaggio; **Accord le salva per account**, perché tema e font sono gusti della persona, non del
personaggio, e le impostazioni personali di Accord (notifiche, Discord) stanno già lì
([SPEC-04 §6](SPEC-04-ui-guild-tab-shell.md#6-impostazioni-m61)).

| Chiave | Valori | Predefinito |
|---|---|---|
| `account.settings.theme` | `nebula`, `aurora`, `accord` | `nebula` |
| `account.settings.effects` | booleano: bagliori e testo neon | `true` |
| `account.settings.animations` | booleano: tutto il movimento di `Motion` | `true` |
| `account.settings.font` | `addon` (Orbitron, Outfit, JetBrains Mono) o `game` (font del gioco) | `addon` |

- Le chiavi entrano in `Config.SCHEMA` con tipo ed enumerazione (un valore sbagliato torna al predefinito), e in
  `Config` nasce una **migrazione di schema da 1 a 2** (M6.10): aggiunge i quattro valori agli account esistenti senza
  toccare altro ([ADR 0011](../adr/0011-embedded-ace3-savedvariables-and-schema-versions.md)). Un account con schema
  più nuovo resta in sola lettura, come oggi.
- Le legge `Theme` (`Theme.Load`, `Theme.EffectsOn`, `Theme.AnimationsOn`) all'accesso. Il cambio si vede **subito**,
  senza `/reload`, tranne il font: un file di font nuovo si legge solo al riavvio del client, e il manuale lo dice.
- Si cambiano dalla scheda **Aspetto** di Settings (M6.14). Una modifica emette `SETTINGS_CHANGED` come le altre.
- La posizione e la dimensione della finestra restano per personaggio (`char.ui`), come ora.

**Stato (M6.10).** Fatto: le quattro chiavi sono in `Config` (regole con enumerazione, predefiniti, migrazione 1 → 2 idempotente per l'account; il passo 2 del personaggio non cambia nulla e porta solo la versione a 2). `Config:Set` emette `CONFIG_CHANGED(percorso)` sul Bus e `UI/Theme.lua` lo ascolta: tema, effetti e font si vedono subito (il font, come detto sopra, si rilegge davvero solo al riavvio); `Theme.Apply` emette `THEME_CHANGED(idTema)`. `Theme.Set(id)` salva e applica un tema; `Theme.EffectsOn()` e `Theme.AnimationsOn()` leggono gli interruttori (rispondono «sì» finché i dati non sono caricati). Gli `<Id>` dei font sono quelli di FDCP: `Display`, `DisplaySmall`, `H1`, `H2`, `Body`, `BodyMedium`, `Small`, `Eyebrow`, `Th`, `Tab`, `Button`, `Mono`, `MonoMedium`, `MonoSmall` (oggetti `AzerothAccordFont<Id>`). La scheda Aspetto che li cambia e il relativo `SETTINGS_CHANGED` sono arrivati con M6.14 (vedi lo stato di M6.14 in §3).

## 3. Le viste come schede

Le cinque viste diventano le **schede** orizzontali di FDCP §6 (sostituiscono la navigazione a sinistra di
[SPEC-04 §2](SPEC-04-ui-guild-tab-shell.md#2-il-pannello)):

| Scheda | Vista | Note |
|---|---|---|
| **Roster** | Roster, scheda membro | selettore a pillole per raggruppato / tabella dove serve |
| **Professions** | professioni, ricette, "who can craft" | |
| **Reputation** | like, indice sociale, mappa dei gruppi | |
| **Bank** | i sette modi della banca | |
| **Settings** | Impostazioni | **selettore a pillole** a due segmenti: *Settings* e *Info* (crediti, [M6.15](../roadmap/M6-release.md)); l'Aspetto è una card della prima |

Restano vere le regole attuali: una vista non ancora pronta non compare, la scheda scelta per ultima si ricorda per
personaggio (`char.ui.lastView`), una vista che solleva un errore mostra il suo testo di errore e non toglie le altre,
i badge (richieste della banca) stanno sul titolo della scheda.

**Lo stesso pannello in due contenitori** ([ADR 0003](../adr/0003-accord-tab-in-the-guild-window.md)):

| | Finestra autonoma | Dentro la finestra Gilda |
|---|---|---|
| Cornice | finestra propria come FDCP §6: **barra del titolo di 52 pt** (logo, "AZEROTH ACCORD" in Orbitron, stato della sincronizzazione, Pop in, chiudi), raggio 12, ombra, mobile, Esc | la finestra Gilda **vestita del tema** finché la linguetta Accord è aperta (M6.18, sotto): cornice tematica con raggio 12 e ombra, il nome della gilda al posto del titolo, la croce del tema, le linguette come tessere; il pannello riempie l'area dei contenuti di `CommunitiesFrame` |
| Schede | barra delle schede da 48 pt sotto il titolo, con l'indicatore da 3 pt (§9.6) | la stessa barra delle schede, in cima al pannello |
| Ricerca globale | a destra della barra delle schede | uguale |
| Dimensione | 1380 × 720 predefinita dal 2026-11-27 (era 920 × 600, troppo stretta per il Roster nel gioco), mai più larga dello schermo; minimo 720 × 460, ridimensionabile (confermata in M6.12; era 640 × 400 in SPEC-04 §3) | quella dell'area di Blizzard, senza ridimensionare |
| Ricordo | posizione e dimensione per personaggio | nessuno |

**La finestra Gilda nel tema (M6.18, `UI/GuildSkin.lua`).** Il proprietario ha chiesto che tutto ciò che il giocatore vede
sia nel nuovo aspetto, anche il nome, la cornice e le linguette a lato: finché il pannello Accord è aperto, la finestra
`CommunitiesFrame` è vestita del tema. L'addon **non sostituisce né chiama funzioni di Blizzard** (nessuna
`SetDisplayMode`, nessun `hooksecurefunc` in più: ADR 0003, GT-04): rende **trasparenti** (`SetAlpha(0)`, il valore vecchio è
ricordato e rimesso) le parti grafiche della cornice di Blizzard e disegna dietro e sopra frame propri.

- *Cornice.* Si azzerano l'alfa delle texture della finestra, di `NineSlice`, `TitleContainer`, `PortraitContainer` e, nell'`Inset`,
  di `NineSlice` e `Bg`; dietro si disegna un frame dell'addon (`Theme.Panel`: riempimento `bg`, anello `border`, raggio 12,
  ombra e luce alta), con il logo da 24 pt e il **nome della gilda** in `H1` `text-1` e una linea `border-subtle` sotto
  (44 pt di titolo).
- *Croce.* Il pulsante di chiusura di Blizzard resta quello che chiude (le sue texture diventano trasparenti); sopra di esso un
  frame senza mouse porta la croce dell'icona `cross` (`text-2`, `text-1` al passaggio).
- *Linguette a lato.* Le quattro di Blizzard (finché la linguetta Accord è aperta) e la nostra (sempre) hanno una **tessera** da
  44 pt (`surface-2`, anello `border`; scelta: `secondary-container` senza anello né bagliore, M12.8): delle linguette di Blizzard si
  rendono trasparenti tutte le texture tranne l'icona, che resta (è ciò che la linguetta fa). La nostra è un pulsante semplice
  con il logo tondo, senza il modello di linguetta di Blizzard, e porta il segno con il conteggio delle richieste.
- *Quando.* La veste si mette quando si apre il pannello Accord e si toglie (alfa ripristinato, frame nascosti) quando si
  sceglie una linguetta di Blizzard, si chiude la finestra o si cambia comunità: i contenuti di Blizzard (chat, roster, vantaggi)
  restano sulla loro grafica. Il tema cambiato si vede subito.
- *Prudenza.* Ogni parte è cercata per nome sotto `pcall`: una finestra con un'altra struttura fa perdere una parte
  dell'aspetto, mai un errore; `/accord debug` (sezione "Guild window skin") dice quante parti ha trovato. **Non verificato nel
  client**: i nomi delle parti (§7).

L'area dentro la finestra Gilda è stretta: le tabelle usano le
colonne scelte dal giocatore e il pulsante **Pop out** apre la stessa vista nella finestra autonoma, più larga.

Densità: come FDCP (righe di 36-40 pt, testo 13 pt). Una gilda di 1000 membri resta sulle righe riciclate da un pool
(DataTable, M6.11): nessuna regione creata durante un aggiornamento.

**Stato (M6.11).** Fatto: i widget di FDCP §3 sono in `UI/Widgets/` (`Core.lua`: Button, Card, Badge, Tabs, Segmented,
Chip, TitleBar, Dialog, EditBox, ChoiceList; `Controls.lua`: Switch, Slider, Select, Snackbar, Skeleton, ClassMark;
`DataTable.lua`, `ThinBar.lua`, `Tooltip.lua`). Scelte, tutte da provare in gioco:

- **Nome.** Il vecchio aspetto (`UI/Widgets/Base.lua`, usato da tutte le viste) teneva `ns.Widgets` fino a M6.14, e i
  nomi coincidevano (`Button`…): i widget nuovi stavano in **`ns.Kit`**. M6.14 ha tolto `Base.lua` e rinominato `Kit` in
  `Widgets` (vedi lo stato di M6.14); qui sotto i nomi `Kit.` sono quelli di allora.
- **DataTable senza ScrollBox.** Come in FDCP la tabella è un pool proprio di righe, con la **rotellina**, che si
  comporta allo stesso modo su ogni client: non serve né `ScrollBox`/`DataProvider` né il ripiego `FauxScrollFrame` (la
  riga «ScrollBox + DataProvider» del verdetto di §5 si legge così). L'intestazione sta fuori dalla lista, la colonna
  ordinata ha freccia e `accent-text`, un indicatore sottile a destra mostra dove si è in una lista lunga (non si trascina).
  Un ordinamento calcola la chiave di ogni riga una volta sola; un aggiornamento o uno scorrimento riempie al massimo il
  pool (40 righe, che cresce fino a 100 solo se la finestra si fa più alta) e non crea regioni. Le colonne fisse e
  flessibili restano; le colonne **fisse a sinistra e a destra come liste sincronizzate** non sono state fatte (nessuna
  vista di Accord ne ha bisogno: i pannelli sono stretti e le colonne le sceglie il giocatore).
- **Schede.** *Superato da [§9.6](#96-componenti) con M12.7: niente riquadri, tinta né badge `accent`.* Dal 2026-11-27 (proprietario) le schede delle viste sono **riquadri arrotondati** (`surface-2`, anello
  `border-subtle`) con l'**icona** della vista (dal foglio delle icone dell'addon, `Shell.VIEW_ICONS`) prima del nome;
  i riquadri sono tutti uguali e quella attiva si distingue solo come nelle schede di Material Design 3: la
  **sottolineatura `accent` da 2 pt** in fondo al suo riquadro (scorre da una scheda all'altra) e nome e icona in
  `accent-text` invece di `text-2` / `text-3` (prima `text-1`: il proprietario non la distingueva, "non è arancione"), con
  il riquadro velato d'`accent` al 18 %; niente bagliore né anello colorato (`Widgets.Tabs(..., { boxed = true })`). Le
  pagine della Banca stanno in una card `surface-1` con anello `border-subtle`, a 14 pt dal bordo, e l'elenco degli
  oggetti ha un'intestazione come la DataTable. Senza `boxed` resta la barra con l'indicatore da 2 pt, che **scorre** da una
  scheda all'altra in 200 ms (`Translation`, poi si posa) e si dissolve solo alla prima comparsa; una scheda può avere un **badge con il conteggio** (le richieste in attesa della
  Banca: `Tabs:SetBadge(id, testo|nil, tono)`; il testo lo passa il chiamante).
- **Tooltip.** *Le due forme di oggi sono in [§9.6](#96-componenti) (M12.7).* Un solo frame proprio dell'addon (`AzerothAccordTooltip`, strato `TOOLTIP`, creato al primo uso): dal
  2026-11-27 un riquadro scuro, fondo `surface-1` con anello `border`, il titolo in `accent-text` e le righe in `text-1`
  (prima era invertito: fondo `text-1`, testo `bg`); i conteggi di una o due cifre sono pallini tondi; larghezza fino a 280 pt, il mouse lo attraversa. `Tooltip.Attach(frame, testo|righe|funzione)`;
  il `GameTooltip` del gioco solo per gli oggetti (`Tooltip.Item`, `AttachItem`) e mai riskinnato.
- **Testi e colori.** Un widget non contiene frasi: ogni testo lo passa il chiamante già tradotto; ogni colore è un
  token del tema, tranne il bianco dello strato di passaggio del mouse (`-- theme-ok`). `tools/check_addon.py` fallisce
  su un testo o un colore scritti dentro i cinque file.
- **Segno di classe.** Il quadratino con bagliore resta nascosto finché `PaintClassMark` non gli dà il colore del
  gioco (che `Theme.Apply` non tocca); `ClearClassMark` lo nasconde di nuovo per le righe riciclate.

**Stato (M6.12).** Fatto: `UI/Window.lua` e `UI/Shell.lua` usano il kit e il tema; le proposte di M6.8 sono confermate
(920 × 600, minimo 720 × 460; ricerca a destra delle schede; nessuna barra del titolo nella finestra Gilda). Scelte:

- **Stato della sincronizzazione.** Nella finestra autonoma è il sottotitolo mono della barra del titolo; nella finestra
  Gilda, che non ha barra del titolo, è una riga sottile (24 pt, `MonoSmall`, `text-3`) in fondo al pannello.
- **Pop in.** Pulsante *ghost* a sinistra della chiusura, visibile solo mentre la finestra Gilda è aperta sulla gilda
  (la linguetta Accord è visibile): rimette il pannello nella finestra Gilda e chiude la finestra autonoma. L'addon non
  apre mai la finestra di Blizzard (ADR 0003). Anche un clic sulla linguetta chiude la finestra autonoma: il pannello non
  resta mai in due posti, né la finestra aperta e vuota.
- **Ricerca.** Un `EditBox` del kit (segnaposto *Search*), 200 pt nella finestra e 150 pt nella finestra Gilda; visibile
  solo mentre la vista aperta ha `search = true` (Settings non ce l'ha). Pop out (secondario) le sta a destra, solo nella
  finestra Gilda.
- **Schede.** `Kit.Tabs` prende le schede quando nasce: una vista che si registra dopo fa nascere una barra nuova. Il
  conteggio della Banca è un badge `accent` (`99+` oltre 99), non più "(n)" nel nome. Un clic sulla scheda di una vista
  fallita la ricostruisce.
- **Cornici.** Finestra: `Theme.Panel` raggio 12, riempimento `bg`, bordo `border`, ombra, linea di luce in alto.
  Finestra Gilda: una texture quadrata `bg` (gli angoli dell'area di Blizzard restano coperti), nessun bordo. La maniglia
  di ridimensionamento è l'icona `dashed` del foglio delle icone (`text-3`, `accent-text` sotto il mouse), nessuna
  texture di Blizzard.
- **Linguetta.** Icona invariata (SPEC-10 Q2); il badge delle richieste è il badge del kit (`err` / `on-error`, M12.8).
- Le viste (corpo del pannello) restano col vecchio aspetto fino a M6.13-M6.14 (M6.13 ha fatto Roster, scheda e Professions): ognuna riceve un frame semplice che
  riempie il corpo, con 16 pt di margine.

**Stato (M6.13).** Fatto: Roster, scheda membro e Professions usano il kit (`UI/Roster.lua`, `UI/MemberCard.lua`,
`UI/CopyBox.lua`, `UI/Professions.lua`; nessuno usa più `ns.Widgets` né `ns.Skin`). Il kit è cresciuto di due cose
(restano compatibili con i test di M6.11):

- **`DataTable` con ordinamento del chiamante e colonne variabili.** `opts.onSort(id)`: il clic su un'intestazione
  chiama il chiamante, `SetData` conserva l'ordine ricevuto e il punto di scorrimento, `SetSortMark(id, discendente)`
  disegna la freccia (il Roster ordina nel proprio modello, che raggruppa per account). `SetColumns(colonne)`: un altro
  insieme di colonne riusando intestazioni e celle (il selettore delle colonne del Roster). `SetData(lista, true)`
  conserva il punto di scorrimento anche in una tabella che ordina da sola (Professions). Il testo vuoto va a capo.
- **`Kit.Menu`** (`Controls.lua`): un elenco a comparsa di voci con la spunta (`checked`, `keepOpen`, `header`), senza
  `UIDropDownMenu`; sostituisce `W.ShowMenu` nelle viste di M6.13 (e in Settings da M6.14).

I filtri a scelta singola sono `Kit.Select` (la prima voce è "tutti"), quelli sì/no `Kit.Chip`. Scelte: la riga del Roster è alta 28 pt (era 18) e la tabella mostra meno righe, ma si legge; la barra degli strumenti
va a capo se non c'è posto (pannello stretto, scheda aperta); la scheda scorre con la rotellina (le sezioni sono in un
frame che taglia). **Non provato nel client:** l'aspetto reale (9-slice, bagliori, quadratino di classe), il taglio dei
figli (`SetClipsChildren`) nella scheda, la rotellina sulla scheda e sulle liste, il popup del `Kit.Menu` e dei `Kit.Select`
sopra la finestra Gilda, la larghezza della barra con le schede in italiano, il tooltip dell'addon sulle righe.

**Stato (M6.14).** Fatto: tutte le viste usano il kit e il tema; `UI/Skin.lua` e `UI/Widgets/Base.lua` non esistono più
e il kit si chiama **`ns.Widgets`** (`AzerothAccord.Widgets` nei test; nei file la variabile locale è `Widgets`).

- **Reputation** (like, indice sociale, mappa dei gruppi, compagni suggeriti) e **Bank** (le sette modalità): le
  modalità sono una fila di **chip** (`Widgets.ChipRow`, nuovo: uno selezionato, `:SetItems`, `:Select`, `.buttons`),
  e così le schede della banca, il periodo e l'ordine delle donazioni e il tipo di richiesta. Gli elenchi restano pool di
  righe propri (righe da 28-30 pt, `Widgets.RowHover`, l'ultima riga tagliata da `SetClipsChildren`); i like hanno
  l'intestazione della `DataTable` (Th, `text-3`, la colonna ordinata in `accent-text`). La mappa dei gruppi è una card;
  i colori dei gruppi sono token (`Theme.SERIES`: `accent`, `neon`, `ok`, `warn`, `accent-2`, `grad-4`, `err`,
  `text-3`). Le caselle della banca sono quadrati arrotondati `surface-2` con il bordo `accent` al passaggio del mouse;
  il grafico del denaro è una card con barre `accent`; il modulo delle richieste è una card con tre `Widgets.EditBox` e
  i due filtri sono chip. Il tooltip di una richiesta è quello dell'addon; quello degli oggetti resta quello del gioco.
- **Settings**: una colonna di card che prende l'altezza di ciò che mostra (`stackCard`), con la nuova card **Aspetto**
  in cima: tema (un `Widgets.Segmented` Nebula / Aurora / Accord), effetti neon e animazioni (`Widgets.Switch`), font
  (Segmented: font di Accord / font del gioco). Ogni modifica passa da `SettingsModel.SetLook(chiave, valore)`:
  `Config:Set` (che emette `CONFIG_CHANGED`, così `Theme` ridipinge subito) e poi `SETTINGS_CHANGED(chiave)`. Le notifiche
  sono interruttori, le colonne del Roster chip; il menu del main è `Widgets.Menu`. `SettingsView.AddPage(id, def)`
  prepara le sotto-pagine (il selettore a pillole compare dalla seconda pagina: M6.15 aggiunge *Info*).
- **Diagnostica**: la finestra di `/accord debug` è un `Widgets.Dialog` come la `CopyBox`.
- **Scheda nella finestra Gilda**: l'icona è il logo dell'addon (SPEC-10 Q2) e il tooltip quello dell'addon.
- **Colori**: `tools/check_addon.py` ha `check_ui_colours` (come FDCP): nessun colore esadecimale, codice `|c`, numero dato
  a un `Set…Color`/`SetColorTexture`/`SetGradient`/`CreateColor` o riga di tooltip colorata con numeri fuori da
  `UI/Theme.lua`; `-- theme-ok` esenta una riga. I colori del tooltip del gioco (bianco, grigio, oro) vengono da
  `Theme.GameColor`; il colore di classe da `Widgets.PaintName` (`Theme.ClassText`), quello di qualità da `Theme.TextRGB`.
- **Testi**: `Tests/test_ui_texts.lua` controlla che nessun file di `UI/` dia a un widget una parola propria e che un
  client italiano mostri, in ogni vista, modalità, scheda e finestra, solo pezzi di stringhe italiane e i dati della
  gilda (nomi, oggetti, gradi, zone, classi del gioco, nomi degli insiemi di dati salvati).

**Non provato nel client:** l'aspetto reale di tutte queste viste (9-slice, chip, interruttori, card che si adattano
all'altezza del testo: in gioco `GetStringHeight` dipende dal font), lo scorrimento e il taglio degli elenchi, il
cambio di tema, effetti, animazioni e font dalla card Aspetto senza `/reload`, la pagina nella finestra Impostazioni del
gioco (sfondo `bg` dentro la cornice di Blizzard), il logo come icona della scheda della finestra Gilda.

## 4. I tre temi

- **Nebula** (predefinito, scuro) e **Aurora** (chiaro): **i token di FDCP §2.1, invariati**. Le due famiglie devono
  sembrare una sola, quindi nessun valore cambia.
- **Accord** (scuro): terzo tema, dalla palette del logo dell'addon (`assets/logo-source.webp`: fondo verde-petrolio
  scuro con nebbia verde, cornice e stendardo oro, bagliori menta), come il tema "Drago" di FDCP nasce dal suo logo.
  **Prende il posto di "Drago"**: Accord non ha un tema Drago. I **nomi dei token sono quelli di FDCP** (la tabella dei
  token è la stessa, cambia solo una colonna di valori).

### 4.1 Token del tema Accord

| Token | Accord | Uso (come in FDCP §2.1) |
|---|---|---|
| `bg` | `#04171A` | fondo della finestra |
| `surface-1` | `#0A2327` | card, barra del titolo, schede |
| `surface-2` | `#102E31` | intestazioni di tabella, campi, riga al passaggio del mouse |
| `surface-3` | `#16393B` | chip, pastiglia del totale, pulsante secondario |
| `raised` | `#1D4546` | segmento selezionato, toast |
| `border-subtle` | `rgba(232,243,236,.08)` | divisori di riga, bordo card |
| `border` | `rgba(232,243,236,.14)` | bordo finestra, campi |
| `border-strong` | `rgba(232,243,236,.26)` | card aperta o al passaggio del mouse |
| `text-1` / `text-2` / `text-3` | `#E8F3EC` / `#BFD6CB` / `#8FB0A3` | testo principale, secondario, attenuato |
| `on-accent` | `#261C00` | testo sul pulsante principale |
| `accent` | `#D9B54E` | l'oro dello stendardo: selezione, indicatore della scheda, pulsante principale |
| `accent-hover` | `#E8CB72` | passaggio del mouse sull'accento |
| `accent-text` | `#D9B54E` | numeri, sopratitoli, colonna ordinata |
| `accent-2` | `#4FBF8E` | secondo colore del gradiente del pulsante (verde menta) |
| `neon` / `neon-core` | `#7DE8B5` / `#3FB07F` | un solo elemento neon per vista: il bagliore menta del logo |
| `ok` / `warn` / `err` | `#5CCB8D` / `#F2B33D` / `#FF6B5E` | stati, annullamenti |
| `highlight` | `rgba(255,255,255,.06)` | riga di luce di 1 px in cima alla card |
| `scrim` | `rgba(1,10,12,.72)` | velo dei dialog |
| `grad-1` … `grad-4` | `#D9B54E → #9FE3A8 → #4FBF8E → #1F7A64` | barre sottili, timer (oro → menta → verde) |

I valori sono stati scelti guardando il logo (l'oro `#C9B562` e il fondo `#031D1E` sono i colori dominanti dell'immagine):
l'oro è più chiaro e saturo del colore medio dello stendardo per reggere il testo, il fondo è più scuro di quello del
logo per dare ai gradini di superficie lo spazio che hanno in Nebula. Il tema è scuro: effetti neon, bagliori `ADD` e
testo neon del titolo come in Nebula; i colori di classe restano quelli del gioco.

### 4.2 Contrasto

Calcolato con la formula WCAG 2.x (luminanza relativa, `(L1+0,05)/(L2+0,05)`), con le stesse regole di
`Tests/test_theme.lua` di FDCP, che il test di Accord (M6.10) ripete per i tre temi. Il valore è il **peggiore** fra
le superfici indicate:

| Regola | Minimo | Peggiore caso (Accord) |
|---|---|---|
| `text-1` e `text-2` su ogni superficie (`bg`, `surface-1/2/3`, `raised`) | 4,5:1 | `text-2` su `raised`: **6,88** (`text-1`: 9,27) |
| `text-3` su `bg`, `surface-1`, `surface-2` | 3:1 | **6,11** |
| `accent-text` su `bg`, `surface-1`, `surface-2` | 4,5:1 | **7,32** |
| `on-accent` su `accent` | 4,5:1 | **8,55** |
| `ok`, `warn`, `err` su `surface-1` | 4,5:1 | `err`: **5,86** (`ok` 8,09, `warn` 8,80) |
| `ok`, `warn`, `err` su `surface-3` e `raised` | 3:1 | `err`: **3,77** (`ok` 5,21, `warn` 5,67) |
| `accent` su `bg` (elementi non testuali) | 3:1 | **9,34** |

Tutte le regole sono rispettate con margine; nessun valore va corretto. I valori sono ricalcolati dal test
reale di M6.10 (`Tests/test_theme.lua`: tabella di questa pagina e `UI/Theme.lua` dicono la stessa cosa, e i peggiori casi sono quelli della tabella).

## 5. Logo e crediti

| Elemento | Dove |
|---|---|
| Logo dell'addon (`assets/logo-source.webp`) | barra del titolo, voce nell'AddOn Compartment e icona della finestra; texture `logo_256` e `logo_64` generate da `tools/make_media.py` (M6.9). Proposta al proprietario per l'icona della linguetta nella finestra Gilda: [SPEC-10 Q2](SPEC-10-risks-open-questions.md), il logo al posto dello stendardo del client |
| Loghi NEBULA (`assets/nebula-logo-dark.png`, `assets/nebula-logo-light.png`) | solo nei crediti (Info, M6.15): quello scuro nei temi scuri (Nebula, Accord), quello chiaro in Aurora; usati con il permesso della gilda |
| Crediti | "Created and designed by Finland", "Made with the Italian guild NEBULA", link alla pagina di NEBULA, Ko-fi, repository e segnalazioni (caselle di sola lettura da copiare), licenza GPL-3.0, `docs/third-party.md`, avviso di fan-made non affiliato a Blizzard |

Nessuna arte di Blizzard nel repository. Il nome pubblico è solo "Finland": nessun nome reale, e-mail o percorso
personale in nessun file ([CLAUDE.md](../../CLAUDE.md), privacy).

## 6. Quale sezione di FDCP usa ogni passo

| Passo | Sezioni di FDCP `ui-style.md` | Sezioni di questo documento |
|---|---|---|
| **M6.9** media, font, licenze | §4 (font e licenze), §7 (texture e prestazioni), §3 "Icone" | §1, §5 |
| **M6.10** tema, asset, movimento | §2 (token, forme, movimento, tipografia), §7, §9 (Glow, TextGlow, Px, Motion) | §1, §2, §4 |
| **M6.11** widget | §3 (tutta la tabella dei componenti), §5 (verdetti) | §1 |
| **M6.12** finestra, barra del titolo, schede | §6 (finestra e schede), §3 "Finestra", "Barra del titolo", "Schede" | §3 |
| **M6.13** viste 1: Roster, scheda membro, Professions | §3 (Tabella, Card, Badge, Chip, Nome di classe), §6 | §3 |
| **M6.14** viste 2: Reputation, Bank, Settings, rimozione del vecchio aspetto | §3 (Switch, campi, slider, Dialog, Tooltip), §9 ("Colori solo nel tema") | §2, §3 |
| **M6.15** Info e crediti | §3 (Card, pillole), `UI/Windows/About.lua` | §5 |
| **M6.16** anteprime e controllo del rilascio | §8 (anteprime) | §4, §5, §8 |

## 7. Cosa non è verificato nel client

Questa specifica è solo documentazione: **nulla è stato provato nel client vero**. Come in FDCP §7, da provare in
gioco ancora prima di fidarsi dei dettagli: caricamento di TGA e font su Forever (M6.9); qualità del 9-slice a scala
frazionaria e `Px()` a più scale dell'interfaccia; fusione `ADD` dei bagliori; propagazione del colore degli oggetti
font; menu senza `UIDropDownMenu` (il template `ScrollBox` e il ripiego `FauxScrollFrame` non servono più: DataTable è un pool
proprio, §3). In più, per Accord:

- la **veste della finestra Gilda** (M6.18): i nomi delle parti di `CommunitiesFrame` che si rendono trasparenti (`NineSlice`, `TitleContainer`, `PortraitContainer`, `CloseButton`, le texture proprie), se Blizzard le rimostra da sé, l'aspetto delle tessere delle linguette e che nessun taint compaia;
- il pannello a tinte di tema **dentro** `CommunitiesFrame` (sfondo, ordine degli strati sopra `Inset`, clic, ridimensionamento della finestra Gilda) senza taint e senza nuovi errori in combattimento;
- l'aspetto del tema **Accord** su schermo (i colori sono scelti da un'immagine, non da una prova);
- la dimensione della finestra autonoma, la ricerca accanto alle schede e lo spazio delle cinque schede (anche in italiano) con ricerca e Pop out nell'area stretta della finestra Gilda (scelte in M6.12);
- il logo come icona del Compartment e della linguetta;
- la leggibilità di Orbitron e degli accenti italiani nel titolo.

Le anteprime ([ADR 0019](../adr/0019-design-previews-original-art-invented-data.md)) sono ridisegnate nel nuovo
aspetto (M6.16, §8) e restano disegni, non screenshot.

## 8. Anteprime e confronto con FDCP (M6.16)

Le anteprime di progetto ([`mockups/`](mockups/README.md), [ADR 0019](../adr/0019-design-previews-original-art-invented-data.md)) sono
disegnate nel nuovo aspetto, con gli strumenti di FDCP adattati (`tools/make_mockups.py`, `mockup_lib.py`, `mockup_scenes*.py`,
`mockup_spec.py`; sola lettura, ADR 0021):

- **Foglio di stile.** `mockups/html/accord.css` è **generato** da `tools/mockup_lib.py` (`--spec`): i token dei tre temi (gli stessi di
  `UI/Theme.lua`, §4) come variabili CSS (`:root` è Nebula, `[data-theme="aurora"]` e `[data-theme="accord"]` gli altri) e, per ogni
  componente del kit, la regola che lo disegna con quei token (§9): pulsanti (pieno, tonale, contornato, di testo), chip filtro e badge, segmentati,
  lista a discesa, campi, interruttore, badge, card, tabella (intestazione in maiuscolo su barra arrotondata, colonna ordinata nel colore
  d'accento, righe da 32 punti, riga scelta in `secondary-container`), quadrato di classe, slot della banca. Il nome di classe è nel colore della classe
  nei temi scuri e nel colore del testo in Aurora, come nell'addon. I font sono quelli dell'addon (`Media/Fonts/`, SIL OFL 1.1): nessun
  font del gioco e nessuna risorsa dalla rete.
- **Che cosa si disegna.** Il layout reale: schede lungo il bordo alto (con il conteggio sulla Banca), ricerca e Pop out a destra, riga
  di stato in fondo nella finestra Gilda, barra del titolo con logo, nome in Orbitron e stato nella finestra autonoma (920 × 600), la
  pagina Impostazioni e la pagina Info come colonna di card larga 520 con il selettore segmentato in alto. Tutti i testi sono letti dai
  file di lingua (inglese, e italiano per le anteprime in italiano). La finestra Gilda è disegnata come l'addon la veste (§3, M6.18): cornice tematica, nome della gilda, croce e linguette come tessere, con icone a linee generiche al posto di quelle del gioco (nessuna arte di Blizzard).
- **Quali anteprime.** Le 24 di M6.6 ridisegnate in Nebula (la scheda Accord, Roster in tabella e raggruppato, scheda membro, ricette e
  *chi può creare*, like, indice sociale, mappa dei gruppi, *qualcuno di nuovo*, i sette modi della Banca, Impostazioni in due parti con la
  scheda Aspetto, la scatola di diagnostica, la finestra autonoma, tre in italiano) più: la pagina **Info** in Nebula (logo NEBULA scuro) e
  in Aurora (logo chiaro), una in italiano; il Roster e le richieste della Banca in **Aurora**; la scheda membro e gli oggetti della Banca
  in **Accord**. Le quattro pagine annotate (`mockups/img/`) mostrano la scheda Accord, la scheda membro, le richieste e il sistema di
  design (i tre temi e il kit).
- **Confronto.** `mockups/compare/accord-vs-fdcp.webp` (`tools/make_compare.py`) mette le anteprime di Accord accanto a quelle di FDCP
  per lo stesso tipo di schermata (tabella, card e interruttori, pagina Info, tema chiaro, tema del logo, token): serve a vedere a colpo
  d'occhio se i due addon sono ancora una famiglia. È un'immagine committata; si rifà a mano quando cambiano le anteprime di uno dei due.
- **Controllo.** `tools/check_docs.py` costruisce ogni scena dai file di lingua (un testo rimosso o rinominato rompe l'anteprima che lo
  usa) e fallisce se manca un'anteprima, se il foglio di stile o una pagina annotata non sono aggiornati, se esiste un'immagine che nessuna
  scena produce o se manca il foglio di confronto. Nel wiki e nei README non resta alcuna nota "aspetto precedente".

Restano disegni nel browser, **non screenshot**: ogni immagine lo dice nella striscia in basso. Quando il proprietario avrà gli
screenshot veri, sostituiscono le anteprime vista per vista (ADR 0019, regola 6), e il controllo del rilascio
([`release.md`](../checklists/release.md), passo 7) confronta lo schermo con l'anteprima e con FDCP.

## 9. Le regole di Material 3 (ADR 0027)

Dal 2026-11-27 la **struttura** dell'interfaccia segue Material Design 3 ([m3.material.io](https://m3.material.io)),
adattato a un addon usato con il mouse dentro il gioco ([ADR 0027](../adr/0027-material-3-rules-adapted-to-accord.md)).
L'**aspetto** resta quello di FDCP (§0–§4: i tre temi, i loro valori, i font). Dove questa sezione e le precedenti dicono
cose diverse su misure, stati, forme o componenti, vale **questa**. Le misure di M3 sono in dp; qui sono in **punti** del
gioco. I valori di M3 citati sono stati letti sul sito il 2026-11-27 (ruoli di colore, stati, forme, tipografia, schede,
pulsanti, chip, liste, dialog, menu, tooltip, badge, side sheet, pulsanti segmentati).

### 9.1 Ruoli di colore

Ogni parte di un widget usa un **ruolo**, mai un token scelto a occhio. Le coppie si usano solo come M3 le prevede: un
colore *on-…* va sul suo contenitore, e la coppia rispetta 3:1 per gli elementi e 4,5:1 per il testo (§4.2).

| Ruolo M3 | Token di Accord | Uso |
|---|---|---|
| surface | `bg` | fondo della finestra e del corpo delle viste |
| surface container lowest / low | `bg` / `surface-1` | card piene, barra del titolo, side sheet |
| surface container | `surface-2` | intestazioni di tabella, menu, campi |
| surface container high | `surface-3` | contenitori annidati, tooltip ricchi |
| surface container highest | `raised` | card piene in evidenza, binario dell'interruttore spento |
| on surface | `text-1` | testo e icone principali |
| on surface variant | `text-2` | testo secondario, etichette inattive delle schede, icone |
| *(aggiunto da Accord)* | `text-3` | metadati e testo attenuato (ore, conteggi), mai per testo che si deve leggere per agire |
| outline | `border-strong` | bordo dei campi e dei pulsanti contornati al passaggio |
| outline variant | `border` (divisori: `border-subtle`) | bordo dei chip e dei pulsanti contornati, divisori, card contornate |
| primary / on primary | `accent` / `on-accent` | pulsante pieno, indicatore della scheda, interruttore acceso, focus dei campi |
| primary come testo | `accent-text` | etichetta della scheda attiva, colonna ordinata, pulsanti di testo, link |
| secondary container / on secondary container | **nuovi**: `secondary-container` / `on-secondary-container` | chip filtro selezionati, segmento selezionato, pulsante tonale, riga selezionata |
| tertiary | `accent-2` | accenti di complemento (gradiente del titolo con gli effetti) |
| error / on error | `err` / **nuovo** `on-error` | errori, badge da azione (richieste della banca) |
| inverse surface / inverse on surface | **nuovi**: `inverse-surface` / `inverse-on-surface` | tooltip semplici, snackbar |
| scrim | `scrim` | velo dei dialog |

I token nuovi hanno un valore per tema (Nebula, Aurora, Accord), scelto nel passo M12.6 e controllato da
`Tests/test_theme.lua` con le regole di §4.2: `on-secondary-container` su `secondary-container` e `inverse-on-surface`
su `inverse-surface` almeno 4,5:1, `secondary-container` distinguibile da `surface-1` (almeno 1,3:1, è un riempimento,
non un bordo). `ok` e `warn` restano ruoli di Accord per gli stati, come oggi.

I valori scelti in M12.6 (`UI/Theme.lua`), con il contrasto calcolato da `Tests/test_theme.lua`:

| Token | Nebula | Aurora | Accord |
|---|---|---|---|
| `secondary-container` | `#3B2A52` (prugna spenta) | `#C8DAF0` (azzurro chiaro) | `#3D4426` (oro oliva scuro, l'oro dello stendardo spento) |
| `on-secondary-container` | `#EBDDF8` | `#0A2A4F` | `#F1E7BE` |
| `inverse-surface` | `#E9E2F0` | `#24303D` | `#DDEBE3` |
| `inverse-on-surface` | `#251B30` | `#EEF3F7` | `#10292A` |
| `on-error` | `#3D0509` | `#FFFFFF` | `#3D0702` |

| Regola | Minimo | Nebula | Aurora | Accord |
|---|---|---|---|---|
| `on-secondary-container` su `secondary-container` | 4,5:1 | 9,90 | 10,12 | **8,24** |
| `inverse-on-surface` su `inverse-surface` | 4,5:1 | 12,99 | **12,01** | 12,43 |
| `on-error` su `err` | 4,5:1 | 5,92 | **5,90** | 6,11 |
| `secondary-container` su `surface-1` | 1,3:1 | 1,51 | **1,42** | 1,60 |
| `inverse-surface` su `bg` (il tooltip si stacca dalla finestra) | 3:1 | 15,83 | **12,58** | 14,94 |

In grassetto il caso peggiore, che il test controlla. Sui temi scuri `inverse-surface` è chiaro e `on-error` è un
inchiostro scuro (come in M3 scuro); su Aurora il contrario.

### 9.2 Stati

Uno **strato di stato** sta tra il contenitore e il contenuto, ha il **colore del contenuto** (il ruolo *on-…*, oppure
il colore dell'etichetta o dell'icona se non c'è contenitore) e un'opacità fissa:

| Stato | Opacità |
|---|---|
| passaggio del mouse | 8 % |
| focus (tastiera, campo attivo) | 10 % |
| pressione | 10 % |
| trascinamento | 16 % |
| disattivato | contenuto al 38 %, contenitore al 12 % di `text-1`, nessuno strato |

Un solo strato per volta. Sostituisce gli strati **bianchi** all'8 % e al 12 % di M6.11 (`Widgets.HOVER`,
`Widgets.PRESSED`): sul tema chiaro Aurora il bianco non si vedeva. La pressione resta anche come lieve rimpicciolimento
(`Motion.Press`) se le animazioni sono accese.

Nel codice (M12.6): le opacità sono `Theme.STATE`; il kit ha un aiuto condiviso, `Widgets.StateLayer(frame, token, opts)`
(una texture fra contenitore e contenuto, del colore del contenuto, con la forma del componente), `Widgets.SetState(layer,
stato)` e `Widgets.TrackState(frame, layer)` (passaggio e pressione agganciati). Lo usano il pulsante (colore
dell'etichetta, sfumato in 120 ms), il chip, i segmenti, le schede, il pulsante di chiusura della barra del titolo, le
righe di `Widgets.RowHover`, della tabella e del menu (strato di `text-1`). `Widgets.HOVER` e `Widgets.PRESSED` restano
come nomi, con i valori 0,08 e 0,10. Il disattivato del pulsante, del chip e dei segmenti segue la riga della tabella
(prima era tutto il widget al 45 % o al 55 %).

### 9.3 Forme

La scala di M3: **0, 4, 8, 12, 16, 28, piena**. Ai media si aggiungono le fette mancanti (`rr_fill_4`, `rr_ring_4`,
`rr_fill_16`, `rr_ring_16`, `rr_fill_28`, `rr_ring_28`); la "piena" è la pillola che c'è già.

| Raggio | Componenti |
|---|---|
| 0 | tabelle (righe), divisori, barre |
| 4 | menu, tooltip semplici, campi di testo, snackbar, riga selezionata |
| 8 | chip, intestazione delle tabelle, piccoli contenitori |
| 12 | card, finestra di Accord, tessere delle linguette nella finestra Gilda, tooltip ricchi |
| 16 | side sheet (la scheda del membro) |
| 28 | dialog |
| piena | pulsanti, pulsanti segmentati, badge, interruttori, indicatore della scheda (in alto) |

Nel codice (M12.6): `Theme.SHAPES` dà i nomi di M3 (`none` 0, `extra-small` 4, `small` 8, `medium` 12, `large` 16,
`extra-large` 28, `full`) e `Theme.ShapeSlice(forma, "fill" | "ring")` la fetta dei media (`large` → `rr_fill_16`,
`full` → `pill`, senza anello); `Theme.Panel` accetta anche il nome della forma. Da M12.7 card e dialog sono a 12 e 28;
i raggi 18 e 20 (`rr_fill_20`, `rr_ring_20`) disegnano la forma piena dei controlli alti 36 e 40 (`Widgets.FullRadius`:
la `pill` è esatta solo a 32 e non ha l'anello).

### 9.4 Tipografia

I ruoli di M3, con i font di FDCP e, per testo e etichette, **un punto sotto** M3: è la misura del testo del gioco.

| Ruolo M3 (misura M3) | Font di Accord | Misura in Accord | Uso |
|---|---|---|---|
| Headline small (24) | `Display` (Orbitron) | 22 | il titolo "AZEROTH ACCORD" |
| Title large (22) | `H1` | 18 | titolo dei dialog e della scheda del membro |
| Title medium (16, medio) | `H1` | 16 | titoli delle card |
| Title small (14, medio) | `Tab`, `H2` | 14 | etichette delle schede, titoli delle sezioni |
| Body large (16) | `Body` | 14 | testo lungo (manuale) |
| Body medium (14) | `Body`, `BodyMedium` | 13 | testo e celle delle tabelle |
| Body small (12) | `Small` | 11 | testo di aiuto, sottotitoli, tooltip |
| Label large (14, medio) | `Button` | 13 | pulsanti, chip |
| Label medium (12, medio) | `Eyebrow` | 11 | sopratitoli, intestazioni delle colonne |
| Label small (11, medio) | `Th`, `MonoSmall` | 10 | badge, piccole etichette |

Nel codice (M12.6): `Theme.TYPE_ROLES` lega ogni ruolo (`"title-large"`, `"body-medium"`…) a un oggetto font;
`Theme.Font`, `Theme.NewText` e `Widgets.Text` accettano il nome del ruolo come un id. Si aggiungono `TitleLarge`
(SemiBold 18) e `BodyLarge` (14); `MonoSmall` passa da 11 a 10 come dice la tabella. Gli id esistenti restano.

Gli stili "enfatizzati" di M3 (più pesanti) servono solo per la scelta attiva: la scheda attiva, la riga selezionata,
l'azione principale.

### 9.5 Spaziatura, densità ed elevazione

- **Griglia di 4 punti**: margini e spazi sono multipli di 4 (4, 8, 12, 16, 24). Margine della vista 16, spazio tra
  card 12, padding delle card 16.
- **Densità**: M3 toglie 4 punti per ogni gradino di densità. Accord usa il **gradino −2** per le tabelle, le barre degli
  strumenti e i menu: controlli da 32 a 36 punti, righe di tabella da 32 a 36 (la riga di lista di M3 è di 56: troppo per
  una gilda di 60 membri). L'area minima di clic è **32 punti**: i 48 di M3 sono per il dito.
- **Elevazione tonale**: i livelli si fanno con i contenitori di superficie (§9.1), non con le ombre. L'**ombra** resta
  solo per ciò che galleggia: la finestra di Accord, la scheda del membro, i menu, i dialog e i tooltip ricchi.

### 9.6 Componenti

| Componente | Misure (punti) | Colori e forma | Quando si usa |
|---|---|---|---|
| **Schede** (primarie) | alte 48; indicatore di 3 sotto l'etichetta, arrotondato in alto (3, 3, 0, 0), largo almeno 24 e rientrato di 2 per lato; divisore di 1 sotto la barra | etichetta attiva `accent-text`, inattive `text-2`; indicatore `accent`; divisore `border`; strato di stato sulla scheda; **nessun bagliore, nessun riempimento** | le viste di Accord (barra in alto) |
| **Pulsante pieno** | alto 40 (36 nelle barre degli strumenti), padding 24 (16 con icona), etichetta Label large | `accent` / `on-accent`, forma piena; con gli effetti accesi il bagliore dell'accento | **una sola** azione principale per vista o dialog |
| **Pulsante tonale** | come il pieno | `secondary-container` / `on-secondary-container` | azioni secondarie importanti (Esporta, Colonne) |
| **Pulsante contornato** | come il pieno, bordo di 1 | bordo `border`, etichetta `text-2` | azioni alternative, "Annulla" |
| **Pulsante di testo** | alto 40, padding 12 | etichetta `accent-text`, nessun contenitore | azioni minori nelle card e nei dialog |
| **Pulsante icona** | 40 (32 denso), icona 20 | icona `text-2`, strato di stato rotondo | chiudi, mostra di più, cuore dei like |
| **Chip filtro** | alto 32, padding 16 (8 con icona), icona 18, spazio 8 | spento: bordo `border`, etichetta `text-2`; acceso: `secondary-container`, nessun bordo, **spunta** a sinistra, etichetta `on-secondary-container`; raggio 8 | i filtri delle viste (Online, Solo main, Per account…) |
| **Pulsanti segmentati** | alti 40 (32 densi), bordo 1, padding minimo 12, spazio 8 | segmento scelto `secondary-container` con spunta; forma piena | scelte esclusive da 2 a 5 voci (tema, font, modi di una vista) |
| **Menu** (Select) | largo da 112 a 280, voce alta 48 (32 densa), padding 12 | `surface-2`, raggio 4, ombra | i menu a tendina (Tutte le classi…) |
| **Campo di testo** | alto 40 (denso), raggio 4 | bordo `border`, al focus 2 punti `accent`; etichetta Body | ricerca, Discord, editor |
| **Card** | padding 16, raggio 12 | piena `surface-1`, contornata `bg` + bordo `border`; ombra solo se galleggia | gruppi di contenuto |
| **Tabella** (DataTable) | righe da 32 a 36, intestazione 32 | intestazione `surface-2` raggio 8, testo Label medium `text-3`; riga al passaggio: strato 8 % di `text-1`; riga scelta `secondary-container` | elenchi lunghi (roster, banca, registri) |
| **Side sheet** (scheda del membro) | largo fino a 400 (oggi 340), padding 24 (16 denso), intestazione 72 | `surface-1`, raggio 16, ombra | il dettaglio di un elemento accanto alla lista |
| **Dialog** | largo da 280 a 560, padding 24, spazio 8 tra i pulsanti | `surface-3`, raggio 28, `scrim` dietro; titolo Title large | conferme, scelte che bloccano |
| **Tooltip semplice** | alto almeno 24, padding 8 | `inverse-surface` / `inverse-on-surface`, raggio 4, Body small | il nome di un'icona o un breve aiuto |
| **Tooltip ricco** | padding 16, spazio 8 | `surface-3`, raggio 12, titolo e testo | spiegazioni con più righe |
| **Badge** | piccolo: punto di 6; grande: alto 16, largo fino a 34, padding 4 | `err` / `on-error`, forma piena | cose da fare (richieste della banca, conteggi) |
| **Interruttore** | binario 52 × 32, maniglia 16 spenta, 24 accesa | acceso: binario `accent`, maniglia `on-accent`; spento: binario `raised`, bordo 2 `border-strong` | impostazioni sì/no |
| **Barra di avanzamento** (ThinBar) | binario 4 | `accent` su `surface-3` | caricamenti, timer |
| **Snackbar** (toast) | raggio 4 | `inverse-surface` / `inverse-on-surface` | conferme brevi |
| **Divisore** | 1 | `border-subtle` | separare righe e sezioni |

**Stato (M12.7).** Il kit (`UI/Widgets/`) e la scheda del membro seguono la tabella; `Tests/test_widgets.lua` controlla
misure, ruoli e stati di ogni componente. Dove una regola è stata adattata, e perché:

- **Stili dei pulsanti.** I nomi di M6.11 (`primary`, `secondary`, `ghost`, `neon`) non ci sono più (M12.8): le viste
  chiedono `filled`, `tonal` (il predefinito), `outlined` o `text`. Il gradiente non c'è più (i pulsanti sono piatti,
  ADR 0027).
- **Pulsanti segmentati densi di norma** (32, 40 con `dense = false`): in Accord stanno solo in barre, selettori di
  pagina e moduli (§9.5). Ogni segmento tiene sempre il posto della spunta, così la scelta non sposta nulla.
- **Campo dei menu a tendina** alto 32 (la tabella dice solo il menu): sta nelle barre degli strumenti. Il suo menu è
  largo quanto il campo, anche oltre 280, come fa M3 per un menu legato a un campo.
- **Altezze nelle viste** (M12.8): tre misure, `Widgets.HEIGHT`: 40 nei dialog e nelle pagine, 36 (`dense`) nelle
  barre degli strumenti e nelle righe dei moduli (pulsanti e campi), 32 per un pulsante dentro la riga di un elenco.
  Chip, menu a tendina e segmentati restano a 32.
- **Badge.** Il badge `err` è per le cose da fare (4 punti per lato, al più 34). Le etichette di stato (Online, Main,
  versione, conteggi che informano soltanto) sono lo stesso widget nella tinta dello stato al 16 %, con 8 punti per lato
  e senza larghezza massima: un badge rosso direbbe di agire.
- **Dialog**: il minimo di 280 vale sempre; il massimo di 560 vale per conferme e scelte, non per le finestre con un
  testo lungo o una tabella (diagnostica, esportazione, copia di sicurezza, reclutamento, revisione), che sarebbero
  illeggibili.
- **Tooltip**: semplice quando è una riga sola senza un colore proprio che sta in 280 punti, ricco negli altri casi; il
  titolo del tooltip ricco resta in `accent-text` (proprietario, 2026-11-27).
- **Card**: resta la riga di luce in cima dei temi scuri (è aspetto FDCP, §0); la card piena non ha più il bordo.
- **Snackbar**: nessun segno colorato del tono (sui colori inversi non reggerebbe il contrasto). Il toast delle
  notifiche (`UI/Toast.lua`) passa a queste regole con le viste (M12.8).
- **Chip**: scelto, il chip si allarga della spunta; chi li dispone per larghezza li ridispone (`onResize`).

**Stato (M12.8).** Le viste usano il kit secondo la tabella; `Tests/test_ui_m3.lua` apre ogni vista, pagina e i
dialog principali della gilda inventata e controlla **al più un pulsante pieno** e le altezze. Le scelte:

- **Il pulsante pieno** è l'azione che conclude il lavoro della vista (Salva la dichiarazione, Mi iscrivo, Chiama il
  raduno, Candidati, Pubblica, Invia la richiesta, Rivedi). Dove un pulsante si ripete su ogni riga (Accetta, Invita,
  Approva) è tonale; la pagina Impostazioni non ha un'azione principale e non ha pulsanti pieni. In un dialog il pieno
  è a destra, "Annulla" e le alternative sono contornati, "Chiudi" accanto a un'azione è di testo.
- **Riga scelta** in `secondary-container`: la tabella (`isSelected`) in Roster, Gruppi e Addon della gilda, e
  `Widgets.Selection` nelle liste disegnate dalle viste (manuale e revisioni, richiesta aperta dal Centro azioni,
  persona scelta nello schieramento). La barretta e la tinta d'accento di M6.14 non ci sono più.
- **Righe**: 32 nelle tabelle e nelle liste; 36 quando contengono un pulsante (il pulsante è alto 32); 44 nelle righe
  a due righe di testo. Gli elenchi di solo testo (Season, Eventi, Raduni, Disponibilità, Raid) non sono tabelle e
  restano a 20 punti; le celle della mappa di disponibilità (26 × 20) sono un grafico.
- **Campi a più righe** (`Widgets.TextArea`): lo stesso aspetto del campo di testo. **Chip** disposti a capo con
  `Widgets.Flow` dove la larghezza non è fissa (colonne del roster, temi dei mentori, tipi dei gruppi).
- **Toast** (`UI/Toast.lua`): le regole della snackbar. **Finestra Gilda**: la tessera della linguetta scelta è
  `secondary-container`, senza bagliore; il suo contatore è il badge del kit.
- **Dialog**: il titolo è `:SetTitle` (title large); i pulsanti stanno a 24 punti dai bordi.

Nulla di questo è provato nel client vero.

### 9.9 Tabelle sempre ordinabili (proprietario, 2026-11-27)

- **Ogni elenco a colonne** è una `Widgets.DataTable` con l'**intestazione**. Il clic su una colonna ordina **crescente**, un secondo clic **decrescente**, e la colonna ordinata ha la freccia e il colore `accent-text`. Nessun elenco a colonne fatto a mano.
- Una colonna che non ha senso ordinare (un pulsante, un'icona d'azione) non ha clic, e la sua intestazione resta vuota o porta il nome senza freccia.
- **Gli elenchi a card senza colonne** (pagine del manuale, annunci della bacheca) hanno un menu **"Ordina per"** con lo stesso comportamento: la voce scelta e poi crescente o decrescente.
- L'ordinamento scelto si ricorda per vista e personaggio, come nel Roster.

### 9.10 Icone: Material Symbols (proprietario, 2026-11-27)

- **Tutte le icone dell'interfaccia propria di Accord** vengono da **Material Symbols Rounded** di Google (licenza **Apache 2.0**, compatibile con GPL-3, citata in `docs/third-party.md` e nei crediti). Sono **vuote** (outlined) di norma, **piene** (filled) per lo stato attivo: la vista scelta, l'interruttore acceso, il filtro scelto.
- Le icone si costruiscono con uno strumento in `tools/` in **un solo atlante** che contiene solo le icone usate, con i nomi di Material Symbols (`groups`, `inventory_2`, `menu_book`…). Il foglio di icone disegnato da Accord (`Media/icons.tga`) va via.
- Misure: 20 punti nei pulsanti e nelle schede, 24 nella barra di navigazione, 18 nei chip; colore del ruolo del contenuto (§9.1).
- **Restano le icone del gioco** dove dicono una cosa del gioco: classi, oggetti, ricette, istanze.
- Un'icona sola, senza testo, ha **sempre un tooltip** con il suo nome.

### 9.11 Navigazione: due livelli (proprietario, 2026-11-27)

- **Livello 1, le viste**: una **barra di navigazione verticale** a sinistra (la *navigation rail* di M3), **solo icone** di 24 su elementi alti 56, con il nome della vista in un tooltip al passaggio del mouse. La vista attiva ha l'icona piena, l'indicatore in `secondary-container` dietro l'icona e i badge di M3. La barra contiene tutte le viste, quindi non c'è più "Altro".
- **Livello 2, le pagine di una vista**: **una sola** riga di schede in cima al contenuto, uguale in tutte le viste (schede primarie di §9.6), con il **nome della vista** a sinistra della riga, così si sa sempre dove si è. Una vista con una sola pagina mostra solo il nome.
- **Nessun terzo livello di navigazione.** Le sotto-categorie diventano **filtri** (chip nella barra degli strumenti) o un **menu** "Categoria". Il selettore segmentato serve solo per **scelte**, non per navigare.
- Vale nella finestra di Accord e nel pannello dentro la finestra della gilda.

**La mappa delle destinazioni** (proprietario, 2026-11-27). Le 15 viste di oggi e quelle delle milestone future stanno in **8 icone** più le Impostazioni; i nomi delle icone sono quelli di Material Symbols e si confermano nel passo delle icone (M13.6):

| # | Destinazione (icona) | Pagine |
|---|---|---|
| 1 | **Home** (`home`) | Centro azioni; lista di benvenuto (M12.4); bacheca degli annunci e storico del MOTD (M14) |
| 2 | **Gilda** (`groups`) | Roster; Reputazione (like, indice sociale, mappa dei gruppi); Mentori; Addon della gilda |
| 3 | **Raid** (`swords`) | Season; Eventi; Raid e loot (FDCP); Disponibilità |
| 4 | **Gruppi** (`group_add`) | Cercagruppi (M18 sostituisce quello di M9); Quest (M16); Raduni |
| 5 | **Professioni** (`construction`) | Ricette e "chi crea"; Ordini; Lista della spesa; Livellamento (M17) |
| 6 | **Economia** (`account_balance`) | Banca (le sue modalità in un menu "Mostra", non in schede); Mercato (compro/vendo, desideri, domanda); Obiettivi di gilda |
| 7 | **Community** (`celebration`) | Manuale; Sondaggi e kudos (M14); avvistamenti, storia della gilda, bingo, quiz, Secret Santa (M15) |
| 8 | **Ufficiali** (`shield_person`), solo per chi può | Strumenti degli ufficiali; Reclutamento e prove; coda delle azioni manuali |
| in fondo | **Impostazioni** (`settings`) | Impostazioni; Cosa condivido; Info e crediti |

Un membro vede 7 icone più le Impostazioni. Una milestone nuova aggiunge **pagine** a una destinazione, non icone: una destinazione nuova si aggiunge solo con il consenso del proprietario.

### 9.7 Cosa non si prende da M3

- I **colori dinamici** e la palette di base di M3: valgono i tre temi di §4.
- **Roboto**: restano i font di FDCP (M3 permette un carattere del marchio).
- Le aree di clic da 48 e le righe di lista da 56: Accord è denso (§9.5).
- Le animazioni "a molla" di M3 Expressive: restano le dissolvenze brevi di `Motion` (100–250 ms), spente con le animazioni.
- Il pulsante "elevato" e il FAB: Accord non li usa.

### 9.8 Come si applica

1. **M12.6, base**: i token nuovi in `UI/Theme.lua` per i tre temi (con i test di contrasto); gli strati di stato con
   il colore del contenuto; le fette di forma 4, 16 e 28 (`tools/make_media.py`); i ruoli tipografici di §9.4.
2. **M12.7, componenti**: `UI/Widgets/` secondo §9.6 (schede, pulsanti con i quattro tipi, chip filtro, segmentati,
   menu, campi, card, tabella, side sheet, dialog, tooltip, badge, interruttore, snackbar); i test dei widget.
3. **M12.8, viste** (fatto): ogni vista usa il componente giusto (un solo pulsante pieno, i filtri come chip, la riga
   scelta in `secondary-container`), le anteprime di §8 e il wiki rifatti.

Le regole §9.9–§9.11 (tabelle, icone, navigazione) si applicano nei passi M13.6–M13.8 della [roadmap di M13](../roadmap/M13-economy.md).

Da questo momento ogni modifica grafica, anche una correzione, segue questa sezione. Una regola che il gioco non permette
si annota qui, con il motivo.
