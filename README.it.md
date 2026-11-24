# Azeroth Accord

<img src="assets/logo-source.webp" alt="Logo di Azeroth Accord" width="160" align="right">

**Una finestra della Gilda più ricca per World of Warcraft: Forever.** Azeroth Accord aggiunge alla finestra della Gilda una scheda **Accord** con ciò che manca al pannello del gioco: roster esteso con professioni e ricette, tutti i personaggi dello stesso account, contatti Battle.net e Discord, like tra compagni, un indice sociale che mostra se la gilda gioca insieme o si divide in gruppetti, e la banca di gilda con richieste di prelievo, deposito e donazioni.

> **Stato: le milestone M1 (fondamenta), M2 (roster), M3 (professioni), M4 (reputazione), M5 (banca di gilda) e M6 (impostazioni, italiano, rifinitura, diagnostica, pacchetto, immagini) sono complete nel codice e aspettano le prove in gioco** ([M1](docs/checklists/M1.md), [M2](docs/checklists/M2.md), [M3](docs/checklists/M3.md), [M4](docs/checklists/M4.md), [M5](docs/checklists/M5.md), [rilascio](docs/checklists/release.md), in inglese): esistono la scheda Accord, la finestra autonoma, la sincronizzazione di gilda, la vista **Roster** (ordinabile, filtrabile, raggruppata per account), la **scheda del membro**, i personaggi di un account, i **contatti** (BattleTag, Discord, richiesta di amicizia), la vista Impostazioni, la registrazione silenziosa del gioco di gruppo e ora la vista **Professioni**: l'elenco delle ricette di un membro aperto da una cella di professione, **chi può creare** un oggetto (prima i membri online, raggruppati per giocatore) e **Request craft**, un sussurro con il link della ricetta che invii tu. Con M4 la vista **Reputation** aggiunge i **like** (dalla scheda del membro o dalla vista: anonimi, uno per giocatore, registrati dall'addon di un ufficiale online), l'**indice sociale** (il proprio; gli ufficiali vedono quello di tutti), la **mappa dei gruppi** per gli ufficiali e **Someone new** per giocare con qualcuno di nuovo; Con M5 la vista **Banca** mostra la banca di gilda dall'ultima visita di un membro con l'addon (scheda per scheda, il denaro, un elenco di oggetti con ricerca; le schede che il tuo grado non vede restano nascoste), tiene il **registro della banca** oltre quello del gioco (senza doppioni), classifica le **donazioni** per giocatore e disegna il denaro della gilda nel tempo, e gestisce le **richieste** (prelievo, deposito, donazione: un membro chiede, gli ufficiali approvano, rifiutano o segnano come consegnata; gli ufficiali vedono un contatore sulla tab e una casella, e ognuno è avvisato quando la sua richiesta viene decisa). Ogni milestone si pubblica come versione di prova per la gilda del proprietario quando la sua prova passa, da `v0.1.0` a `v0.6.0` (le correzioni alzano l'ultimo numero, come `v0.6.1`); non c'è ancora un download. Le prossime milestone, da M7 a M15, sono pianificate nella [roadmap](ROADMAP.md); `v1.0.0` arriva quando sono tutte finite. L'interfaccia è anche in **italiano**. Con M6 la pagina **Impostazioni** (la card **Aspetto**: tema Nebula, Aurora o Accord, effetti neon, animazioni e carattere; personaggio principale, avvisi della banca, colonne del roster, dati salvati e *Cancella i dati della gilda*) è nel pannello Accord e nella finestra impostazioni del gioco; vedi [Impostazioni](docs/wiki/Settings-it.md). Il manuale ha ora le immagini: anteprime di progetto di ogni vista principale (non screenshot). Prima di `v0.6.0`, M6 continua con i passi da M6.8 a M6.18 (da M6.8 a M6.18 sono fatti: il nuovo aspetto è completo, `v0.6.0` aspetta le prove in gioco): Accord prende l'aspetto dell'altro addon del proprietario, Finland Dragon Credit Points (temi, font, barra del titolo e schede; tutte le viste sono già disegnate così, e anche le immagini; M6.18 veste nel tema anche la finestra Gilda intorno al pannello Accord: la cornice, il nome della gilda, la croce e le linguette a lato), e aggiunge una pagina Informazioni con i crediti e il manuale in italiano (fatto in M6.17: ogni pagina del wiki ha la sua gemella italiana).

[English](README.md) · [Roadmap](ROADMAP.md) · [Specifiche](docs/specs/README.md) · [Decisioni](docs/adr/README.md) · [Manuale](docs/wiki/Home-it.md) ([inglese](docs/wiki/Home.md))

## Come appare

