# APP YBA

Controlla Roblox ogni 2 secondi. Se Roblox si chiude o crasha:

1. manda **"Roblox si è chiuso/crash"** sul tuo webhook Discord e ti pinga;
2. se il processo di Roblox è rimasto aperto nel Task Manager (succede quando lo chiudi con la X), lo chiude;
3. apre la tua app e clicca il bottone che apre Roblox; se Roblox non si apre entro 10 secondi ricomincia dal punto 1;
4. entra in **Your Bizarre Adventure**;
5. fa i 2 click finali sulla tua app.

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

   **Caricamento bloccato** (per tutte le scelte): entra in YBA e, quando vedi la schermata di caricamento,
   premi **F8**. Il Setup ti mostra le scritte che legge: scegli una parola che c'è **solo** lì (es. `Loading`).
   Se dopo l'ingresso nel gioco quella parola si vede ancora dopo 2 minuti (si può cambiare), l'app chiude
   Roblox e ricomincia dallo step 1.
5. **I 2 click finali**: mouse sopra il primo bottone dell'app + **F8**, poi sopra il secondo + **F8**.
   Poi scegli quanti secondi aspettare (prima del primo click, il gioco deve fare in tempo a caricare) e quanti tra un click e l'altro.

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
| Gioco non trovato nella home, o YBA bloccato nella schermata di caricamento | Chiude Roblox e ricomincia |

## Impostazioni avanzate (`config.json`)

Si può modificare con il Blocco note (meglio con APP YBA chiusa):

| Campo | Default | Significato |
|---|---|---|
| `Message` | `Roblox si è chiuso/crash` | Testo del messaggio Discord |
| `CheckIntervalSeconds` | `2` | Ogni quanti secondi controlla Roblox |
| `RobloxProcessNames` | `["RobloxPlayerBeta"]` | Nomi dei processi di Roblox |
| `NoWindowGraceSeconds` | `10` | Attesa se il processo è attivo ma la finestra non c'è |
| `FreezeTimeoutSeconds` | `60` | Attesa se Roblox non risponde (`0` = non controllare) |
| `RobloxStartTimeoutSeconds` | `10` | Tempo massimo per l'apertura di Roblox dopo il click |
| `RobloxWindowTimeoutSeconds` | `60` | Tempo massimo perché compaia la finestra di Roblox |
| `Launcher.StartupTimeoutSeconds` | `30` | Tempo massimo per l'apertura della tua app |
| `Launcher.LoadDelaySeconds` | `3` | Attesa dopo l'apertura dell'app, prima del click |
| `Join.DelayBeforeSeconds` | `20` | (scelta 3) attesa dopo l'apertura di Roblox, prima dei passi: la home deve essere caricata |
| `Join.LoadingText` | (vuoto) | Parola che si vede solo nella schermata di caricamento di YBA (vuoto = nessun controllo) |
| `Join.LoadingTimeoutSeconds` | `120` | Dopo quanti secondi con quella parola ancora visibile chiude Roblox |
| `Join.Clicks[].MaxScrolls` | `15` | (passo "Cerca") quante volte scrolla al massimo prima di riavviare Roblox |
| `Join.ScrollPauseMilliseconds` | `1500` | (scelta 3) pausa ogni 5 scatti di scroll, per dare tempo a Roblox di caricare la home. Se lo scroll si ferma prima, aumentala (es. `3000`) |
| `FinalClicks.DelayBeforeSeconds` | `30` | Attesa dopo l'ingresso nel gioco, prima dei click finali |
| `...Clicks[].DelayAfterSeconds` | `2`/`3` | Attesa dopo ogni click |
