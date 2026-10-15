@echo off
rem Run the audio repair with full output captured to repair-log.txt.
rem This file is launched by the scheduled task DSH-AudioRepair (highest privileges).
rem
rem The log is produced by Fix-Audio-AllInOne.ps1 / Repair-WindowsAudio.ps1 through
rem Add-Content -Encoding UTF8. Do NOT redirect with ">" here: cmd.exe captures a
rem program's output as UTF-16LE, and appending that to the UTF-8 log is what left
rem repair-log.txt 47% NUL bytes. Delegate to PowerShell instead, and locate the
rem script from this file's own folder (%~dp0) so the repository copy works as well.
setlocal
set "PS1=%~dp0Fix-Audio-AllInOne.ps1"
if not exist "%PS1%" if exist "D:\ai\audio\Fix-Audio-AllInOne.ps1" set "PS1=D:\ai\audio\Fix-Audio-AllInOne.ps1"
if not exist "%PS1%" (
  echo [ERROR] Fix-Audio-AllInOne.ps1 not found next to this file or in D:\ai\audio
  echo         Run this launcher from the repository's audio folder, or deploy the
  echo         repository to D:\ai first ^(see README, section 4^).
  exit /b 2
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
exit /b %ERRORLEVEL%
