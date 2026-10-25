# APP YBA

Controlla Roblox ogni 2 secondi. Se Roblox si chiude o crasha:

1. manda **"Roblox crash/chiuso"** sul tuo webhook Discord e ti pinga;
2. se il processo di Roblox è rimasto aperto nel Task Manager (succede quando lo chiudi con la X), lo chiude;
3. apre la tua app e clicca il bottone che apre Roblox; se Roblox non si apre entro 10 secondi ricomincia dal punto 1;
4. entra in **Your Bizarre Adventure**;
5. fa i 2 click finali sulla tua app.

Inoltre, mentre Roblox è aperto, legge lo schermo ogni secondo:
- se la schermata di caricamento di YBA c'è per 15 letture di fila (15 secondi), manda **"YBA bloccato nel caricamento"**
  e riavvia Roblox;
- se compare la finestra **Disconnected** e resta per 15 secondi, clicca **Reconnect** e manda **"Reconnect issue"**
  (una volta sola per disconnessione). Se dopo 3 tentativi è ancora disconnesso, riavvia Roblox.

Non serve installare niente: usa PowerShell, che c'è già in Windows 10 e 11.

## File

| File | A cosa serve |
|---|---|
| `Setup.bat` | Configurazione guidata (da fare la prima volta) |
| `Avvia.bat` | Avvia il controllo di Roblox |
| `config.json` | Creato dal Setup. Contiene il webhook: **non condividerlo** |
| `watchdog.log` | Registro di tutto quello che è successo |

## Primo avvio

1. Doppio click su **`Setup.bat`**.
   Se Windows mostra "PC protetto da Windows", clicca *Ulteriori informazioni* → *Esegui comunque*.
2. Incolla l'URL del webhook Discord e conferma l'ID da pingare (`350886488235311126`).
   Puoi mandare un messaggio di prova per vedere se funziona.
3. **Bottone che apre Roblox**: apri la tua app, metti il mouse sopra il bottone (senza cliccare) e premi **F8**.
   Senti un beep e il Setup si salva quale app è e dove si trova il bottone.
   **Se F8 non fa niente**: sui portatili prova **Fn+F8**; oppure clicca sulla finestra nera del Setup,
   premi **INVIO** e in 5 secondi metti il mouse sopra il bottone (il bottone deve essere visibile,
   non coperto dalla finestra nera).
