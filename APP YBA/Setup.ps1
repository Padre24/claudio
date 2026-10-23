#Requires -Version 5.1
# APP YBA - Setup guidato: crea config.json (webhook, app che apre Roblox, click da fare).

. (Join-Path $PSScriptRoot 'Common.ps1')

$VK_F8 = 0x77
$ConsoleProcesses = @('powershell', 'pwsh', 'WindowsTerminal', 'OpenConsole', 'conhost', 'cmd')
$WebhookPattern = '^https://([a-z]+\.)?discord(app)?\.com/api/webhooks/\d+/[\w-]+'

function Write-Step {
    param([int]$Number, [string]$Title)
    Write-Host ''
    Write-Host ("[{0}/5] {1}" -f $Number, $Title) -ForegroundColor Cyan
    Write-Host ('-' * 60) -ForegroundColor DarkGray
}

function Read-Answer {
    param([string]$Prompt, [string]$Default = '')
    $suffix = if ($Default -ne '') { " [$Default]" } else { '' }
    $answer = Read-Host ($Prompt + $suffix)
    if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
    return $answer.Trim()
}

function Read-YesNo {
    param([string]$Prompt, [bool]$Default = $true)
    $hint = if ($Default) { 'S/n' } else { 's/N' }
    while ($true) {
        $answer = Read-Host "$Prompt ($hint)"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        if ($answer.Trim() -match '^(s|si|sì|y|yes)$') { return $true }
        if ($answer.Trim() -match '^(n|no)$') { return $false }
    }
}

function Read-Number {
    param([string]$Prompt, [int]$Default, [int]$Min = 0)
    while ($true) {
        $answer = Read-Answer $Prompt ([string]$Default)
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge $Min) { return $number }
        Write-Host "  Scrivi un numero (minimo $Min)." -ForegroundColor Yellow
    }
}

function Wait-KeyRelease {
    param([int]$Key)
    while ([YbaWin32]::IsKeyDown($Key)) { Start-Sleep -Milliseconds 30 }
}

# 'Now' = F8 premuto (ovunque), 'Countdown' = INVIO premuto in questa finestra.
# F8 a volte non arriva (portatili senza Fn, app avviate come amministratore): INVIO funziona sempre.
function Wait-Trigger {
    Wait-KeyRelease $VK_F8
    while ([YbaWin32]::ReadConsoleKey() -ne 0) { }
    while ($true) {
        if ([YbaWin32]::IsKeyDown($VK_F8)) { Wait-KeyRelease $VK_F8; return 'Now' }
        if ([YbaWin32]::ReadConsoleKey() -eq [int][ConsoleKey]::Enter) { return 'Countdown' }
        Start-Sleep -Milliseconds 30
    }
}

function Get-CursorTarget {
    $target = [YbaWin32]::GetCursorTarget()
    if ($null -eq $target) { return $null }
    $process = Get-Process -Id $target.ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $process) { return $null }
    [pscustomobject]@{
        ProcessName = $process.ProcessName
        Path        = [YbaWin32]::GetProcessPath($target.ProcessId)
        Elevated    = [YbaWin32]::IsProcessElevated($target.ProcessId)
        WindowTitle = [YbaWin32]::GetTitle($target.Window)
        X           = $target.OffsetX
        Y           = $target.OffsetY
    }
}

# Registra la posizione del mouse quando l'utente preme F8 o dopo il conto alla rovescia.
function Read-ClickTarget {
    param([string]$Label, [string]$ExpectedProcess = '', [string]$Hint = 'il punto da cliccare')
    while ($true) {
        Write-Host ''
        Write-Host "  >> $Label" -ForegroundColor White
        Write-Host "     Metti il mouse SOPRA $Hint (senza cliccare) e premi F8 (sui portatili: Fn+F8)."
        Write-Host '     Se F8 non funziona: premi INVIO qui, poi hai 5 secondi per mettere il mouse al suo posto.'
        if ((Wait-Trigger) -eq 'Countdown') {
            Write-Host '     Metti il mouse al suo posto (deve essere visibile, non coperto da questa finestra): ' -NoNewline
            for ($second = 5; $second -ge 1; $second--) {
                Write-Host "$second... " -NoNewline -ForegroundColor Cyan
                Start-Sleep -Seconds 1
            }
            Write-Host ''
        }
        $target = Get-CursorTarget
        try { [Console]::Beep(880, 120) } catch { }
        [YbaWin32]::FocusConsole()
        if ($null -eq $target) {
            Write-Host '     Non trovo nessuna finestra sotto il mouse, riprova.' -ForegroundColor Yellow
            continue
        }
        if ($ConsoleProcesses -contains $target.ProcessName) {
            Write-Host "     Il mouse era sopra questa finestra nera: mettilo sopra l'app giusta e riprova." -ForegroundColor Yellow
            continue
        }
        Write-Host ("     Registrato: finestra '{0}' ({1}.exe), punto X={2} Y={3} nella finestra." -f $target.WindowTitle, $target.ProcessName, $target.X, $target.Y) -ForegroundColor Green
        if ($ExpectedProcess -and $target.ProcessName -ne $ExpectedProcess) {
            Write-Host "     Attenzione: mi aspettavo un punto dentro $ExpectedProcess.exe." -ForegroundColor Yellow
            if (-not (Read-YesNo '     Lo tengo lo stesso?' $false)) { continue }
        }
        return $target
    }
}

