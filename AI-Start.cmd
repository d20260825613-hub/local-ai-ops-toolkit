@echo off
rem Force-start the local AI stack now, even if a game is running.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "D:\ai\LocalAI-Watchdog.ps1" -Once -Force
echo.
echo Done. Server: http://127.0.0.1:8080/v1
pause
