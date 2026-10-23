# APP YBA

Watchdog per Roblox su Windows: se Roblox si chiude o crasha avvisa su Discord, chiude il processo
rimasto appeso, lo riapre dalla tua app, entra in Your Bizarre Adventure e fa i click finali.

L'app è nella cartella [`APP YBA`](APP%20YBA/): leggi [`APP YBA/LEGGIMI.md`](APP%20YBA/LEGGIMI.md).

## Installazione in `C:\Users\vitom\Desktop\APP YBA`

Apri **PowerShell** (tasto Start → scrivi `powershell` → Invio) e incolla:

```powershell
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'; $z = "$env:TEMP\yba.zip"; $t = "$env:TEMP\yba"; $d = 'C:\Users\vitom\Desktop\APP YBA'; Invoke-WebRequest 'https://github.com/Padre24/claudio/archive/refs/heads/claude/roblox-monitoring-app-46gh7g.zip' -OutFile $z -UseBasicParsing; Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue; Expand-Archive $z $t; New-Item -ItemType Directory $d -Force | Out-Null; Copy-Item (Join-Path (Get-ChildItem $t -Directory)[0].FullName 'APP YBA\*') $d -Recurse -Force; explorer $d
```

Si apre la cartella: fai doppio click su `Setup.bat`, poi su `Avvia.bat`.
Se rifai l'installazione per aggiornare, il tuo `config.json` resta com'è.