# Fa subito il click appena registrato: si vede se funziona e Roblox passa alla schermata del click dopo.
function Test-RecordedClick {
    param($Target, [string]$Question = '     Ha funzionato?')
    $window = Get-YbaTargetWindow -ProcessName $Target.ProcessName -WindowTitle $Target.WindowTitle
    if ($null -eq $window) { return $true }
    Write-Host '     Lo clicco adesso: guarda Roblox.'
    [YbaWin32]::FocusWindow($window.Handle)
    Start-Sleep -Milliseconds 400
    [void][YbaWin32]::ClickInWindow($window.Handle, [int]$Target.X, [int]$Target.Y)
    Start-Sleep -Seconds 2
    [YbaWin32]::FocusConsole()
    return (Read-YesNo $Question $true)
}

function Read-Notches {
    param([int]$Default)
    do {
        $notches = Read-Number '     Quanti scatti di rotellina? (positivo = giù, negativo = su)' $Default -100
    } while ($notches -eq 0)
    return $notches
}

# Fa lo scroll su Roblox esattamente come lo farà l'app, poi torna su questa finestra.
# Prima fa il click iniziale: rispondendo qui Roblox perde il mouse, come quando si è appena aperto.
function Invoke-SetupScroll {
    param($Window, $Step, [int]$PauseMilliseconds, $InitialClick)
    Write-Host '     Provo adesso: guarda Roblox.'
    if ($InitialClick) {
        [YbaWin32]::FocusWindow($Window.Handle)
        Start-Sleep -Milliseconds 400
        [void][YbaWin32]::ClickInWindow($Window.Handle, [int]$InitialClick.X, [int]$InitialClick.Y)
        Start-Sleep -Milliseconds 500
    }
    Invoke-YbaScrollStep -Handle $Window.Handle -Step $Step -PauseMilliseconds $PauseMilliseconds
    Start-Sleep -Seconds 1
    [YbaWin32]::FocusConsole()
}

