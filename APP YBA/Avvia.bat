@echo off
title APP YBA
cd /d "%~dp0"
if not exist "config.json" (
    echo Configurazione mancante: avvio prima il Setup...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1"
)
if exist "config.json" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0RobloxWatchdog.ps1"
)
echo.
pause
