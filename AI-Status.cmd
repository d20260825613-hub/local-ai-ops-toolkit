@echo off
echo === watchdog state (D:\ai\state.json) ===
type "D:\ai\state.json"
echo.
echo === watchdog process ===
powershell.exe -NoLogo -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -like '*-File*LocalAI-Watchdog.ps1*' -and $_.CommandLine -notlike '*Where-Object*' } | Select-Object ProcessId, CreationDate | Format-Table -AutoSize"
echo === model service ===
powershell.exe -NoLogo -NoProfile -Command "Get-Process llama-server -ErrorAction SilentlyContinue | Select-Object Id, @{n='RAM_MB';e={[int]($_.WorkingSet64/1MB)}} | Format-Table -AutoSize"
echo === last log lines ===
powershell.exe -NoLogo -NoProfile -Command "Get-ChildItem 'D:\ai\logs\watchdog-*.log' | Sort-Object LastWriteTime | Select-Object -Last 1 | Get-Content -Tail 12"
pause
