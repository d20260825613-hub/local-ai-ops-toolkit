@echo off
rem Stop the local model service (frees the 4 GB VRAM). The watchdog will bring
rem it back on its next cycle unless a game is running; use it together with
rem "schtasks /end /tn LocalAI-Autostart" to stop everything for good.
taskkill /IM llama-server.exe /F >nul 2>&1
echo Model service stopped.
powershell.exe -NoLogo -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count"
pause
