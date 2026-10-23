# APP YBA - funzioni condivise da Setup.ps1 e RobloxWatchdog.ps1.
# Compatibile con Windows PowerShell 5.1 (quello già installato su Windows).

$ErrorActionPreference = 'Stop'

$Script:YbaConfigPath = Join-Path $PSScriptRoot 'config.json'
$Script:YbaLogPath    = Join-Path $PSScriptRoot 'watchdog.log'

# In Windows PowerShell 5.1 senza questo ConvertTo-Json può scrivere gli array come {"value":[...],"Count":n}.
try { Remove-TypeData -TypeName System.Array -ErrorAction SilentlyContinue } catch { }

if (-not ('YbaWin32' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public class YbaCursorTarget
{
    public IntPtr Window;
    public int ProcessId;
    public int OffsetX;
    public int OffsetY;
}

public static class YbaWin32
{
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    private const uint GA_ROOT = 2;
    private const uint GW_OWNER = 4;
    private const int SW_RESTORE = 9;
    private const byte VK_MENU = 0x12;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;

    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool IsHungAppWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hWnd, uint cmd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr hWnd, uint flags);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int cmd);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] private static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extraInfo);
    [DllImport("user32.dll")] private static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extraInfo);
    [DllImport("kernel32.dll")] private static extern IntPtr GetConsoleWindow();

    // Finestre principali (visibili e senza "owner") dei processi indicati.
    public static IntPtr[] GetTopWindows(int[] processIds)
    {
        List<uint> ids = new List<uint>();
        foreach (int id in processIds) ids.Add((uint)id);
        List<IntPtr> found = new List<IntPtr>();
        EnumWindows(delegate (IntPtr hWnd, IntPtr lParam)
        {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (ids.Contains(pid) && IsWindowVisible(hWnd) && GetWindow(hWnd, GW_OWNER) == IntPtr.Zero)
                found.Add(hWnd);
            return true;
        }, IntPtr.Zero);
        return found.ToArray();
    }

    public static string GetTitle(IntPtr hWnd)
    {
        StringBuilder sb = new StringBuilder(GetWindowTextLength(hWnd) + 1);
        GetWindowText(hWnd, sb, sb.Capacity);
        return sb.ToString();
    }

    public static string GetClass(IntPtr hWnd)
    {
        StringBuilder sb = new StringBuilder(256);
        GetClassName(hWnd, sb, sb.Capacity);
        return sb.ToString();
    }

    public static int GetProcessId(IntPtr hWnd)
    {
        uint pid;
        GetWindowThreadProcessId(hWnd, out pid);
        return (int)pid;
    }

    public static bool IsKeyDown(int vKey)
    {
        return (GetAsyncKeyState(vKey) & 0x8000) != 0;
    }

    // Finestra sotto il mouse e posizione del mouse relativa al suo angolo in alto a sinistra.
    public static YbaCursorTarget GetCursorTarget()
    {
        POINT p;
        if (!GetCursorPos(out p)) return null;
        IntPtr hWnd = WindowFromPoint(p);
        if (hWnd == IntPtr.Zero) return null;
        IntPtr root = GetAncestor(hWnd, GA_ROOT);
        if (root == IntPtr.Zero) root = hWnd;
        RECT r;
        GetWindowRect(root, out r);
        YbaCursorTarget t = new YbaCursorTarget();
        t.Window = root;
        t.ProcessId = GetProcessId(root);
        t.OffsetX = p.X - r.Left;
        t.OffsetY = p.Y - r.Top;
        return t;
    }

    public static void FocusWindow(IntPtr hWnd)
    {
        if (IsIconic(hWnd)) ShowWindow(hWnd, SW_RESTORE);
        if (GetForegroundWindow() == hWnd) return;
        // Premere e rilasciare ALT permette a SetForegroundWindow di portare davvero la finestra davanti.
        keybd_event(VK_MENU, 0, 0, UIntPtr.Zero);
        keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        SetForegroundWindow(hWnd);
        BringWindowToTop(hWnd);
    }

    public static void FocusConsole()
    {
        IntPtr hWnd = GetConsoleWindow();
        if (hWnd != IntPtr.Zero) FocusWindow(hWnd);
    }

    public static bool ClickInWindow(IntPtr hWnd, int offsetX, int offsetY)
    {
        RECT r;
        if (!GetWindowRect(hWnd, out r)) return false;
        int x = r.Left + offsetX;
        int y = r.Top + offsetY;
        // Piccolo movimento prima del click: alcune app (e Roblox) registrano il click solo dopo l'hover.
        SetCursorPos(x, y);
        Thread.Sleep(60);
        SetCursorPos(x + 1, y);
        Thread.Sleep(40);
        SetCursorPos(x, y);
        Thread.Sleep(60);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
        Thread.Sleep(60);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
        return true;
    }
}
'@
}

function Initialize-YbaEnvironment {
    # Discord accetta solo TLS 1.2+; su alcuni Windows PowerShell 5.1 non è attivo di default.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    # Coordinate in pixel reali anche con lo zoom di Windows (125%, 150%...).
    try { [void][YbaWin32]::SetProcessDPIAware() } catch { }
}

function Write-YbaLog {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Gray)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line -ForegroundColor $Color
    try { Add-Content -LiteralPath $Script:YbaLogPath -Value $line -Encoding UTF8 } catch { }
}

