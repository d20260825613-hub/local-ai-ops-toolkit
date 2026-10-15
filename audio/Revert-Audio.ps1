# Undo everything Fix-Audio-AllInOne.ps1 / Repair-WindowsAudio.ps1 changed.
# Run it the same way (UAC "Yes" required).
$ErrorActionPreference = 'Continue'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath
  ) | Out-Null
  exit
}

Write-Output '=== reverting audio changes ==='

# 1. fast startup back on
try {
  Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 1 -Type DWord -ErrorAction Stop
  Write-Output 'fast startup: back ON (1)'
} catch { Write-Output ('fast startup revert failed: ' + $_.Exception.Message) }

# 2. remove service failure actions
foreach ($svc in 'Audiosrv', 'AudioEndpointBuilder') {
  $r = & sc.exe failure $svc reset= 0 actions= '' 2>&1
  Write-Output ("{0} recovery cleared: {1}" -f $svc, (($r -join ' ').Trim()))
}

# 3. device power management back on
try {
  $devs = @(Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -ErrorAction Stop)
  foreach ($d in ($devs | Where-Object { $_.InstanceName -match '(?i)VEN_8086|VEN_10EC|VEN_10DE' })) {
    if (-not $d.Enable) {
      $d.Enable = $true
      try { Set-CimInstance -InputObject $d -ErrorAction Stop; Write-Output ('power save back ON: ' + $d.InstanceName) }
      catch { Write-Output ('power save revert failed: ' + $d.InstanceName) }
    }
  }
} catch { Write-Output ('power management revert failed: ' + $_.Exception.Message) }

# 4. delete the exclusive-mode values we wrote (defaults come back)
$guids = @(
  '61c2c278-1b0e-40e9-8aaf-5c9184528ad8'
)
foreach ($g in $guids) {
  $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\{$g}\Properties"
  foreach ($name in '{b3f8fa53-0004-438e-9003-51a46e139bfc},3', '{b3f8fa53-0004-438e-9003-51a46e139bfc},4') {
    try {
      Remove-ItemProperty -Path $key -Name $name -ErrorAction Stop
      Write-Output ("removed {0} {1}" -f $g.Substring(0, 8), $name)
    } catch { }
  }
}

# 5. Nahimic back to automatic + started
try {
  Set-Service NahimicService -StartupType Automatic -ErrorAction Stop
  Start-Service NahimicService -ErrorAction SilentlyContinue
  Write-Output 'Nahimic service: back to Automatic'
} catch { Write-Output ('nahimic revert failed: ' + $_.Exception.Message) }

# 6. remove the watchdog task
try {
  Unregister-ScheduledTask -TaskName 'DSH-AudioGuard' -Confirm:$false -ErrorAction Stop
  Write-Output 'watchdog task DSH-AudioGuard removed'
} catch { Write-Output ('watchdog removal failed: ' + $_.Exception.Message) }

# 7. restart the audio stack
foreach ($name in 'Audiosrv', 'AudioEndpointBuilder') {
  try { Restart-Service $name -Force -ErrorAction Stop; Write-Output ("restarted {0}" -f $name) } catch { }
}

Write-Output '=== done ==='
try {
  $ws = New-Object -ComObject WScript.Shell
  $ws.Popup('声音设置已还原到修复前的状态。', 0, '还原完成', 64) | Out-Null
} catch { }
