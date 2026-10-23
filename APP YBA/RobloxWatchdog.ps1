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
    param($Click)
    $window = Get-YbaTargetWindow -ProcessName $Click.ProcessName -WindowTitle $Click.WindowTitle
    if ($null -eq $window) {
        Write-YbaLog ("Non trovo la finestra di {0}.exe per '{1}'." -f $Click.ProcessName, $Click.Name) Red
        return $false
    }
    $isScroll = $Click.Type -eq 'Scroll'
    if ($isScroll) { Write-YbaLog ("Scroll: {0} ({1} scatti)" -f $Click.Name, $Click.Amount) }
    else { Write-YbaLog ("Click: {0}" -f $Click.Name) }
    if (-not $Script:IsAdmin -and [YbaWin32]::IsProcessElevated($window.ProcessId)) {
        Write-YbaLog ("{0}.exe è avviata come amministratore: Windows blocca il click. Avvia Avvia.bat come amministratore." -f $Click.ProcessName) Red
    }
    [YbaWin32]::FocusWindow($window.Handle)
    Start-Sleep -Milliseconds 500
    if ($isScroll) {
        [void][YbaWin32]::ScrollInWindow($window.Handle, [int]$Click.X, [int]$Click.Y, [int]$Click.Amount)
    } else {
        [void][YbaWin32]::ClickInWindow($window.Handle, [int]$Click.X, [int]$Click.Y)
    }
    return $true
}

function Invoke-ClickSequence {
    param([object[]]$Clicks)
    foreach ($click in @($Clicks)) {
        if (-not (Invoke-ConfiguredClick $click)) { return $false }
        Start-Sleep -Seconds ([int]$click.DelayAfterSeconds)
    }
    return $true
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
            Write-YbaLog "Entro in Your Bizarre Adventure con il link $uri"
            Start-Process $uri
            Start-Sleep -Seconds 5
            return (Wait-RobloxWindow $Config)
        }
        'Clicks' {
            Write-YbaLog 'Entro in Your Bizarre Adventure con i passi registrati in Roblox.'
            Start-Sleep -Seconds ([int]$Config.Join.DelayBeforeSeconds)
            return (Invoke-ClickSequence $Config.Join.Clicks)
        }
        default {
            Write-YbaLog "Il bottone dell'app entra già in Your Bizarre Adventure."
            return $true
        }
    }
}

function Invoke-Recovery {
    param($Config, [string]$Reason)
    Write-YbaLog "ROBLOX $Reason" Red

    # Step 2: avviso su Discord + controllo del processo rimasto aperto.
    [void](Send-YbaDiscordMessage -Config $Config -Text $Config.Message)
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

    # Step 4: entrare nel gioco.
    if (-not (Enter-Game $Config)) { return }

    # Step 5: i click finali sull'app.
    $finalClicks = @($Config.FinalClicks.Clicks)
    if ($finalClicks.Count -gt 0) {
        $delay = [int]$Config.FinalClicks.DelayBeforeSeconds
        Write-YbaLog "Aspetto $delay secondi che il gioco carichi, poi faccio i click finali."
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

    while ($true) {
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
            } else {
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
                    Invoke-Recovery $config $reason
                    $lastStatus = ''
                    $problemStatus = ''
                }
            }
        } catch {
            Write-YbaLog ('Errore: ' + $_.Exception.Message) Red
        }
        Start-Sleep -Seconds $interval
    }
}

if ($MyInvocation.InvocationName -ne '.') { Start-YbaWatchdog }