# Prova lo scroll su Roblox in 3 modi, finché uno funziona: rotellina, rotellina mandata direttamente
# a Roblox, trascinamento. Restituisce il modo (Method) e i suoi valori, da salvare nel passo.
function Read-ScrollStep {
    param($Target, [int]$PauseMilliseconds, $InitialClick)
    $step = [ordered]@{ Method = 'Wheel'; Amount = 5; X = $Target.X; Y = $Target.Y; EndX = 0; EndY = 0 }
    $window = Get-YbaTargetWindow -ProcessName $Target.ProcessName -WindowTitle $Target.WindowTitle
    if ($null -eq $window) {
        Write-Host '     Non trovo la finestra di Roblox per provarlo: lo salvo con la rotellina.' -ForegroundColor Yellow
        $step.Amount = Read-Notches $step.Amount
        return $step
    }
    Write-Host '     Provo lo scroll in 3 modi diversi, finché uno funziona.'
    $wheelModes = [ordered]@{
        Wheel   = 'Modo 1 di 3: rotellina del mouse'
        Message = 'Modo 2 di 3: rotellina mandata direttamente a Roblox'
    }
    foreach ($mode in $wheelModes.Keys) {
        Write-Host ('     ' + $wheelModes[$mode]) -ForegroundColor Cyan
        $step.Method = $mode
        while ($true) {
            $step.Amount = Read-Notches $step.Amount
            Invoke-SetupScroll $window $step $PauseMilliseconds $InitialClick
            if (-not (Read-YesNo '     La pagina di Roblox si è mossa?' $true)) { break }
            if (Read-YesNo '     Adesso si vede il punto da cliccare dopo?' $true) { return $step }
            # Torna su: verso giù si scrolla un po' di più (la pagina si ferma in cima); verso su si torna indietro uguale.
            $backAmount = if ($step.Amount -gt 0) { -($step.Amount + 20) } else { -$step.Amount }
            Invoke-SetupScroll $window ([ordered]@{ Method = $mode; Amount = $backAmount; X = $step.X; Y = $step.Y }) 0 $InitialClick
            Write-Host '     Ho riportato la pagina com''era: prova con un altro numero.'
        }
    }
    Write-Host '     Modo 3 di 3: trascinamento (come trascinare col mouse la pagina o la barra di scorrimento).' -ForegroundColor Cyan
    $step.Method = 'Drag'
    $step.Amount = 0
    while ($true) {
        $start = Read-ClickTarget -Label 'Inizio del trascinamento' -ExpectedProcess $Target.ProcessName -Hint 'il punto da cui trascinare (la pagina, oppure la barra di scorrimento)'
        $end = Read-ClickTarget -Label 'Fine del trascinamento' -ExpectedProcess $Target.ProcessName -Hint 'il punto dove finire (pagina: più in ALTO; barra di scorrimento: più in BASSO)'
        $step.X = $start.X
        $step.Y = $start.Y
        $step.EndX = $end.X
        $step.EndY = $end.Y
        Invoke-SetupScroll $window $step $PauseMilliseconds $InitialClick
        if (Read-YesNo '     La pagina di Roblox si è mossa?' $true) {
            if (Read-YesNo '     Adesso si vede il punto da cliccare dopo?' $true) { return $step }
            Invoke-SetupScroll $window ([ordered]@{ Method = 'Drag'; X = $step.EndX; Y = $step.EndY; EndX = $step.X; EndY = $step.Y }) 0 $InitialClick
            Write-Host '     Ho riportato la pagina com''era: prova con altri punti.'
        } elseif (-not (Read-YesNo '     Non si muove neanche così. Riprovo con altri punti?' $true)) {
            Write-Host '     Nessun modo ha funzionato: salvo la rotellina, ma probabilmente lo scroll non andrà.' -ForegroundColor Yellow
            $step.Method = 'Wheel'
            $step.Amount = 5
            $step.X = $Target.X
            $step.Y = $Target.Y
            return $step
        }
    }
}

function New-ClickEntry {
    param([string]$Name, $Target, [int]$DelayAfterSeconds, [string]$Type = 'Click')
    [ordered]@{
        Name              = $Name
        Type              = $Type
        ProcessName       = $Target.ProcessName
        WindowTitle       = $Target.WindowTitle
        X                 = $Target.X
        Y                 = $Target.Y
        DelayAfterSeconds = $DelayAfterSeconds
    }
}

function Hide-Webhook {
    param([string]$Url)
    if ($Url.Length -le 50) { return $Url }
    return $Url.Substring(0, 50) + '...'
}

Initialize-YbaEnvironment
try { $Host.UI.RawUI.WindowTitle = 'APP YBA - Setup' } catch { }
$config = Read-YbaConfig

Write-Host ''
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host '   APP YBA - Setup' -ForegroundColor Cyan
Write-Host '==============================================' -ForegroundColor Cyan
Write-Host 'Premi Invio per tenere il valore tra [parentesi].'

# 1. Webhook
Write-Step 1 'Webhook Discord'
if ($config.WebhookUrl) { Write-Host ('  Attuale: ' + (Hide-Webhook $config.WebhookUrl)) }
while ($true) {
    $url = Read-Answer "  Incolla l'URL del webhook (Invio = tieni quello attuale)"
    if ($url -eq '') {
        if ($config.WebhookUrl) { break }
        Write-Host '  Serve un webhook per mandare gli avvisi.' -ForegroundColor Yellow
        continue
    }
    if ($url -match $WebhookPattern) { $config.WebhookUrl = $url; break }
    Write-Host '  Non sembra un webhook Discord (https://discord.com/api/webhooks/...).' -ForegroundColor Yellow
}

# 2. Utente da pingare
Write-Step 2 'Utente Discord da pingare'
while ($true) {
    $userId = Read-Answer '  ID utente (vuoto = nessun ping)' $config.DiscordUserId
    if ($userId -eq '' -or $userId -match '^\d+$') { $config.DiscordUserId = $userId; break }
    Write-Host "  L'ID è fatto solo di numeri." -ForegroundColor Yellow
}
if (Read-YesNo '  Mando adesso un messaggio di prova su Discord?' $true) {
    [void](Send-YbaDiscordMessage -Config $config -Text 'Messaggio di prova da APP YBA: il webhook funziona!')
}

