# Fix the common Windows causes of "sound randomly stops working" on this laptop.
# Every change is reversible; see "声音问题修复说明.txt" in the same folder.
# This file is intentionally written with a UTF-8 BOM: Windows PowerShell 5.1 reads a
# .ps1 without a BOM as ANSI, and that file name is not ASCII.
# Original values are recorded in audio-backup.json so Revert-Audio.ps1 restores them
# instead of guessing factory defaults.
$ErrorActionPreference = 'Continue'

# The original values of everything this script changes are recorded in
# audio\audio-backup.json before the first change, so Revert-Audio.ps1 restores the
# real previous state instead of guessing "factory defaults".
. (Join-Path $PSScriptRoot 'lib\AudioBackup.ps1')
$backupPath = Get-AudioBackupPath -Dir $PSScriptRoot

Write-Output '=== context ==='
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
$elevated = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Output ("user      : {0}" -f $id.Name)
Write-Output ("elevated  : {0}" -f $elevated)

# --------------------------------------------------- 0. record the original values
$pwrPath   = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
$EXCL_ALLOW = '{b3f8fa53-0004-438e-9003-51a46e139bfc},3'
$EXCL_PRIO  = '{b3f8fa53-0004-438e-9003-51a46e139bfc},4'

$defaultGuid = $null
try {
  [void][Windows.Media.Devices.MediaDevice, Windows.Media.Devices, ContentType = WindowsRuntime]
  $defaultRenderId = [Windows.Media.Devices.MediaDevice]::GetDefaultAudioRenderId([Windows.Media.Devices.AudioDeviceRole]::Default)
  if ($defaultRenderId -match '\{0\.0\.[01]\.00000000\}\.\{([0-9a-fA-F\-]+)\}') { $defaultGuid = $Matches[1].ToLower() }
} catch { }

