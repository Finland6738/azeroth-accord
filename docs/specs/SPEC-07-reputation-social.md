# SPEC-07: Reputazione e indice sociale

## 1. Scopo

Due segnali diversi: i **like** dicono quanto un giocatore è apprezzato dagli altri; l'**indice sociale** misura in automatico se un giocatore gioca con tanti compagni diversi oppure sempre con lo stesso gruppetto, e la **mappa dei gruppi** mostra se la gilda si divide.

## 2. Like

Decisioni D1 e D2, [ADR 0007](../adr/0007-likes-one-per-account-irreversible-anonymous.md).

| ID | Requisito |
|---|---|
| LIKE-01 | Un account dà **al massimo un like** a ciascun altro account. Il pulsante Like compare su ogni personaggio del destinatario; dopo il voto sparisce da tutti. |
| LIKE-02 | Mai a se stessi né ai personaggi del proprio account. |
| LIKE-03 | **Irrevocabile**: non esiste "togli like". |
| LIKE-04 | **Anonimo**: l'interfaccia mostra solo il totale dell'account destinatario, su tutti i suoi personaggi. Nessuna vista dice chi ha votato. |
| LIKE-05 | Il voto viaggia in whisper a un **ufficiale online** (il notaio), mai su `GUILD`. Se nessun ufficiale è online il voto aspetta in coda e la tab mostra "pending". |
| LIKE-06 | Il notaio verifica (mittente in gilda, account noto, non se stesso, non già votato), calcola lo pseudonimo `HMAC-SHA256(salt, tokenDelVotante)` e pubblica la voce `{pseudonym, target, day}` su `GUILD`. |
| LIKE-07 | Il `salt` lo crea il primo ufficiale o il GM con l'addon, viaggia solo su `OFFICER` e resta solo nei client degli ufficiali. Se l'ultimo ufficiale con il salt lascia la gilda, un nuovo salt riparte da zero solo per i voti nuovi: le voci vecchie restano valide. |
| LIKE-08 | Classifica: vista Reputation con l'elenco degli account ordinabile per like; visibile a tutti. |
| LIKE-09 | Chi non ha l'addon può ricevere like (sul personaggio, che si unisce al suo account quando installa l'addon) ma non darne. |

Limiti noti, scritti nella wiki: il notaio vede chi ha votato nel momento in cui riceve il voto; un ufficiale con un addon modificato potrebbe inventare voti (come nel gioco, gli ufficiali sono fidati).

## 3. Indice sociale

[ADR 0008](../adr/0008-social-breadth-index-from-co-play.md).

### 3.1 Registrazione (da M2, D6)

- SOC-01: ogni 60 s, se il giocatore è in un gruppo o raid (`IsInGroup`, `GetNumGroupMembers`, `UnitGUID("party1..4"/"raid1..40")`, `UnitIsInMyGuild`) con almeno un altro membro della gilda, aggiunge 1 minuto a **ogni coppia** di membri della gilda presenti nel gruppo **[verificare]** S7.
- SOC-02: si conta anche dentro istanze e raid; l'invio dei dati aspetta la fine del lockdown.
- SOC-03: i dati si pubblicano una volta all'ora e alla disconnessione, per giorno; si uniscono con il **massimo** per coppia e giorno.

### 3.2 Calcolo

Per ogni account `a` nella finestra degli ultimi 30 giorni:

- `m_b` = minuti giocati con l'account `b` (somma sui giorni, alt uniti); `M = Σ m_b`
- `p_b = m_b / M`
- **compagni effettivi** `N = exp(−Σ p_b · ln p_b)`
- `A` = account attivi nella finestra (almeno 60 minuti di gioco di gruppo in gilda)
- **indice** `= min(100, round(100 · N / (A − 1)))`

| Esempio (A = 41) | N | Indice |
|---|---|---|
| 100 ore sempre con le stesse 4 persone, in parti uguali | 4 | 10 |
| 100 ore, metà con 1 amico e il resto sparso su 20 persone | ≈ 8,9 | 22 |
| 60 ore divise in modo uguale fra 30 persone | 30 | 75 |

- SOC-04: sotto 5 ore di gioco di gruppo in gilda nella finestra l'indice è "not enough data".
- SOC-05: la scheda membro mostra l'indice, `N`, il numero di compagni distinti e i 5 compagni principali con la loro quota.
- SOC-06: il calcolo si fa in locale, al massimo una volta ogni 10 minuti, a pezzi per non bloccare il client.

### 3.3 Mappa dei gruppi

- SOC-10: grafo degli account (peso = minuti insieme); comunità con *label propagation* pesata; **modularità** `Q` come indice di mescolanza della gilda ("bassa: tutti giocano con tutti", "alta: gruppetti").
- SOC-11: vista con l'elenco delle comunità (membri, minuti interni contro minuti verso l'esterno) e un disegno semplice a cerchi.
- SOC-12: visibile a tutti per l'indice personale; la mappa completa è per ufficiali e GM (domanda Q3 in [SPEC-10](SPEC-10-risks-open-questions.md)).

### 3.4 Compagni suggeriti

- SOC-20: riquadro "Play with someone new": membri **online adesso**, di livello compatibile, con cui il giocatore ha giocato meno di 30 minuti negli ultimi 30 giorni; pulsanti Whisper e Invite (azioni del giocatore).
