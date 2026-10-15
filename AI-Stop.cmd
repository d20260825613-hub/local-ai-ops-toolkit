@echo off
rem Stop the local model service (frees the 4 GB VRAM). The watchdog will bring
rem it back on its next cycle unless a game is running; use it together with
rem "schtasks /end /tn LocalAI-Autostart" to stop everything for good.
rem
rem Port-scoped on purpose: this stops ONLY the llama-server serving the main model
rem port (8080 by default, or whatever config.json says), never the Sydney service
rem on its own port - the old "taskkill /IM llama-server.exe" killed both, and any
rem hand-started llama-server as well. The selection logic lives in
rem tools\portfilter.ps1 so the self-test can exercise it with fake data.
setlocal
set "PF=%~dp0tools\portfilter.ps1"
if not exist "%PF%" if exist "D:\ai\tools\portfilter.ps1" set "PF=D:\ai\tools\portfilter.ps1"
if not exist "%PF%" (
  echo [ERROR] tools\portfilter.ps1 not found next to this file or in D:\ai\tools
  echo         Deploy the repository to D:\ai first ^(see README, section 4^).
  exit /b 2
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PF%" -Stop
echo.
echo Model service (main port only) stopped. Sydney on its own port was left alone.
pause
