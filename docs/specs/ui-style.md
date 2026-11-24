# Stile dell'interfaccia: la famiglia di FDCP

> Specifica del passo **M6.8**. Vale per M6.9 (media e font), M6.10 (tema), M6.11 (widget), M6.12 (finestra e schede),
> M6.13 e M6.14 (viste), M6.15 (Info e crediti), M6.16 (anteprime). Decisione in
> [ADR 0021](../adr/0021-interface-follows-the-ecosystem-style-of-fdcp.md).

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
| Cornice | finestra propria come FDCP §6: **barra del titolo di 52 pt** (logo, "AZEROTH ACCORD" in Orbitron, stato della sincronizzazione, Pop in, chiudi), raggio 12, ombra, mobile, Esc | **nessuna barra del titolo né cornice propria**: il pannello riempie l'area dei contenuti di `CommunitiesFrame` e prende i colori del tema |
| Schede | barra delle schede da 44 pt sotto il titolo, con l'indicatore da 2 pt | la stessa barra delle schede, in cima al pannello |
| Ricerca globale | a destra della barra delle schede | uguale |
| Dimensione | 920 × 600 predefinita, minimo 720 × 460, ridimensionabile (confermata in M6.12; era 640 × 400 in SPEC-04 §3) | quella dell'area di Blizzard, senza ridimensionare |
| Ricordo | posizione e dimensione per personaggio | nessuno |

La finestra di Blizzard è **solo osservata**, come ADR 0003 prescrive: il pannello è un frame dell'addon figlio della
finestra, i colori si applicano ai frame dell'addon, mai a quelli di Blizzard (nessun riskin, nessuna `SetDisplayMode`,
nessuna sostituzione di funzioni). La **linguetta** nella finestra Gilda resta il pulsante di Blizzard con l'icona
(SPEC-10 Q2: l'icona proposta è il logo, §5); il pannello sotto di essa non ha più "il look del gioco" di
[SPEC-04 §5](SPEC-04-ui-guild-tab-shell.md#5-stile). L'area dentro la finestra Gilda è stretta: le tabelle usano le
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
- **Schede.** L'indicatore da 2 pt **scorre** da una scheda all'altra in 200 ms (`Translation`, poi si posa) e si
  dissolve solo alla prima comparsa; una scheda può avere un **badge con il conteggio** (le richieste in attesa della
  Banca: `Tabs:SetBadge(id, testo|nil, tono)`; il testo lo passa il chiamante).
- **Tooltip.** Un solo frame proprio dell'addon (`AzerothAccordTooltip`, strato `TOOLTIP`, creato al primo uso): fondo
  `text-1`, testo `bg`, larghezza fino a 280 pt, il mouse lo attraversa. `Tooltip.Attach(frame, testo|righe|funzione)`;
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
- **Linguetta.** Icona invariata (SPEC-10 Q2); il badge delle richieste è un cerchio `accent` col numero in `on-accent`.
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
  componente del kit, la regola che lo disegna con quei token: pulsanti (primario, secondario, ghost, neon), pillole e chip, segmentato,
  lista a discesa, campi, interruttore, badge, card, tabella (intestazione in maiuscolo su barra arrotondata, colonna ordinata nel colore
  d'accento, righe da 28 punti, riga scelta tinta), quadrato di classe, slot della banca. Il nome di classe è nel colore della classe
  nei temi scuri e nel colore del testo in Aurora, come nell'addon. I font sono quelli dell'addon (`Media/Fonts/`, SIL OFL 1.1): nessun
  font del gioco e nessuna risorsa dalla rete.
- **Che cosa si disegna.** Il layout reale: schede lungo il bordo alto (con il conteggio sulla Banca), ricerca e Pop out a destra, riga
  di stato in fondo nella finestra Gilda, barra del titolo con logo, nome in Orbitron e stato nella finestra autonoma (920 × 600), la
  pagina Impostazioni e la pagina Info come colonna di card larga 520 con il selettore a pillole in alto. Tutti i testi sono letti dai
  file di lingua (inglese, e italiano per le anteprime in italiano). La cornice della finestra Gilda del gioco è un'imitazione originale
  (non arte di Blizzard); il pannello dentro è quello dell'addon.
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