# 3. App con il bottone che apre Roblox
Write-Step 3 "L'app con il bottone che apre Roblox"
$recordLauncher = $true
if ($config.Launcher.LaunchButton) {
    Write-Host ("  Attuale: {0}.exe, bottone in X={1} Y={2}" -f $config.Launcher.LaunchButton.ProcessName, $config.Launcher.LaunchButton.X, $config.Launcher.LaunchButton.Y)
    $recordLauncher = Read-YesNo '  Vuoi registrarlo di nuovo?' $false
}
if ($recordLauncher) {
    Write-Host "  1) Apri l'app che usi per aprire Roblox."
    Write-Host '  2) Metti il mouse sopra il bottone che apre Roblox (NON cliccarlo).'
    Write-Host '  3) Premi F8: sentirai un beep. (Se non succede niente usa INVIO + 5 secondi.)'
    $target = Read-ClickTarget -Label 'Bottone che apre Roblox'
    $config.Launcher.ProcessName = $target.ProcessName
    $config.Launcher.LaunchButton = New-ClickEntry 'Bottone che apre Roblox' $target 0
    $config.Launcher.RunAsAdmin = [bool]$target.Elevated
    if ($target.Elevated) {
        Write-Host "  L'app è avviata come amministratore: Windows blocca i click dei programmi normali," -ForegroundColor Yellow
        Write-Host '  quindi Avvia.bat si riavvierà da solo come amministratore (Windows ti chiederà il permesso).' -ForegroundColor Yellow
    }
    if ($target.Path) {
        Write-Host "  Percorso dell'app: $($target.Path)"
    } else {
        Write-Host "  Non riesco a leggere il percorso dell'app: scrivilo tu." -ForegroundColor Yellow
    }
    $defaultPath = if ($target.Path) { $target.Path } else { $config.Launcher.Path }
    while ($true) {
        $path = (Read-Answer "  Percorso da aprire quando l'app è chiusa (.exe o collegamento)" $defaultPath).Trim('"')
        if ($path -and (Test-Path -LiteralPath $path)) { $config.Launcher.Path = $path; break }
        Write-Host '  File non trovato, controlla il percorso.' -ForegroundColor Yellow
    }
}

