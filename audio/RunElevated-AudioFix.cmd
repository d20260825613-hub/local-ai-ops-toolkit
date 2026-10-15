@echo off
rem Run the audio repair with full output captured to repair-log.txt.
rem This file is launched by the scheduled task DSH-AudioRepair (highest privileges).
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "D:\ai\audio\Repair-WindowsAudio.ps1" > "D:\ai\audio\repair-log.txt" 2>&1
exit /b %ERRORLEVEL%