function Get-YbaDefaultConfig {
    [ordered]@{
        WebhookUrl                 = ''
        DiscordUserId              = '350886488235311126'
        Message                    = 'Roblox si è chiuso/crash'
        CheckIntervalSeconds       = 2
        RobloxProcessNames         = @('RobloxPlayerBeta')
        NoWindowGraceSeconds       = 10
        FreezeTimeoutSeconds       = 60
        RobloxStartTimeoutSeconds  = 10
        RobloxWindowTimeoutSeconds = 60
        Launcher                   = [ordered]@{
            Path                  = ''
            ProcessName           = ''
            StartupTimeoutSeconds = 30
            LoadDelaySeconds      = 3
            LaunchButton          = $null
        }
        Join                       = [ordered]@{
            Method             = 'None'
            PlaceId            = '2809202155'
            DelayBeforeSeconds = 10
            Clicks             = @()
        }
        FinalClicks                = [ordered]@{
            DelayBeforeSeconds = 30
            Clicks             = @()
        }
    }
}

# Oggetti letti da JSON -> hashtable ordinate (più facili da modificare e salvare).
function ConvertTo-YbaPlain {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $table = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) { $table[$property.Name] = ConvertTo-YbaPlain $property.Value }
        return $table
    }
    if ($Value -is [System.Array]) { return , @($Value | ForEach-Object { ConvertTo-YbaPlain $_ }) }
    return $Value
}

function Merge-YbaConfig {
    param($Default, $Loaded)
    $result = [ordered]@{}
    foreach ($key in $Default.Keys) {
        $defaultValue = $Default[$key]
        if ($null -ne $Loaded -and $Loaded.PSObject.Properties.Name -contains $key) {
            if ($defaultValue -is [System.Collections.IDictionary]) {
                $result[$key] = Merge-YbaConfig $defaultValue $Loaded.$key
            } else {
                $result[$key] = ConvertTo-YbaPlain $Loaded.$key
            }
        } else {
            $result[$key] = $defaultValue
        }
    }
    return $result
}

function Test-YbaConfigExists {
    Test-Path -LiteralPath $Script:YbaConfigPath
}

function Read-YbaConfig {
    $config = Get-YbaDefaultConfig
    if (Test-YbaConfigExists) {
        $loaded = Get-Content -LiteralPath $Script:YbaConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $config = Merge-YbaConfig $config $loaded
    }
    $config.RobloxProcessNames = @($config.RobloxProcessNames | ForEach-Object { ([string]$_).Trim() -replace '\.exe$', '' } | Where-Object { $_ })
    return $config
}

function Save-YbaConfig {
    param($Config)
    $json = ConvertTo-Json -InputObject $Config -Depth 8
    Set-Content -LiteralPath $Script:YbaConfigPath -Value $json -Encoding UTF8
}

# Finestre principali visibili dei processi indicati, con titolo e classe.
function Get-YbaWindows {
    param([int[]]$ProcessIds)
    if (-not $ProcessIds -or $ProcessIds.Count -eq 0) { return }
    foreach ($handle in [YbaWin32]::GetTopWindows($ProcessIds)) {
        [pscustomobject]@{
            Handle    = $handle
            Title     = [YbaWin32]::GetTitle($handle)
            ClassName = [YbaWin32]::GetClass($handle)
            ProcessId = [YbaWin32]::GetProcessId($handle)
        }
    }
}

# Trova la finestra su cui cliccare: prima quella col titolo registrato nel Setup, poi la finestra principale.
function Get-YbaTargetWindow {
    param([string]$ProcessName, [string]$WindowTitle)
    if (-not $ProcessName) { return $null }
    $processes = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) { return $null }
    $windows = @(Get-YbaWindows -ProcessIds ($processes | ForEach-Object { $_.Id }))
    if ($windows.Count -eq 0) { return $null }
    if ($WindowTitle) {
        $match = @($windows | Where-Object { $_.Title -eq $WindowTitle })
        if ($match.Count -gt 0) { return $match[0] }
    }
    $mainHandles = @($processes | ForEach-Object { $_.MainWindowHandle } | Where-Object { $_ -ne [IntPtr]::Zero })
    $match = @($windows | Where-Object { $mainHandles -contains $_.Handle })
    if ($match.Count -gt 0) { return $match[0] }
    $match = @($windows | Where-Object { $_.Title -and $_.ClassName -ne '#32770' })
    if ($match.Count -gt 0) { return $match[0] }
    return $windows[0]
}

function Send-YbaDiscordMessage {
    param($Config, [string]$Text)
    if ([string]::IsNullOrWhiteSpace($Config.WebhookUrl)) {
        Write-YbaLog 'Webhook Discord non impostato: esegui Setup.bat.' Yellow
        return $false
    }
    $userId = ([string]$Config.DiscordUserId).Trim()
    $content = $Text
    $mentions = [ordered]@{ parse = @() }
    if ($userId -match '^\d+$') {
        $content = "<@$userId> $Text"
        $mentions['users'] = @($userId)
    }
    $payload = [ordered]@{ content = $content; allowed_mentions = $mentions }
    $body = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $payload -Depth 5 -Compress))
    try {
        Invoke-RestMethod -Uri $Config.WebhookUrl -Method Post -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 15 -UseBasicParsing | Out-Null
        Write-YbaLog 'Messaggio inviato su Discord.' Green
        return $true
    } catch {
        Write-YbaLog ('Invio del messaggio Discord fallito: ' + $_.Exception.Message) Red
        return $false
    }
}