$snapshot = [ordered]@{
  hostName          = $env:COMPUTERNAME
  hiberbootEnabled  = (Get-ItemProperty $pwrPath -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
  nahimicStartType  = Get-AudioServiceStartType -Name 'NahimicService'
  nahimicStatus     = $null
  defaultRenderGuid = $defaultGuid
  exclusiveMode     = @()
}
$svcSnap = Get-Service NahimicService -ErrorAction SilentlyContinue
if ($svcSnap) { $snapshot.nahimicStatus = [string]$svcSnap.Status }

# record both exclusive-mode properties on every endpoint we are about to touch
$exclTargets = @()
if ($defaultGuid) { $exclTargets += $defaultGuid }
$exclTargets += '61c2c278-1b0e-40e9-8aaf-5c9184528ad8'
$exclTargets = @($exclTargets | Select-Object -Unique)
foreach ($g in $exclTargets) {
  $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\{$g}\Properties"
  $entry = [ordered]@{ guid = $g; keyExists = [bool](Test-Path $key); values = [ordered]@{} }
  if ($entry.keyExists) {
    foreach ($name in $EXCL_ALLOW, $EXCL_PRIO) {
      $entry.values[$name] = (Get-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue).$name
    }
  }
  $snapshot.exclusiveMode += $entry
}

if (New-AudioBackupIfMissing -Data $snapshot -Path $backupPath) {
  Write-Output ("0) original values recorded: {0}" -f $backupPath)
} else {
  Write-Output ("0) original values already recorded, kept as they were: {0}" -f $backupPath)
}

# ---------------------------------------------------------------- 1. fast startup
$pwr = $pwrPath
$before = (Get-ItemProperty $pwr -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
Write-Output ''
Write-Output ("1) fast startup (HiberbootEnabled) before = {0}" -f $before)
if ($before -ne 0) {
  try {
    Set-ItemProperty -Path $pwr -Name HiberbootEnabled -Value 0 -Type DWord -ErrorAction Stop
    $after = (Get-ItemProperty $pwr -Name HiberbootEnabled).HiberbootEnabled
    Write-Output ("   -> set to {0} (a full shutdown now really re-initialises drivers)" -f $after)
  } catch {
    Write-Output ("   -> FAILED: {0}" -f $_.Exception.Message)
  }
} else {
  Write-Output '   -> already off'
}

# ------------------------------------------------- 2. audio service auto-recovery
Write-Output ''
Write-Output '2) service recovery (restart automatically if the audio service dies)'
foreach ($svc in 'Audiosrv', 'AudioEndpointBuilder') {
  $r = & sc.exe failure $svc reset= 86400 actions= restart/5000/restart/5000/restart/5000 2>&1
  Write-Output ("   {0}: {1}" -f $svc, (($r -join ' ').Trim()))
}

# ------------------------------------------- 3. stop Windows powering down audio
Write-Output ''
Write-Output '3) device power management (stop Windows switching the codec off to save power)'
try {
  $devs = @(Get-CimInstance -Namespace root\wmi -ClassName MSPower_DeviceEnable -ErrorAction Stop)

  # Only touch devices that really belong to the audio stack:
  #   - every "High Definition Audio Controller" (Intel/NVIDIA HDA buses)
  #   - the Realtek codec (HDAUDIO\...VEN_10EC...)
  $audioInstanceIds = @()
  try {
    $audioInstanceIds = @(Get-PnpDevice -Class 'MEDIA', 'System' -ErrorAction SilentlyContinue |
      Where-Object { $_.FriendlyName -match '(?i)high definition audio controller|realtek\(r\) audio|audio' -and $_.InstanceId } |
      Select-Object -ExpandProperty InstanceId)
  } catch { }
  $audioInstanceIds = @($audioInstanceIds | ForEach-Object { $_.ToUpper() })

  $targets = @()
  foreach ($d in $devs) {
    $inst = ([string]$d.InstanceName).ToUpper()
    if ($inst -match 'VEN_10EC') { $targets += $d; continue }       # Realtek codec
    foreach ($aid in $audioInstanceIds) {
      if ($inst.StartsWith($aid)) { $targets += $d; break }
    }
  }
  Write-Output ("   audio devices with power management: {0}" -f $targets.Count)
  foreach ($d in $targets) {
    $short = ($d.InstanceName -replace '\\_0$', '')
    if ($d.Enable) {
      $d.Enable = $false
      try {
        Set-CimInstance -InputObject $d -ErrorAction Stop
        Write-Output ("   [off] {0}" -f $short)
      } catch {
        Write-Output ("   [fail] {0} : {1}" -f $short, $_.Exception.Message)
      }
    } else {
      Write-Output ("   [already off] {0}" -f $short)
    }
  }
} catch {
  Write-Output ("   FAILED: {0}" -f $_.Exception.Message)
}

# --------------------------------- 4. exclusive mode off on the default endpoint
Write-Output ''
Write-Output '4) exclusive mode on the default output device'
$guid = $defaultGuid
Write-Output ("   default endpoint guid : {0}" -f $guid)
if (-not $guid) { Write-Output '   WARNING: the default endpoint could not be determined; only the known Realtek endpoint is touched' }

foreach ($g in $exclTargets) {
  $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\{$g}\Properties"
  if (-not (Test-Path $key)) { Write-Output ("   {0}: no property store" -f $g); continue }
  foreach ($name in $EXCL_ALLOW, $EXCL_PRIO) {
    $old = (Get-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue).$name
    try {
      Set-ItemProperty -Path $key -Name $name -Value 0 -Type DWord -ErrorAction Stop
      Write-Output ("   {0} {1}: {2} -> 0 (original kept in audio-backup.json)" -f $g, $name.Split(',')[1], $old)
    } catch {
      Write-Output ("   {0} {1}: FAILED {2}" -f $g, $name.Split(',')[1], $_.Exception.Message)
    }
  }
}

# ------------------------------------------------------------ 5. Nahimic service
Write-Output ''
Write-Output '5) Nahimic (Dell audio effect layer, a known cause of random silence)'
$svc = Get-Service NahimicService -ErrorAction SilentlyContinue
if ($svc) {
  Write-Output ("   before: {0} / {1}" -f $svc.Status, $svc.StartType)
  try {
    if ($svc.Status -eq 'Running') { Stop-Service NahimicService -Force -ErrorAction Stop }
    Set-Service NahimicService -StartupType Manual -ErrorAction Stop
    $svc2 = Get-Service NahimicService
    Write-Output ("   after : {0} / {1}  (can be re-enabled any time)" -f $svc2.Status, $svc2.StartType)
  } catch {
    Write-Output ("   FAILED: {0}" -f $_.Exception.Message)
  }
} else {
  Write-Output '   not installed'
}

# ------------------------------------------------------ 6. restart the audio stack
Write-Output ''
Write-Output '6) restarting the audio stack'
foreach ($name in 'Audiosrv', 'AudioEndpointBuilder') {
  try {
    Restart-Service $name -Force -ErrorAction Stop
    Write-Output ("   restarted {0}" -f $name)
  } catch {
    Write-Output ("   restart {0} failed: {1}" -f $name, $_.Exception.Message)
  }
}
Start-Sleep -Seconds 3

Write-Output ''
Write-Output '=== state after repair ==='
Get-Service Audiosrv, AudioEndpointBuilder, NahimicService -ErrorAction SilentlyContinue |
  Select-Object Name, Status, StartType | Format-Table -AutoSize
Write-Output ("fast startup = {0}" -f (Get-ItemProperty $pwr -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled)
try {
  [void][Windows.Media.Devices.MediaDevice, Windows.Media.Devices, ContentType = WindowsRuntime]
  Write-Output ('default render now: ' + [Windows.Media.Devices.MediaDevice]::GetDefaultAudioRenderId([Windows.Media.Devices.AudioDeviceRole]::Default))
} catch { }