![La scheda Accord nella finestra di gilda: il roster con professioni, like e chi usa l'addon](docs/specs/mockups/previews/it-roster.webp)

| | |
|---|---|
| ![Richieste alla banca](docs/specs/mockups/previews/it-bank-requests.webp) | ![Impostazioni con la scheda Aspetto](docs/specs/mockups/previews/it-settings.webp) |
| ![Info e crediti](docs/specs/mockups/previews/it-about.webp) | ![Scheda membro](docs/specs/mockups/previews/member-card.webp) |
| ![Chi può creare](docs/specs/mockups/previews/professions-who-can-craft.webp) | ![Mappa dei gruppi](docs/specs/mockups/previews/reputation-group-map.webp) |
| ![Il tema chiaro Aurora](docs/specs/mockups/previews/roster-aurora.webp) | ![Il tema Accord](docs/specs/mockups/previews/member-card-accord.webp) |

> **Anteprime di progetto, non screenshot.** Sono disegnate dal layout e dai testi dell'addon, nel nuovo aspetto (Nebula, il tema predefinito, e alcune in Aurora e in Accord), con personaggi e oggetti inventati e grafica originale, perché l'addon non è ancora stato provato nel gioco. Le prime quattro sono in italiano, le altre in inglese. [Tutte le anteprime](docs/specs/mockups/previews/README.md) (in inglese) · [come si fanno](docs/specs/mockups/README.md) · [accanto a Finland Dragon Credit Points](docs/specs/mockups/compare/README.md).

## Funzioni previste

| Area | Cosa offre |
|---|---|
| **Scheda Accord** | Una quinta tab sotto Chat, Membri, Vantaggi e Info; lo stesso pannello si apre anche in una finestra a parte (`/accord`) |
| **Roster esteso** | Tabella ordinabile e filtrabile: livello, classe, grado, zona, ultimo accesso, professione 1 e 2, like, indice sociale, contatti |
| **Alt** | Clic su un personaggio: tutti i personaggi dello stesso account Battle.net sul reame, senza chiedere |
| **Contatti** | BattleTag e Discord di ogni membro con l'addon, copia con un clic, richiesta d'amicizia BattleTag nativa |
| **Professioni** | Clic sulla professione di un membro: le sue ricette; ricerca "chi sa fare…"; richiesta di crafting |
| **Like** | Un like da ogni account a ogni altro account, mai a se stessi, irrevocabile, totali anonimi |
| **Indice sociale** | Con quanti compagni diversi gioca davvero ciascuno (compagni effettivi), una mappa dei gruppi della gilda e i suggerimenti "gioca con qualcuno di nuovo" |
| **Banca di gilda** | Contenuto dall'ultima visita di un membro, registri, donazioni, richieste di prelievo e deposito approvate dagli ufficiali |
| **Addon di raid e di loot** | Lavora con l'addon del loot della gilda invece di sostituirlo: gli ufficiali scelgono Finland Dragon Credit Points come fonte, e la vista **Raid** mostra il suo pool della season (MS1, MS2, OS), la formazione e la panchina della serata e le sue regole del loot, e la scheda del membro i crediti e il posto nella coda del loot, tutto in sola lettura; in Accord nessun motore del loot e nessuna presenza |

Tutto resta **dentro la gilda**: l'addon comunica solo sui canali addon nascosti della gilda, senza server, senza internet e senza telemetria.

## Contribuire

Vedi [CONTRIBUTING.md](CONTRIBUTING.md) (in inglese). Le specifiche sono in italiano.

## Crediti

- **Creato e progettato da Finland.**
- **Realizzato con la gilda italiana NEBULA** ([la pagina della gilda](https://nebula-community.github.io/giochi/wow-forever/)). Il logo di NEBULA è usato con il permesso della gilda.
- Sostieni il progetto su [Ko-fi](https://ko-fi.com/finland6738); segnala un problema o suggerisci qualcosa nelle [issue](https://github.com/Finland6738/azeroth-accord/issues).
- Nel gioco gli stessi crediti sono nella pagina **Info** delle Impostazioni (`/accord about`); `/accord about chat` li scrive in chat. Li ha anche il manuale: [Informazioni e crediti](docs/wiki/About-it.md).
- Azeroth Accord è un addon creato dai fan, non realizzato da Blizzard Entertainment e non affiliato a Blizzard Entertainment.

## Crediti dei font

L'addon include tre famiglie di font con la [SIL Open Font License 1.1](https://openfontlicense.org/) (i testi delle licenze sono accanto ai file in `AzerothAccord/Media/Fonts/`): **Outfit** (The Outfit Project Authors), **JetBrains Mono** (The JetBrains Mono Project Authors) e **Orbitron** (Matt McInerney, incluso senza modifiche perché dichiara un Reserved Font Name). Ogni font, il foglio delle icone, le texture, i loghi e le librerie sono elencati con le loro licenze in [docs/third-party.md](docs/third-party.md), in inglese.

## Licenza

[GNU GPL v3.0](LICENSE). Addon amatoriale, non affiliato a Blizzard Entertainment.
