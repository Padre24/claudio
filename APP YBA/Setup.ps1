#Requires -Version 5.1
# APP YBA - Setup guidato: crea config.json (webhook, app che apre Roblox, click da fare).

. (Join-Path $PSScriptRoot 'Common.ps1')

$VK_F8 = 0x77
$VK_F9 = 0x78
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

# 'Now' = F8 premuto, 'Countdown' = INVIO premuto in questa finestra, 'Finish' = F9 o F in questa finestra.
# F8 a volte non arriva (portatili senza Fn, app avviate come amministratore): INVIO funziona sempre.
function Wait-Trigger {
    param([switch]$AllowFinish)
    Wait-KeyRelease $VK_F8
    Wait-KeyRelease $VK_F9
    while ([YbaWin32]::ReadConsoleKey() -ne 0) { }
    while ($true) {
        if ([YbaWin32]::IsKeyDown($VK_F8)) { Wait-KeyRelease $VK_F8; return 'Now' }
        if ($AllowFinish -and [YbaWin32]::IsKeyDown($VK_F9)) { Wait-KeyRelease $VK_F9; return 'Finish' }
        $consoleKey = [YbaWin32]::ReadConsoleKey()
        if ($consoleKey -eq [int][ConsoleKey]::Enter) { return 'Countdown' }
        if ($AllowFinish -and $consoleKey -eq [int][ConsoleKey]::F) { return 'Finish' }
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

# Registra la posizione del mouse quando l'utente preme F8 o dopo il conto alla rovescia (F9 = fine, se permesso).
function Read-ClickTarget {
    param([string]$Label, [string]$ExpectedProcess = '', [switch]$AllowFinish)
    while ($true) {
        Write-Host ''
        Write-Host "  >> $Label" -ForegroundColor White
        Write-Host '     Metti il mouse SOPRA il punto da cliccare (senza cliccare) e premi F8 (sui portatili: Fn+F8).'
        Write-Host '     Se F8 non funziona: premi INVIO qui, poi hai 5 secondi per mettere il mouse sopra il punto.'
        if ($AllowFinish) { Write-Host '     Hai finito? Premi F9 (oppure F qui).' }
        $trigger = Wait-Trigger -AllowFinish:$AllowFinish
        if ($trigger -eq 'Finish') {
            [YbaWin32]::FocusConsole()
            return $null
        }
        if ($trigger -eq 'Countdown') {
            Write-Host '     Metti il mouse sopra il punto (deve essere visibile, non coperto da questa finestra): ' -NoNewline
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

function New-ClickEntry {
    param([string]$Name, $Target, [int]$DelayAfterSeconds)
    [ordered]@{
        Name              = $Name
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
        $config.Join.PlaceId = Read-Answer '  PlaceId del gioco' $config.Join.PlaceId
    }
    '3' {
        $recordJoin = $true
        if ($config.Join.Method -eq 'Clicks' -and @($config.Join.Clicks).Count -gt 0) {
            $recordJoin = Read-YesNo ("  Ci sono già {0} click registrati. Vuoi registrarli di nuovo?" -f @($config.Join.Clicks).Count) $false
        }
        $config.Join.Method = 'Clicks'
        if ($recordJoin) {
            Write-Host '  Apri Roblox e lascialo nella schermata in cui si apre di solito (es. la home).'
            $robloxProcess = $config.RobloxProcessNames[0]
            $clicks = @()
            while ($true) {
                $number = $clicks.Count + 1
                $target = Read-ClickTarget -Label "Click $number in Roblox" -ExpectedProcess $robloxProcess -AllowFinish:($number -gt 1)
                if ($null -eq $target) { break }
                $clicks += , (New-ClickEntry "Click $number in Roblox" $target 3)
            }
            $config.Join.DelayBeforeSeconds = Read-Number '  Secondi da aspettare dopo che Roblox si apre, prima del 1° click' $config.Join.DelayBeforeSeconds
            $delay = Read-Number '  Secondi di attesa dopo ogni click' 3
            foreach ($click in $clicks) { $click.DelayAfterSeconds = $delay }
            $config.Join.Clicks = $clicks
        }
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
