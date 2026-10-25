# APP YBA - lettura delle scritte sullo schermo con il riconoscimento del testo di Windows 10/11 (OCR).
# Caricato da Common.ps1.

$Script:YbaOcrEngine = $null
$Script:YbaOcrAwait = $null

function Initialize-YbaOcr {
    if ($Script:YbaOcrEngine) { return $true }
    try {
        Add-Type -AssemblyName System.Drawing
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
        $null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
        $null = [Windows.Foundation.IAsyncOperation`1, Windows.Foundation, ContentType = WindowsRuntime]
        $null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Foundation, ContentType = WindowsRuntime]
        $null = [Windows.Storage.Streams.RandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
        # Le funzioni di Windows per l'OCR sono asincrone: questo metodo permette di aspettarne il risultato.
        $Script:YbaOcrAwait = [System.WindowsRuntimeSystemExtensions].GetMember('GetAwaiter') |
            Where-Object { $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } |
            Select-Object -First 1
        $Script:YbaOcrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    } catch {
        Write-YbaLog ('Il riconoscimento del testo di Windows non funziona: ' + $_.Exception.Message) Red
        return $false
    }
    if ($null -eq $Script:YbaOcrEngine) {
        Write-YbaLog 'Il riconoscimento del testo di Windows non è installato: aggiungi la lingua Inglese in Impostazioni > Ora e lingua > Lingua.' Red
        return $false
    }
    return $true
}

function Invoke-YbaOcrAwait {
    param($Operation, [type]$ResultType)
    $Script:YbaOcrAwait.MakeGenericMethod($ResultType).Invoke($null, @($Operation)).GetResult()
}

# true se l'immagine è tutta di un colore (-BlackOnly: tutta nera), guardando una griglia di 15x15 punti.
function Test-YbaBlankBitmap {
    param([System.Drawing.Bitmap]$Bitmap, [switch]$BlackOnly)
    $first = $Bitmap.GetPixel([int]($Bitmap.Width / 16), [int]($Bitmap.Height / 16))
    for ($i = 1; $i -le 15; $i++) {
        for ($j = 1; $j -le 15; $j++) {
            $pixel = $Bitmap.GetPixel([int]($Bitmap.Width * $i / 16), [int]($Bitmap.Height * $j / 16))
            if ($BlackOnly) {
                if (($pixel.R + $pixel.G + $pixel.B) -gt 30) { return $false }
            } elseif ([Math]::Abs($pixel.R - $first.R) + [Math]::Abs($pixel.G - $first.G) + [Math]::Abs($pixel.B - $first.B) -gt 30) {
                return $false
            }
        }
    }
    return $true
}

# Foto della finestra: prima PrintWindow (funziona anche se la finestra è coperta);
# se viene tutta di un colore (succede con i giochi) si fotografa quella parte dello schermo.
# $null se anche così è tutto nero.
function Get-YbaWindowBitmap {
    param([IntPtr]$Handle)
    $bounds = [YbaWin32]::GetWindowBounds($Handle)
    if ($null -eq $bounds -or $bounds[2] -le 0 -or $bounds[3] -le 0) { return $null }
    $bitmap = [System.Drawing.Bitmap]::new($bounds[2], $bounds[3])
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $hdc = $graphics.GetHdc()
        $printed = [YbaWin32]::PrintWindow($Handle, $hdc, 2)
        $graphics.ReleaseHdc($hdc)
        if (-not $printed -or (Test-YbaBlankBitmap $bitmap)) {
            $graphics.CopyFromScreen($bounds[0], $bounds[1], 0, 0, $bitmap.Size)
        }
    } finally {
        $graphics.Dispose()
    }
    if (Test-YbaBlankBitmap $bitmap -BlackOnly) {
        $bitmap.Dispose()
        return $null
    }
    return $bitmap
}

$Script:YbaOcrUseFile = $false

# Immagine -> SoftwareBitmap per l'OCR. Di solito in memoria: lo schermo si legge anche ogni secondo e
# salvarlo ogni volta su disco lo consumerebbe. Se in memoria non funziona, si passa a un file temporaneo.
function ConvertTo-YbaSoftwareBitmap {
    param([System.Drawing.Bitmap]$Bitmap)
    if (-not $Script:YbaOcrUseFile) {
        $memory = New-Object System.IO.MemoryStream
        try {
            $Bitmap.Save($memory, [System.Drawing.Imaging.ImageFormat]::Bmp)
            $memory.Position = 0
            $stream = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($memory)
            $decoder = Invoke-YbaOcrAwait ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
            return Invoke-YbaOcrAwait ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        } catch {
            Write-YbaLog ('Lettura dello schermo in memoria non riuscita, uso un file temporaneo: ' + $_.Exception.Message) Yellow
            $Script:YbaOcrUseFile = $true
        } finally {
            $memory.Dispose()
        }
    }
    $path = Join-Path $env:TEMP ('appyba-ocr-{0}.png' -f [guid]::NewGuid().ToString('N'))
    $stream = $null
    try {
        $Bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $file = Invoke-YbaOcrAwait ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
        $stream = Invoke-YbaOcrAwait ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
        $decoder = Invoke-YbaOcrAwait ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        return Invoke-YbaOcrAwait ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    } finally {
        if ($stream) { try { $stream.Dispose() } catch { } }
        Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
    }
}

# Scritte lette nella finestra, riga per riga, con la posizione di ogni parola (in pixel rispetto alla finestra).
# $null = lo schermo non si riesce a leggere (OCR non disponibile o schermo nero).
# -Fast: per le letture continue (ogni secondo) l'immagine si ingrandisce solo se la finestra è piccola:
# le scritte cercate lì (caricamento, disconnessione) sono grandi, e così si usa meno CPU.
function Get-YbaScreenLines {
    param([IntPtr]$Handle, [switch]$Fast)
    if (-not (Initialize-YbaOcr)) { return $null }
    $bitmap = Get-YbaWindowBitmap $Handle
    if ($null -eq $bitmap) { return $null }
    # I nomi dei giochi nella home sono scritti piccoli: ingrandire l'immagine aiuta il riconoscimento.
    $maxWidthToScale = if ($Fast) { 1279 } else { 2000 }
    $scale = if ($bitmap.Width -le $maxWidthToScale) { 2 } else { 1 }
    $software = $null
    try {
        if ($scale -ne 1) {
            $big = [System.Drawing.Bitmap]::new($bitmap, $bitmap.Width * $scale, $bitmap.Height * $scale)
            try { $software = ConvertTo-YbaSoftwareBitmap $big } finally { $big.Dispose() }
        } else {
            $software = ConvertTo-YbaSoftwareBitmap $bitmap
        }
        $result = Invoke-YbaOcrAwait ($Script:YbaOcrEngine.RecognizeAsync($software)) ([Windows.Media.Ocr.OcrResult])
    } catch {
        Write-YbaLog ('Lettura dello schermo fallita: ' + $_.Exception.Message) Red
        return $null
    } finally {
        if ($software) { try { $software.Dispose() } catch { } }
        $bitmap.Dispose()
    }
    $lines = foreach ($line in $result.Lines) {
        [pscustomobject]@{
            Text  = $line.Text
            Words = @(foreach ($word in $line.Words) {
                    $rect = $word.BoundingRect
                    [pscustomobject]@{
                        Text   = $word.Text
                        X      = [int]($rect.X / $scale)
                        Y      = [int]($rect.Y / $scale)
                        Width  = [int]($rect.Width / $scale)
                        Height = [int]($rect.Height / $scale)
                    }
                })
        }
    }
    return , @($lines)
}
