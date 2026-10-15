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

# Original values recorded by Repair-WindowsAudio.ps1 before it changed anything.
# When the backup is missing we do NOT guess: a "factory default" guess turned
# Nahimic into a boot-start service and fast startup back on even on machines where
# neither had been the original state.
. (Join-Path $PSScriptRoot 'lib\AudioBackup.ps1')
$backupPath = Get-AudioBackupPath -Dir $PSScriptRoot
$backup = Read-AudioBackup -Path $backupPath
if (-not $backup) {
  Write-Output ("NOTE: {0} not found - the original values are unknown." -f $backupPath)
  Write-Output '      Only values that can be restored without guessing are touched;'
  Write-Output '      run Repair-WindowsAudio.ps1 once first if you want a full revert.'
}

# 1. fast startup back to the recorded value
try {
  $pwrKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
  $want = $null
  if ($backup -and $null -ne $backup.hiberbootEnabled) { $want = [int]$backup.hiberbootEnabled }
  if ($null -eq $want) {
    Write-Output 'fast startup: original value unknown - left AS IS (was it on or off before?)'
  } else {
    Set-ItemProperty -Path $pwrKey -Name HiberbootEnabled -Value $want -Type DWord -ErrorAction Stop
    Write-Output ("fast startup: restored to {0}" -f $want)
  }
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

# 4. exclusive mode: put back exactly what the repair recorded
$exclNames = '{b3f8fa53-0004-438e-9003-51a46e139bfc},3', '{b3f8fa53-0004-438e-9003-51a46e139bfc},4'
if ($backup -and @($backup.exclusiveMode).Count -gt 0) {
  foreach ($entry in @($backup.exclusiveMode)) {
    $g = [string]$entry.guid
    if (-not $g) { continue }
    $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\{$g}\Properties"
    if (-not (Test-Path $key)) { Write-Output ("{0}: property store is gone, skipped" -f $g); continue }
    foreach ($name in $exclNames) {
      $had = $null
      $old = $null
      if ($entry.values) {
        $prop = $entry.values.PSObject.Properties[$name]
        if ($prop) { $had = $true; $old = $prop.Value }
      }
      try {
        if (-not $had -or $null -eq $old) {
          # the value did not exist before the repair: delete ours so the system default returns
          if ($null -ne (Get-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue).$name) {
            Remove-ItemProperty -Path $key -Name $name -ErrorAction Stop
            Write-Output ("removed {0} {1} (it did not exist before the repair)" -f $g, $name.Split(',')[1])
          }
        } else {
          Set-ItemProperty -Path $key -Name $name -Value ([int]$old) -Type DWord -ErrorAction Stop
          Write-Output ("restored {0} {1} = {2}" -f $g, $name.Split(',')[1], $old)
        }
      } catch {
        Write-Output ("{0} {1}: revert failed: {2}" -f $g, $name.Split(',')[1], $_.Exception.Message)
      }
    }
  }
} else {
  # no backup: fall back to the historical behaviour, but say so instead of hiding it
  Write-Output 'exclusive mode: no backup, clearing the known Realtek endpoint only'
  $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\{61c2c278-1b0e-40e9-8aaf-5c9184528ad8}\Properties'
  foreach ($name in $exclNames) {
    try {
      Remove-ItemProperty -Path $key -Name $name -ErrorAction Stop
      Write-Output ("removed 61c2c278 {0}" -f $name)
    } catch {
      if ($null -ne (Get-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue).$name) {
        Write-Output ("61c2c278 {0}: remove failed: {1}" -f $name, $_.Exception.Message)
      }
    }
  }
}

# 5. Nahimic: restore the recorded startup type, and only start it if it was running
if ($backup -and $backup.nahimicStartType) {
  $wantType = ConvertTo-ServiceStartupType -Value $backup.nahimicStartType
  try {
    if (-not $wantType) { throw ("unrecognised recorded StartType '{0}'" -f $backup.nahimicStartType) }
    Set-Service NahimicService -StartupType $wantType -ErrorAction Stop
    if ($backup.nahimicStatus -eq 'Running') {
      Start-Service NahimicService -ErrorAction SilentlyContinue
      Write-Output ("Nahimic service: restored to {0} / Running" -f $wantType)
    } else {
      Write-Output ("Nahimic service: restored to {0} (originally not running, left stopped)" -f $wantType)
    }
  } catch { Write-Output ('nahimic revert failed: ' + $_.Exception.Message) }
} else {
  Write-Output 'Nahimic service: no backup - left AS IS (guessing "Automatic" could enable a service that was Disabled)'
}

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