# 4. Come entrare in YBA
Write-Step 4 'Come entrare in "Your Bizarre Adventure"'
Write-Host "  1 = Il bottone dell'app fa già entrare in YBA (non serve altro)"
Write-Host "  2 = Apro YBA con il link roblox:// (placeId 2809202155, usa l'account loggato su Roblox)"
Write-Host '  3 = Registro dei click nella finestra di Roblox (es. icona di YBA e poi "Gioca")'
$currentChoice = switch ($config.Join.Method) { 'Link' { '2' } 'Clicks' { '3' } default { '1' } }
do { $choice = Read-Answer '  Scelta' $currentChoice } until (@('1', '2', '3') -contains $choice)
switch ($choice) {
    '1' { $config.Join.Method = 'None' }
    '2' {
        $config.Join.Method = 'Link'
        Write-Host '  (il PlaceId è il numero nell''indirizzo della pagina del gioco: roblox.com/games/NUMERO/...)'
        $config.Join.PlaceId = Read-Answer '  PlaceId del gioco' $config.Join.PlaceId
    }
    '3' {
        $recordJoin = $true
        if ($config.Join.Method -eq 'Clicks' -and @($config.Join.Clicks).Count -gt 0) {
            $recordJoin = Read-YesNo ("  Ci sono già {0} passi registrati. Vuoi registrarli di nuovo?" -f @($config.Join.Clicks).Count) $false
        }
        # Se si tengono i passi ma manca il click iniziale (config vecchia), lo si registra comunque.
        $recordInitial = $true
        if (-not $recordJoin -and $config.Join.InitialClick) {
            $recordInitial = Read-YesNo '  Vuoi registrare di nuovo il click iniziale su Roblox?' $false
        }
        $config.Join.Method = 'Clicks'
        $robloxProcess = $config.RobloxProcessNames[0]
        if ($recordInitial -or $recordJoin) {
            Write-Host '  Apri Roblox e lascialo come quando si è appena aperto (nella home, in cima: non scrollare).'
            Write-Host '  Registro i passi uno alla volta e li provo subito su Roblox, così vedi se funzionano.'
            Write-Host '  Dopo ogni prova torna su questa finestra nera per rispondere.'
        }
        if ($recordInitial) {
            Write-Host '  Prima di tutto un click su Roblox appena si apre: senza, Roblox non "prende" il mouse.'
            while ($true) {
                $target = Read-ClickTarget -Label 'CLICK INIZIALE' -ExpectedProcess $robloxProcess -Hint 'un punto VUOTO di Roblox che non apre niente, tipo uno spazio vuoto in alto'
                if (Test-RecordedClick $target '     Roblox è rimasto com''era (il click non ha aperto niente)?') { break }
                Write-Host '     Torna alla home di Roblox e scegli un punto più vuoto.' -ForegroundColor Yellow
            }
            $config.Join.InitialClick = New-ClickEntry 'Click iniziale su Roblox' $target 0
        }
        if ($recordJoin) {
            $clicks = @()
            $number = 1
            $withScroll = Read-YesNo '  Prima dei click serve scrollare?' $true
            if ($withScroll) {
                $target = Read-ClickTarget -Label "Passo ${number}: SCROLL" -ExpectedProcess $robloxProcess -Hint 'la zona da scrollare'
                $entry = New-ClickEntry 'Scroll in Roblox' $target 3 -Type 'Scroll'
                $scroll = Read-ScrollStep $target $config.Join.ScrollPauseMilliseconds $config.Join.InitialClick
                foreach ($key in $scroll.Keys) { $entry[$key] = $scroll[$key] }
                $clicks += , $entry
                $number++
            }
            $countPrompt = if ($withScroll) { '  Quanti click in Roblox dopo lo scroll?' } else { '  Quanti click in Roblox?' }
            $count = Read-Number $countPrompt 2 1
            for ($i = 1; $i -le $count; $i++) {
                while ($true) {
                    $target = Read-ClickTarget -Label "Passo ${number}: CLICK $i di $count" -ExpectedProcess $robloxProcess
                    if (Test-RecordedClick $target) { break }
                    Write-Host '     Riporta Roblox alla schermata giusta e registra di nuovo questo click.' -ForegroundColor Yellow
                }
                $clicks += , (New-ClickEntry "Click $i in Roblox" $target 3)
                $number++
            }
            $delay = Read-Number '  Secondi di attesa dopo ogni passo' 3
            foreach ($click in $clicks) { $click.DelayAfterSeconds = $delay }
            $config.Join.Clicks = $clicks
        }
        Write-Host '  Prima del 1° passo Roblox deve aver caricato tutta la home (sennò lo scroll si ferma prima).'
        $config.Join.DelayBeforeSeconds = Read-Number '  Secondi da aspettare dopo che Roblox si apre (consigliati almeno 20)' $config.Join.DelayBeforeSeconds
    }
}

# 5. Click finali sull'app
Write-Step 5 "I click finali sull'app (dopo essere entrati in YBA)"
$recordFinal = $true
if (@($config.FinalClicks.Clicks).Count -gt 0) {
    $recordFinal = Read-YesNo ("  Ci sono già {0} click registrati. Vuoi registrarli di nuovo?" -f @($config.FinalClicks.Clicks).Count) $false
}
if ($recordFinal) {
    $count = Read-Number '  Quanti click?' 2 1
    Write-Host "  Prepara l'app in modo che si vedano i bottoni da premere"
    Write-Host '  (se compaiono solo quando Roblox è aperto, apri prima Roblox).'
    $clicks = @()
    for ($i = 1; $i -le $count; $i++) {
        $target = Read-ClickTarget -Label "Click finale $i di $count" -ExpectedProcess $config.Launcher.ProcessName
        $clicks += , (New-ClickEntry "Click finale $i" $target 2)
    }
    $config.FinalClicks.DelayBeforeSeconds = Read-Number '  Secondi da aspettare dopo che Roblox entra nel gioco, prima del 1° click' $config.FinalClicks.DelayBeforeSeconds
    $between = Read-Number "  Secondi tra un click e l'altro" 2
    foreach ($click in $clicks) { $click.DelayAfterSeconds = $between }
    $config.FinalClicks.Clicks = $clicks
}

Save-YbaConfig $config
Write-Host ''
Write-Host 'Fatto! Configurazione salvata in config.json.' -ForegroundColor Green
Write-Host 'Ora avvia Avvia.bat per far partire il controllo di Roblox.' -ForegroundColor Green
