# Install-Startup.ps1
# Registers the local-AI watchdog so it runs automatically at every logon.
# Preferred: a Scheduled Task (hidden, restart on failure).
# Fallback : a HKCU Run entry that calls the hidden VBS wrapper (no admin needed).

$ErrorActionPreference = 'Continue'
$Root     = 'D:\ai'
$Watchdog = Join-Path $Root 'LocalAI-Watchdog.ps1'
$Vbs      = Join-Path $Root 'run-watchdog-hidden.vbs'
$TaskName = 'LocalAI-Autostart'
$Ps       = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Log($m) { Write-Host $m }

if (-not (Test-Path -LiteralPath $Watchdog)) { Log "ERROR: $Watchdog not found"; exit 1 }

# 1) hidden VBS wrapper (used by the Run-key fallback and by manual start)
$vbsBody = @"
' Auto-generated: start the local AI watchdog with no visible window.
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""$Watchdog""", 0, False
"@
Set-Content -LiteralPath $Vbs -Value $vbsBody -Encoding ASCII
Log "wrapper written: $Vbs"

# 2) try the scheduled task
$taskOk = $false
try {
  $action = New-ScheduledTaskAction -Execute $Ps `
    -Argument "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Watchdog`""
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
  $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
  $taskOk = $true
  Log "scheduled task registered: $TaskName"
} catch {
  Log "scheduled task registration failed: $($_.Exception.Message)"
}

# 3) Run-key fallback
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if ($taskOk) {
  Remove-ItemProperty -Path $runKey -Name 'LocalAI-Watchdog' -ErrorAction SilentlyContinue
  Log 'run-key entry not needed (task registered)'
} else {
  $cmd = 'wscript.exe "' + $Vbs + '"'
  Set-ItemProperty -Path $runKey -Name 'LocalAI-Watchdog' -Value $cmd
  Log "run-key entry written: LocalAI-Watchdog = $cmd"
}

# 4) status
Log ''
Log '--- current autostart state ---'
Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue |
  Select-Object TaskName, State | Format-Table -AutoSize | Out-String | Write-Host
Get-ItemProperty -Path $runKey -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty 'LocalAI-Watchdog' -ErrorAction SilentlyContinue | Write-Host
