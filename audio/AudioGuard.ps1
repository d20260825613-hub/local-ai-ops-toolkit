# AudioGuard: watch the Windows audio stack and recover automatically from the
# "suddenly no sound" failure mode (service stopped / default endpoint dead).
# Runs elevated from the scheduled task DSH-AudioGuard at logon.
# Conservative by design: at most 3 recoveries per hour, everything logged.

$ErrorActionPreference = 'Continue'
$logDir = 'D:\ai\audio'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$log = Join-Path $logDir 'guard.log'
$stateFile = Join-Path $logDir 'guard-state.json'
$pollSeconds = 45
$deadStreak = 0
$recoveries = @()

function Write-Log {
  param([string]$Message)
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
  Add-Content -LiteralPath $log -Value $line -Encoding UTF8
  # keep the log small
  $fi = Get-Item -LiteralPath $log -ErrorAction SilentlyContinue
  if ($fi -and $fi.Length -gt 512KB) {
    $tail = Get-Content -LiteralPath $log -Tail 400
    Set-Content -LiteralPath $log -Value $tail -Encoding UTF8
  }
}

function Get-DefaultRenderEndpointGuid {
  try {
    [void][Windows.Media.Devices.MediaDevice, Windows.Media.Devices, ContentType = WindowsRuntime]
    $id = [Windows.Media.Devices.MediaDevice]::GetDefaultAudioRenderId([Windows.Media.Devices.AudioDeviceRole]::Default)
    if ($id -match '\{0\.0\.0\.00000000\}\.\{([0-9a-f\-]+)\}') { return $Matches[1] }
  } catch { }
  return $null
}

function Get-EndpointState {
  param([string]$Guid)
  $p = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\{$Guid}"
  $v = (Get-ItemProperty -Path $p -Name DeviceState -ErrorAction SilentlyContinue).DeviceState
  if ($null -eq $v) { return -1 }
  return [int]$v
}

function Invoke-Recovery {
  param([string]$Reason)
  $now = Get-Date
  $script:recoveries = @($script:recoveries | Where-Object { ($now - $_).TotalMinutes -lt 60 })
  if ($script:recoveries.Count -ge 3) {
    Write-Log ("recovery suppressed (3 in the last hour): {0}" -f $Reason)
    return
  }
  $script:recoveries += $now
  Write-Log ("RECOVERY: {0}" -f $Reason)
  foreach ($svc in 'Audiosrv', 'AudioEndpointBuilder') {
    try {
      Restart-Service $svc -Force -ErrorAction Stop
      Write-Log ("  restarted {0}" -f $svc)
    } catch {
      Write-Log ("  restart {0} failed: {1}" -f $svc, $_.Exception.Message)
    }
  }
  Start-Sleep -Seconds 5
  $g = Get-DefaultRenderEndpointGuid
  $st = if ($g) { Get-EndpointState -Guid $g } else { -1 }
  Write-Log ("  after recovery: endpoint={0} state={1}" -f $g, $st)
  Save-State
}

function Save-State {
  $obj = [ordered]@{
    updated      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    audiosrv     = (Get-Service Audiosrv -ErrorAction SilentlyContinue).Status.ToString()
    endpointGuid = Get-DefaultRenderEndpointGuid
    endpointState = ''
    recoveries   = @($script:recoveries | ForEach-Object { $_.ToString('s') })
  }
  if ($obj.endpointGuid) { $obj.endpointState = Get-EndpointState -Guid $obj.endpointGuid }
  try { ($obj | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $stateFile -Encoding UTF8 } catch { }
}

Write-Log ("guard starting (pid {0}, poll {1}s)" -f $PID, $pollSeconds)

while ($true) {
  try {
    $svc = Get-Service Audiosrv -ErrorAction SilentlyContinue
    if (-not $svc) {
      Write-Log 'Audiosrv not found'
    } elseif ($svc.Status -ne 'Running') {
      Invoke-Recovery -Reason ("Audiosrv is {0}" -f $svc.Status)
      $deadStreak = 0
    } else {
      $guid = Get-DefaultRenderEndpointGuid
      if (-not $guid) {
        $deadStreak++
        if ($deadStreak -ge 3) { Invoke-Recovery -Reason 'no default render endpoint'; $deadStreak = 0 }
      } else {
        $state = Get-EndpointState -Guid $guid
        if ($state -ne 1) {
          $deadStreak++
          Write-Log ("default endpoint {0} state={1} (streak {2})" -f $guid, $state, $deadStreak)
          if ($deadStreak -ge 3) { Invoke-Recovery -Reason ("default endpoint state={0}" -f $state); $deadStreak = 0 }
        } else {
          if ($deadStreak -gt 0) { Write-Log 'default endpoint healthy again' }
          $deadStreak = 0
          Save-State
        }
      }
    }
  } catch {
    Write-Log ("cycle error: {0}" -f $_.Exception.Message)
  }
  Start-Sleep -Seconds $pollSeconds
}
