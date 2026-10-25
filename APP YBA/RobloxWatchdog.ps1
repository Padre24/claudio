#Requires -Version 5.1
# APP YBA - controlla Roblox ogni pochi secondi e, se si chiude o crasha:
#   avvisa su Discord, chiude il processo rimasto appeso, lo riapre dall'app,
#   entra in Your Bizarre Adventure e fa i click finali sull'app.

. (Join-Path $PSScriptRoot 'Common.ps1')

function Get-RobloxProcesses {
    param($Config)
    @(Get-Process -Name $Config.RobloxProcessNames -ErrorAction SilentlyContinue)
}

# Finestre "vere" di Roblox: esclude i dialoghi di errore (es. "Roblox Crash") e le finestre senza titolo.
function Get-RobloxGameWindows {
    param($Config)
    $ids = @(Get-RobloxProcesses $Config | ForEach-Object { $_.Id })
    @(Get-YbaWindows -ProcessIds $ids | Where-Object { $_.Title -and $_.ClassName -ne '#32770' })
}

# Open     = Roblox aperto e funzionante
# Closed   = nessun processo di Roblox
# NoWindow = processo ancora attivo ma senza finestra (chiuso con la X ma rimasto nel Task Manager)
# Frozen   = finestra aperta ma "Non risponde"
function Get-RobloxStatus {
    param($Config)
    if (@(Get-RobloxProcesses $Config).Count -eq 0) { return 'Closed' }
    $windows = @(Get-RobloxGameWindows $Config)
    if ($windows.Count -eq 0) { return 'NoWindow' }
    foreach ($window in $windows) {
        if (-not [YbaWin32]::IsHungAppWindow($window.Handle)) { return 'Open' }
    }
    return 'Frozen'
}

