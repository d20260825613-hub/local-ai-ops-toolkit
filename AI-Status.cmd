@echo off
rem Show the watchdog state. Paths are resolved from this file's own folder (%~dp0)
rem first, so running it from the repository works; D:\ai is the deployed fallback.
setlocal
set "ROOT=%~dp0"
if not exist "%ROOT%state.json" if exist "D:\ai\state.json" set "ROOT=D:\ai\"

echo === watchdog state (%ROOT%state.json) ===
if exist "%ROOT%state.json" (
  type "%ROOT%state.json"
) else (
  echo (not found - the watchdog has not run yet)
)
echo.
echo === watchdog process ===
powershell.exe -NoLogo -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -like '*-File*LocalAI-Watchdog.ps1*' -and $_.CommandLine -notlike '*Where-Object*' } | Select-Object ProcessId, CreationDate | Format-Table -AutoSize"
echo === model service (with the port it was started on) ===
powershell.exe -NoLogo -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='llama-server.exe'\" -ErrorAction SilentlyContinue | ForEach-Object { $port = '?'; if ($_.CommandLine -match '(?i)--port[ =]+([0-9]+)') { $port = $Matches[1] }; [pscustomobject]@{ Id = $_.ProcessId; Port = $port; RAM_MB = [int]($_.WorkingSetSize/1MB) } } | Format-Table -AutoSize"
echo === last log lines ===
set "LOGDIR=%ROOT%logs"
if not exist "%LOGDIR%" if exist "D:\ai\logs" set "LOGDIR=D:\ai\logs"
powershell.exe -NoLogo -NoProfile -Command "Get-ChildItem -LiteralPath '%LOGDIR%' -Filter 'watchdog-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1 | Get-Content -Tail 12"
pause
