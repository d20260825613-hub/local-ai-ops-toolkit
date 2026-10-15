@echo off
rem Force-start the local AI stack now, even if a game is running.
rem Locate the watchdog from this file's own folder (%~dp0) first, so running it from
rem the repository works; the deployed layout in D:\ai is the fallback.
setlocal
set "WD=%~dp0LocalAI-Watchdog.ps1"
if not exist "%WD%" if exist "D:\ai\LocalAI-Watchdog.ps1" set "WD=D:\ai\LocalAI-Watchdog.ps1"
if not exist "%WD%" (
  echo [ERROR] LocalAI-Watchdog.ps1 not found next to this file or in D:\ai
  echo         Deploy the repository to D:\ai first ^(see README, section 4^).
  exit /b 2
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%WD%" -Once -Force
if errorlevel 1 (
  echo.
  echo [FAILED] the watchdog exited with errorlevel %ERRORLEVEL%.
  echo          Read the last lines of "%~dp0logs\watchdog-*.log" ^(or D:\ai\logs^).
  pause
  exit /b %ERRORLEVEL%
)
echo.
echo Done. Server: http://127.0.0.1:8080/v1
pause