function Wait-Condition {
    param([scriptblock]$Condition, [double]$TimeoutSeconds, [int]$PollMilliseconds = 500)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (& $Condition) { return $true }
        Start-Sleep -Milliseconds $PollMilliseconds
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Stop-RobloxProcesses {
    param($Config)
    $processes = @(Get-RobloxProcesses $Config)
    if ($processes.Count -eq 0) {
        Write-YbaLog 'Nessun processo di Roblox rimasto aperto.'
        return
    }
    $list = ($processes | ForEach-Object { '{0}.exe (PID {1})' -f $_.ProcessName, $_.Id }) -join ', '
    Write-YbaLog "Il processo di Roblox è ancora attivo: lo chiudo -> $list" Yellow
    foreach ($process in $processes) {
        try { $process.Kill() } catch { Write-YbaLog ("Non riesco a chiudere PID {0}: {1}" -f $process.Id, $_.Exception.Message) Red }
    }
    if (-not (Wait-Condition { @(Get-RobloxProcesses $Config).Count -eq 0 } 10)) {
        Write-YbaLog 'Roblox non si è chiuso del tutto, continuo lo stesso.' Yellow
    }
}

# Esegue un passo registrato nel Setup: un click oppure (Type = 'Scroll') degli scatti di rotellina.
function Invoke-ConfiguredClick {
    param($Click, [int]$ScrollPauseMilliseconds = 1500)
    $window = Get-YbaTargetWindow -ProcessName $Click.ProcessName -WindowTitle $Click.WindowTitle
    if ($null -eq $window) {
        Write-YbaLog ("Non trovo la finestra di {0}.exe per '{1}'." -f $Click.ProcessName, $Click.Name) Red
        return $false
    }
    $isScroll = $Click.Type -eq 'Scroll'
    if ($isScroll) {
        $how = switch ($Click.Method) {
            'Drag'    { 'trascinamento' }
            'Message' { '{0} scatti mandati direttamente a Roblox' -f $Click.Amount }
            default   { '{0} scatti di rotellina' -f $Click.Amount }
        }
        Write-YbaLog ("Scroll: {0} ({1})" -f $Click.Name, $how)
    } else {
        Write-YbaLog ("Click: {0}" -f $Click.Name)
    }
    if (-not $Script:IsAdmin -and [YbaWin32]::IsProcessElevated($window.ProcessId)) {
        Write-YbaLog ("{0}.exe è avviata come amministratore: Windows blocca il click. Avvia Avvia.bat come amministratore." -f $Click.ProcessName) Red
    }
    [YbaWin32]::FocusWindow($window.Handle)
    Start-Sleep -Milliseconds 500
    if (-not [YbaWin32]::IsForeground($window.Handle)) {
        Write-YbaLog ("Attenzione: Windows non mi lascia mettere in primo piano {0}.exe." -f $Click.ProcessName) Yellow
    }
    if ($isScroll) {
        Invoke-YbaScrollStep -Handle $window.Handle -Step $Click -PauseMilliseconds $ScrollPauseMilliseconds
    } else {
        [void][YbaWin32]::ClickInWindow($window.Handle, [int]$Click.X, [int]$Click.Y)
    }
    return $true
}

# Passo "Cerca": legge lo schermo di Roblox e clicca il gioco, scrollando finché non lo trova.
function Invoke-FindStep {
    param($Step, [int]$ScrollPauseMilliseconds = 1500)
    $window = Get-YbaTargetWindow -ProcessName $Step.ProcessName -WindowTitle $Step.WindowTitle
    if ($null -eq $window) {
        Write-YbaLog ("Non trovo la finestra di {0}.exe per cercare il gioco." -f $Step.ProcessName) Red
        return $false
    }
    Write-YbaLog ("Cerco il gioco sullo schermo (al massimo {0} scroll)..." -f $Step.MaxScrolls)
    $result = Invoke-YbaFind -Handle $window.Handle -Step $Step -PauseMilliseconds $ScrollPauseMilliseconds
    switch ($result) {
        'Found' { return $true }
        'Unreadable' { Write-YbaLog 'Non riesco a leggere lo schermo (monitor spento da Windows o schermo bloccato?).' Red }
        default { Write-YbaLog ("Gioco non trovato dopo {0} scroll." -f $Step.MaxScrolls) Red }
    }
    return $false
}

function Invoke-ClickSequence {
    param([object[]]$Clicks, [int]$ScrollPauseMilliseconds = 1500)
    foreach ($click in @($Clicks)) {
        $done = if ($click.Type -eq 'Find') { Invoke-FindStep $click $ScrollPauseMilliseconds } else { Invoke-ConfiguredClick $click $ScrollPauseMilliseconds }
        if (-not $done) { return $false }
        Start-Sleep -Seconds ([int]$click.DelayAfterSeconds)
    }
    return $true
}

# Stato del controllo della schermata di caricamento di YBA: quante letture di fila con la scritta.
function New-LoadingWatch {
    [pscustomobject]@{ Count = 0 }
}

# Aggiorna lo stato con le scritte appena lette sullo schermo (una lettura al secondo). Restituisce:
#   'Loading'    = si vede la schermata di caricamento
#   'NotLoading' = non si vede (il conteggio riparte da zero)
#   'Stuck'      = si è vista per LoadingStuckChecks letture di fila
function Update-LoadingWatch {
    param($Config, $Watch, $Lines)
    if ($null -eq (Find-YbaText -Lines $Lines -Needle $Config.Join.LoadingText)) {
        $Watch.Count = 0
        return 'NotLoading'
    }
    $Watch.Count++
    # Le scritte cercate non vanno scritte qui: se questa finestra coprisse Roblox, verrebbero lette anche da qui.
    if ($Watch.Count -eq 1) { Write-YbaLog 'Vedo la schermata di caricamento di YBA.' }
    if ($Watch.Count -lt [int]$Config.Join.LoadingStuckChecks) { return 'Loading' }
    Write-YbaLog ("YBA è bloccato nella schermata di caricamento ({0} letture di fila)." -f $Watch.Count) Red
    return 'Stuck'
}

# Stato del controllo della finestra "Disconnected" di Roblox.
function New-DisconnectWatch {
    [pscustomobject]@{ Since = $null; LastSeen = $null; Attempts = 0 }
}

# Aggiorna lo stato con le scritte appena lette sullo schermo. Restituisce:
#   'None'     = la finestra di disconnessione non c'è
#   'Waiting'  = c'è da meno di DisconnectTimeoutSeconds
#   'Clicked'  = c'era da troppo: ha cliccato il bottone per riconnettersi (Attempts = numero del tentativo)
#   'NoButton' = c'era da troppo ma il bottone non si trova (conta comunque come tentativo)
#   'GiveUp'   = già fatti ReconnectMaxAttempts tentativi: meglio riavviare Roblox
# I tentativi ripartono da zero quando la finestra non si vede per 2 minuti.
function Update-DisconnectWatch {
    param($Config, $Watch, $Lines, [IntPtr]$Handle)
    $now = Get-Date
    if ($null -eq (Find-YbaText -Lines $Lines -Needle $Config.DisconnectText)) {
        $Watch.Since = $null
        if ($Watch.LastSeen -and ($now - $Watch.LastSeen).TotalSeconds -ge 120) {
            $Watch.Attempts = 0
            $Watch.LastSeen = $null
        }
        return 'None'
    }
    $Watch.LastSeen = $now
    if (-not $Watch.Since) {
        # Le scritte cercate non vanno scritte qui: se questa finestra coprisse Roblox, verrebbero lette anche da qui.
        Write-YbaLog 'Roblox ha perso la connessione al server.' Yellow
        $Watch.Since = $now
    }
    $timeout = [int]$Config.DisconnectTimeoutSeconds
    if (($now - $Watch.Since).TotalSeconds -lt $timeout) { return 'Waiting' }
    $max = [int]$Config.ReconnectMaxAttempts
    if ($max -gt 0 -and $Watch.Attempts -ge $max) {
        Write-YbaLog ("Ancora senza connessione dopo {0} tentativi." -f $Watch.Attempts) Red
        return 'GiveUp'
    }
    $Watch.Attempts++
    $Watch.Since = $null
    # Il bottone è sotto al messaggio, che a volte contiene la stessa parola: si prende quella più in basso.
    $button = Find-YbaText -Lines $Lines -Needle $Config.ReconnectText -Lowest
    if ($null -eq $button -or -not [YbaWin32]::IsPointOnWindow($Handle, $button.X, $button.Y)) {
        Write-YbaLog 'Non trovo il bottone per riconnettermi.' Yellow
        return 'NoButton'
    }
    Write-YbaLog ("Senza connessione da {0} secondi: clicco per riconnettermi (tentativo {1})." -f $timeout, $Watch.Attempts) Yellow
    [YbaWin32]::FocusWindow($Handle)
    Start-Sleep -Milliseconds 300
    [void][YbaWin32]::ClickInWindow($Handle, $button.X, $button.Y)
    return 'Clicked'
}

# Controlli continui mentre Roblox è aperto, con una sola lettura dello schermo:
# disconnessione (clicca per riconnettersi) e caricamento bloccato.
# Restituisce 'LoadingStuck' o 'ReconnectGiveUp' quando bisogna riavviare Roblox, sennò ''.
# Stato del controllo della schermata iniziale ("PATCH NOTES") ferma.
function New-PatchNotesWatch {
    [pscustomobject]@{ Count = 0; Clicked = $false }
}

function Test-PatchNotesCheck {
    param($Config)
    [bool]($Config.PatchNotes.Text -and $Config.PatchNotes.Click)
}

# Aggiorna lo stato con le scritte appena lette (una lettura al secondo). $true = è il momento di fare il click:
# la scritta si è vista per PatchNotes.StuckChecks letture di fila. Un solo click: il prossimo solo dopo che
# la scritta è sparita ed è ricomparsa.
function Update-PatchNotesWatch {
    param($Config, $Watch, $Lines)
    if ($null -eq (Find-YbaText -Lines $Lines -Needle $Config.PatchNotes.Text)) {
        $Watch.Count = 0
        $Watch.Clicked = $false
        return $false
    }
    $Watch.Count++
    if ($Watch.Clicked -or $Watch.Count -lt [int]$Config.PatchNotes.StuckChecks) { return $false }
    $Watch.Clicked = $true
    return $true
}

function Invoke-ScreenChecks {
    param($Config, $LoadingWatch, $DisconnectWatch, $PatchNotesWatch)
    $window = @(Get-RobloxGameWindows $Config) | Select-Object -First 1
    if (-not $window) { return '' }
    $lines = Get-YbaScreenLines -Handle $window.Handle -Fast
    if ($null -eq $lines) { return '' }
    if ($Config.DisconnectText) {
        $disconnect = Update-DisconnectWatch $Config $DisconnectWatch $lines $window.Handle
        if ($disconnect -eq 'GiveUp') { return 'ReconnectGiveUp' }
        if ($disconnect -eq 'Clicked' -or $disconnect -eq 'NoButton') {
            # Un solo avviso per disconnessione, non uno per ogni tentativo.
            if ($DisconnectWatch.Attempts -eq 1) { [void](Send-YbaDiscordMessage -Config $Config -Text $Config.MessageReconnect) }
            return ''
        }
        if ($disconnect -eq 'Waiting') { return '' }
    }
    if ((Test-PatchNotesCheck $Config) -and (Update-PatchNotesWatch $Config $PatchNotesWatch $lines)) {
        # Le scritte cercate non vanno scritte qui: se questa finestra coprisse Roblox, verrebbero lette anche da qui.
        Write-YbaLog ("Il gioco è fermo sulla schermata iniziale da {0} letture di fila: faccio il click sull'app." -f $PatchNotesWatch.Count) Yellow
        if ($Config.MessagePatchNotes) { [void](Send-YbaDiscordMessage -Config $Config -Text $Config.MessagePatchNotes) }
        [void](Invoke-ConfiguredClick $Config.PatchNotes.Click)
    }
    if ($Config.Join.LoadingText -and (Update-LoadingWatch $Config $LoadingWatch $lines) -eq 'Stuck') { return 'LoadingStuck' }
    return ''
}

# Apre l'app che lancia Roblox (se non è già aperta) e restituisce la sua finestra.
function Open-Launcher {
    param($Config)
    $button = $Config.Launcher.LaunchButton
    $window = Get-YbaTargetWindow -ProcessName $button.ProcessName -WindowTitle $button.WindowTitle
    if ($null -ne $window) { return $window }

    $path = $Config.Launcher.Path
    if (-not $path -or -not (Test-Path -LiteralPath $path)) {
        Write-YbaLog "Percorso dell'app non valido ('$path'): esegui di nuovo Setup.bat." Red
        return $null
    }
    Write-YbaLog "Apro l'app: $path"
    Start-Process -FilePath $path -WorkingDirectory (Split-Path -Parent $path)
    $opened = Wait-Condition { $null -ne (Get-YbaTargetWindow -ProcessName $button.ProcessName -WindowTitle $button.WindowTitle) } $Config.Launcher.StartupTimeoutSeconds
    if (-not $opened) {
        Write-YbaLog "L'app non si è aperta entro $($Config.Launcher.StartupTimeoutSeconds) secondi." Red
        return $null
    }
    Start-Sleep -Seconds ([int]$Config.Launcher.LoadDelaySeconds)
    return Get-YbaTargetWindow -ProcessName $button.ProcessName -WindowTitle $button.WindowTitle
}

function Wait-RobloxWindow {
    param($Config)
    $ok = Wait-Condition { @(Get-RobloxGameWindows $Config).Count -gt 0 } $Config.RobloxWindowTimeoutSeconds
    if (-not $ok) { Write-YbaLog "La finestra di Roblox non è comparsa entro $($Config.RobloxWindowTimeoutSeconds) secondi." Red }
    return $ok
}

# Step 4: entrare in Your Bizarre Adventure.
function Enter-Game {
    param($Config)
    switch ($Config.Join.Method) {
        'Link' {
            $uri = 'roblox://placeId=' + $Config.Join.PlaceId
            Write-YbaLog "Entro in YBA con il link $uri"
            Start-Process $uri
            Start-Sleep -Seconds 5
            return (Wait-RobloxWindow $Config)
        }
        'Clicks' {
            Write-YbaLog 'Entro in YBA con i passi registrati in Roblox.'
            # Click iniziale appena Roblox si apre (senza, Roblox non "prende" il mouse) e di nuovo prima dei passi.
            $initial = $Config.Join.InitialClick
            if ($initial) { [void](Invoke-ConfiguredClick $initial) }
            Start-Sleep -Seconds ([int]$Config.Join.DelayBeforeSeconds)
            if ($initial) {
                [void](Invoke-ConfiguredClick $initial)
                Start-Sleep -Seconds 1
            }
            return (Invoke-ClickSequence $Config.Join.Clicks $Config.Join.ScrollPauseMilliseconds)
        }
        default {
            Write-YbaLog "Il bottone dell'app entra già in YBA."
            return $true
        }
    }
}

# $Alert = messaggio Discord per questa situazione ('' = nessun messaggio).
function Invoke-Recovery {
    param($Config, [string]$Reason, [string]$Alert)
    Write-YbaLog "ROBLOX $Reason" Red

    # Step 2: avviso su Discord + controllo del processo rimasto aperto.
    if ($Alert) { [void](Send-YbaDiscordMessage -Config $Config -Text $Alert) }
    Stop-RobloxProcesses $Config

    # Step 3: aprire l'app e cliccare il bottone che apre Roblox.
    $launcher = Open-Launcher $Config
    if ($null -eq $launcher) { return }
    $before = @(Get-RobloxProcesses $Config | ForEach-Object { $_.Id })
    if (-not (Invoke-ConfiguredClick $Config.Launcher.LaunchButton)) { return }
    $timeout = $Config.RobloxStartTimeoutSeconds
    Write-YbaLog "Aspetto che Roblox si apra (massimo $timeout secondi)..."
    $started = Wait-Condition { @(Get-RobloxProcesses $Config | Where-Object { $before -notcontains $_.Id }).Count -gt 0 } $timeout
    if (-not $started) {
        Write-YbaLog "Roblox non si è aperto entro $timeout secondi: ricomincio dal controllo." Yellow
        return
    }
    if (-not (Wait-RobloxWindow $Config)) { return }
    Write-YbaLog 'Roblox aperto.' Green

    # Step 4: entrare nel gioco. Se non ci riesce (es. gioco non trovato) chiude Roblox:
    # al prossimo controllo risulta chiuso e si ricomincia dallo step 1.
    if (-not (Enter-Game $Config)) {
        Write-YbaLog 'Non sono riuscito a entrare nel gioco: chiudo Roblox e ricomincio.' Yellow
        Stop-RobloxProcesses $Config
        return
    }
    # Step 5: i click finali sull'app, SecondsAfterJoin secondi dopo l'ingresso nel gioco (senza aspettare
    # la fine del caricamento: se resta bloccato se ne accorge il controllo continuo).
    $finalClicks = @($Config.FinalClicks.Clicks)
    if ($finalClicks.Count -gt 0) {
        $delay = [int]$Config.FinalClicks.SecondsAfterJoin
        Write-YbaLog "Aspetto $delay secondi, poi faccio i click finali."
        Start-Sleep -Seconds $delay
        if (@(Get-RobloxGameWindows $Config).Count -eq 0) {
            Write-YbaLog 'Roblox si è chiuso mentre caricava: ricomincio dal controllo.' Yellow
            return
        }
        if (-not (Invoke-ClickSequence $finalClicks)) { return }
    }
    Write-YbaLog 'Recupero completato: torno a controllare Roblox.' Green
}

function Test-WatchdogConfig {
    param($Config)
    $ok = $true
    if (-not $Config.Launcher.LaunchButton) {
        Write-YbaLog "Manca il bottone dell'app che apre Roblox: esegui Setup.bat." Red
        $ok = $false
    }
    if (-not $Config.Launcher.Path) {
        Write-YbaLog "Manca il percorso dell'app che apre Roblox: esegui Setup.bat." Red
        $ok = $false
    }
    if (-not $Config.WebhookUrl) { Write-YbaLog 'Webhook Discord non impostato: non arriveranno avvisi.' Yellow }
    return $ok
}

function Set-StatusTitle {
    param([string]$Text)
    try { $Host.UI.RawUI.WindowTitle = 'APP YBA - Roblox: {0} ({1})' -f $Text, (Get-Date -Format 'HH:mm:ss') } catch { }
}

# Windows blocca i click verso le app avviate come amministratore: in quel caso serve esserlo anche noi.
function Restart-AsAdmin {
    Write-YbaLog "L'app che apre Roblox è avviata come amministratore: riavvio APP YBA come amministratore." Yellow
    try {
        Start-Process -FilePath (Join-Path $PSScriptRoot 'Avvia.bat') -Verb RunAs
        Write-Host 'APP YBA continua nella nuova finestra: questa si può chiudere.' -ForegroundColor Green
        return $true
    } catch {
        Write-YbaLog "Permesso negato: continuo senza amministratore, ma i click sull'app potrebbero non funzionare." Red
        return $false
    }
}

function Start-YbaWatchdog {
    Initialize-YbaEnvironment

    if (-not (Test-YbaConfigExists)) {
        Write-Host 'Configurazione mancante: esegui prima Setup.bat.' -ForegroundColor Red
        return
    }
    $config = Read-YbaConfig
    if (-not (Test-WatchdogConfig $config)) { return }

    $Script:IsAdmin = [YbaWin32]::IsProcessElevated($PID)
    if ($config.Launcher.RunAsAdmin -and -not $Script:IsAdmin) {
        if (Restart-AsAdmin) { return }
    }

    $createdNew = $false
    $Script:InstanceMutex = [System.Threading.Mutex]::new($true, 'Local\APP_YBA_RobloxWatchdog', [ref]$createdNew)
    if (-not $createdNew) {
        Write-Host "APP YBA è già in esecuzione in un'altra finestra." -ForegroundColor Yellow
        return
    }

    $interval = [Math]::Max(1, [int]$config.CheckIntervalSeconds)
    Write-YbaLog "APP YBA avviata: controllo Roblox ogni $interval secondi. Chiudi questa finestra (o CTRL+C) per fermarla." Cyan

    $statusText = @{ Open = 'aperto'; Closed = 'chiuso'; NoWindow = 'chiuso ma processo ancora attivo'; Frozen = 'non risponde' }
    $lastStatus = ''
    $problemStatus = ''
    $problemSince = Get-Date
    # Caricamento bloccato e disconnessione: controllati sempre mentre Roblox è aperto, leggendo lo schermo.
    $loadingWatch = New-LoadingWatch
    $disconnectWatch = New-DisconnectWatch
    $patchNotesWatch = New-PatchNotesWatch
    $screenChecks = [bool]($config.Join.LoadingText -or $config.DisconnectText -or (Test-PatchNotesCheck $config))
    $screenEvery = [Math]::Max(0, [int]$config.ScreenCheckEverySeconds)
    $nextScreenCheck = Get-Date
    # Con i controlli dello schermo attivi il giro dura quanto l'intervallo fra due letture (di solito 1 secondo).
    $tickMilliseconds = 1000 * $(if ($screenChecks) { [Math]::Max(1, [Math]::Min($interval, $screenEvery)) } else { $interval })
    if ($config.Join.LoadingText) {
        Write-YbaLog ("Controllo del caricamento attivo: leggo lo schermo ogni {0} s, riavvio Roblox dopo {1} letture di fila con la schermata di caricamento." -f $screenEvery, $config.Join.LoadingStuckChecks)
    } else {
        Write-YbaLog 'Controllo del caricamento disattivato (si attiva da Setup.bat).'
    }
    if ($config.DisconnectText) {
        Write-YbaLog ("Controllo della connessione attivo: se Roblox resta senza connessione per {0} secondi provo a riconnettermi." -f $config.DisconnectTimeoutSeconds)
    }
    if (Test-PatchNotesCheck $config) {
        Write-YbaLog ("Controllo della schermata iniziale attivo: dopo {0} letture di fila faccio un click su {1}.exe." -f $config.PatchNotes.StuckChecks, $config.PatchNotes.Click.ProcessName)
    }

    while ($true) {
        $tickStart = Get-Date
        try {
            $status = Get-RobloxStatus $config
            if ($status -ne $lastStatus) {
                $color = if ($status -eq 'Open') { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }
                Write-YbaLog ('Roblox: ' + $statusText[$status]) $color
                $lastStatus = $status
            }
            Set-StatusTitle $statusText[$status]

            if ($status -eq 'Open') {
                $problemStatus = ''
                if ($screenChecks -and (Get-Date) -ge $nextScreenCheck) {
                    # Un po' di margine, così una lettura al secondo non salta un giro per pochi millisecondi.
                    $nextScreenCheck = (Get-Date).AddSeconds($screenEvery).AddMilliseconds(-300)
                    $problem = Invoke-ScreenChecks $config $loadingWatch $disconnectWatch $patchNotesWatch
                    if ($problem) {
                        if ($problem -eq 'LoadingStuck') {
                            Invoke-Recovery $config 'è bloccato nella schermata di caricamento' $config.MessageLoading
                        } else {
                            Invoke-Recovery $config 'non riesce a riconnettersi al server' $config.MessageReconnect
                        }
                        $loadingWatch = New-LoadingWatch
                        $disconnectWatch = New-DisconnectWatch
                        $patchNotesWatch = New-PatchNotesWatch
                        $lastStatus = ''
                    }
                }
            } else {
                $loadingWatch = New-LoadingWatch
                $disconnectWatch = New-DisconnectWatch
                $patchNotesWatch = New-PatchNotesWatch
                if ($status -ne $problemStatus) {
                    $problemStatus = $status
                    $problemSince = Get-Date
                }
                # Chiuso: si interviene subito. Processo senza finestra o bloccato: si aspetta un po'
                # (Roblox appena avviato non ha ancora la finestra, e a volte si blocca per pochi secondi).
                $limit = switch ($status) {
                    'NoWindow' { [int]$config.NoWindowGraceSeconds }
                    'Frozen'   { [int]$config.FreezeTimeoutSeconds }
                    default    { 0 }
                }
                $frozenCheckDisabled = ($status -eq 'Frozen' -and $limit -le 0)
                if (-not $frozenCheckDisabled -and ((Get-Date) - $problemSince).TotalSeconds -ge $limit) {
                    $reason = switch ($status) {
                        'NoWindow' { 'si è chiuso, ma il processo era ancora attivo' }
                        'Frozen'   { "non risponde da più di $limit secondi" }
                        default    { 'si è chiuso/crashato' }
                    }
                    Invoke-Recovery $config $reason $config.MessageCrash
                    $lastStatus = ''
                    $problemStatus = ''
                }
            }
        } catch {
            Write-YbaLog ('Errore: ' + $_.Exception.Message) Red
        }
        $spent = ((Get-Date) - $tickStart).TotalMilliseconds
        Start-Sleep -Milliseconds ([int][Math]::Max(100, $tickMilliseconds - $spent))
    }
}

if ($MyInvocation.InvocationName -ne '.') { Start-YbaWatchdog }