4. **Come entrare in YBA**, scegli una di queste:
   - `1` se il bottone dell'app ti fa già entrare in YBA;
   - `2` per aprire YBA con il link `roblox://` (placeId `2809202155`, usa l'account loggato su Roblox);
   - `3` per fare i passi nella finestra di Roblox: **scroll → click → altro click** (scroll e numero di click
     si possono cambiare). Parti con Roblox appena aperto, nella home in cima. Ogni passo si registra con
     mouse sopra + **F8** (oppure **INVIO** nella finestra nera + 5 secondi) e il Setup **lo prova subito** su Roblox:
     - **Click iniziale**: un punto **vuoto** di Roblox, che non apre niente. Senza questo click Roblox non
       "prende" il mouse: l'app lo fa appena Roblox si apre e di nuovo subito prima dello scroll.
     - **Cerca il gioco** (consigliato, perché la posizione di YBA nella home cambia): l'app legge le scritte
       su Roblox con il riconoscimento del testo di Windows; se vede "Your Bizarre" lo clicca, sennò scrolla
       un po' e riprova. Se non lo trova dopo tot scroll (di default 15) chiude Roblox e ricomincia dallo step 1.
       Il Setup ti fa vedere cosa legge sullo schermo e prova subito la ricerca completa.
       La finestra nera non deve coprire Roblox.
     - **Scroll**: il Setup lo prova in 3 modi, finché uno fa muovere la pagina di Roblox:
       1. rotellina del mouse; 2. rotellina mandata direttamente a Roblox (scrivi quanti scatti: positivo = giù);
       3. trascinamento: registri con F8 dove inizia e dove finisce (sulla pagina: fine più in ALTO;
          sulla barra di scorrimento: fine più in BASSO).
       Dopo ogni prova ti chiede se la pagina si è mossa e se il bottone si vede; se no, torna su e riprovi.
       L'app poi usa il modo che ha funzionato.
     - **Click**: il Setup clicca e ti chiede se ha funzionato; se no, lo registri di nuovo.
       Così Roblox arriva alla schermata giusta per il click dopo.

   **Caricamento bloccato** (per tutte le scelte): di default l'app cerca la scritta `LOADING ASSETS`.
   Per sceglierne un'altra entra in YBA e, quando vedi la schermata di caricamento, premi **F8**: il Setup
   ti mostra le scritte che legge e scegli una parola che c'è **solo** lì (es. `LOADING`).
   Mentre Roblox è aperto l'app legge lo schermo ogni secondo: se quella scritta c'è per 15 letture di fila
   (si può cambiare), chiude Roblox e ricomincia dallo step 1. Se il caricamento normale di YBA dura più
   di 15 secondi, alza il numero, sennò l'app chiude Roblox anche quando non è bloccato.
5. **I 2 click finali**: mouse sopra il primo bottone dell'app + **F8**, poi sopra il secondo + **F8**.
   Poi scegli quanti secondi tra un click e l'altro, e quanti secondi aspettare dopo l'ingresso nel gioco
   prima del primo click (di default 10: si può cambiare anche tenendo i click già registrati).

Poi doppio click su **`Avvia.bat`**. Per fermarla chiudi la finestra (o premi CTRL+C).

Se avvii `Avvia.bat` con Roblox chiuso, lo riapre subito (e manda anche l'avviso su Discord).
Puoi rifare `Setup.bat` quando vuoi: premi Invio per tenere i valori già salvati.

## Cose importanti

- **Non bloccare il PC** (Win+L): con lo schermo bloccato Windows non permette di cliccare. Lo schermo spento va bene.
- Per **leggere lo schermo** (ricerca del gioco e caricamento) l'app riaccende lo schermo se l'ha spento Windows.
  Se lo spegni tu con il tasto del monitor va bene comunque.
- I click sono salvati **rispetto alla finestra dell'app**: puoi spostarla, ma se la ridimensioni
  o cambia la grafica dell'app rifai il Setup.
- Se la tua app si apre **come amministratore**, il Setup se ne accorge e `Avvia.bat` si riavvia da solo
  come amministratore (Windows ti chiede il permesso), perché altrimenti Windows blocca i click.
- Roblox va bene sia dal sito che con Bloxstrap/Fishstrap. La versione del Microsoft Store non è supportata.
- Per farla partire insieme a Windows: Win+R → `shell:startup` → crea lì un collegamento ad `Avvia.bat`.

## Come capisce se Roblox è chiuso

| Situazione | Cosa fa |
|---|---|
| Nessun processo di Roblox | Interviene subito |
| Processo attivo ma senza finestra (chiuso con la X, oppure c'è solo la finestra di errore/crash) | Interviene dopo 10 secondi (Roblox appena aperto non ha ancora la finestra) |
| Finestra di Roblox che "Non risponde" | Interviene dopo 60 secondi |
| Gioco non trovato nella home | Chiude Roblox e ricomincia (messaggio "Roblox crash/chiuso") |
| YBA bloccato nella schermata di caricamento | Chiude Roblox e ricomincia (messaggio "YBA bloccato nel caricamento") |
| Finestra "Disconnected" per 15 secondi | Clicca "Reconnect" (messaggio "Reconnect issue"); dopo 3 tentativi riavvia Roblox |

## Impostazioni avanzate (`config.json`)

Si può modificare con il Blocco note (meglio con APP YBA chiusa):

| Campo | Default | Significato |
|---|---|---|
| `MessageCrash` | `Roblox crash/chiuso` | Messaggio Discord quando Roblox si chiude, crasha o non risponde |
| `MessageLoading` | `YBA bloccato nel caricamento` | Messaggio Discord quando YBA resta bloccato nel caricamento |
| `MessageReconnect` | `Reconnect issue` | Messaggio Discord quando Roblox si disconnette |
| `ScreenCheckEverySeconds` | `1` | Ogni quanti secondi legge lo schermo (caricamento e disconnessione) |
| `DisconnectText` | `Disconnected` | Titolo della finestra di disconnessione di Roblox (vuoto = nessun controllo) |
| `ReconnectText` | `Reconnect` | Bottone da cliccare per riconnettersi |
| `DisconnectTimeoutSeconds` | `15` | Dopo quanti secondi di finestra di disconnessione clicca il bottone |
| `ReconnectMaxAttempts` | `3` | Tentativi di riconnessione prima di riavviare Roblox (`0` = non riavviare mai) |
| `CheckIntervalSeconds` | `2` | Ogni quanti secondi controlla Roblox |
| `RobloxProcessNames` | `["RobloxPlayerBeta"]` | Nomi dei processi di Roblox |
| `NoWindowGraceSeconds` | `10` | Attesa se il processo è attivo ma la finestra non c'è |
| `FreezeTimeoutSeconds` | `60` | Attesa se Roblox non risponde (`0` = non controllare) |
| `RobloxStartTimeoutSeconds` | `10` | Tempo massimo per l'apertura di Roblox dopo il click |
| `RobloxWindowTimeoutSeconds` | `60` | Tempo massimo perché compaia la finestra di Roblox |
| `Launcher.StartupTimeoutSeconds` | `30` | Tempo massimo per l'apertura della tua app |
| `Launcher.LoadDelaySeconds` | `3` | Attesa dopo l'apertura dell'app, prima del click |
| `Join.DelayBeforeSeconds` | `20` | (scelta 3) attesa dopo l'apertura di Roblox, prima dei passi: la home deve essere caricata |
| `Join.LoadingText` | `LOADING ASSETS` | Scritta che si vede solo nella schermata di caricamento di YBA (vuoto = nessun controllo) |
| `Join.LoadingStuckChecks` | `15` | Dopo quante letture di fila con quella scritta (una al secondo) la considera bloccata |
| `Join.Clicks[].MaxScrolls` | `15` | (passo "Cerca") quante volte scrolla al massimo prima di riavviare Roblox |
| `Join.ScrollPauseMilliseconds` | `1500` | (scelta 3) pausa ogni 5 scatti di scroll, per dare tempo a Roblox di caricare la home. Se lo scroll si ferma prima, aumentala (es. `3000`) |
| `FinalClicks.SecondsAfterJoin` | `10` | Attesa dopo l'ingresso nel gioco (con la scelta 1: dopo l'apertura di Roblox), prima dei click finali |
| `...Clicks[].DelayAfterSeconds` | `2`/`3` | Attesa dopo ogni click |
