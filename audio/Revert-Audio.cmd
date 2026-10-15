@echo off
rem Launcher: asks for administrator rights once (UAC "Yes"), then reverts the audio fix.
rem The target is resolved from this file's own folder (%~dp0) first, so the repository
rem copy works; D:\ai\audio is the deployed fallback.
setlocal
set "PS1=%~dp0Revert-Audio.ps1"
if not exist "%PS1%" if exist "D:\ai\audio\Revert-Audio.ps1" set "PS1=D:\ai\audio\Revert-Audio.ps1"
if not exist "%PS1%" (
  echo [ERROR] Revert-Audio.ps1 not found next to this file or in D:\ai\audio
  echo         Deploy the repository to D:\ai first ^(see README, section 4^).
  exit /b 2
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File','%PS1%')"
exit /b 0
