# Report the current default audio endpoints (render + capture) and every render
# endpoint's state.
#
# Why this is not COM interop anymore
#   The previous version hand-wrote the Core Audio (MMDevice) interfaces and a
#   PROPVARIANT struct. The layout was wrong for x64 (24 bytes, union at offset 8)
#   and the interface signatures did not match the real vtables, so the script died
#   with an access violation (0xC0000005 / exit code -1073741819) on the first COM
#   call and produced no output at all.
#   The WinRT MediaDevice API used by audio/List-AudioEndpoints.ps1 and
#   audio/AudioGuard.ps1 is stable on Windows PowerShell 5.1, and the endpoint id it
#   returns is the same {0.0.0.00000000}.{guid} form that keys the MMDevices registry
#   store, so endpoint names and states can come from the registry without any
#   interop. This file is the read-only "second opinion" next to List-AudioEndpoints.ps1
#   and touches no device.
$ErrorActionPreference = 'Continue'

function Get-MediaDeviceId {
  param([ValidateSet('render', 'capture')][string]$Kind, [ValidateSet('Default', 'Communications')][string]$Role = 'Default')
  try {
    [void][Windows.Media.Devices.MediaDevice, Windows.Media.Devices, ContentType = WindowsRuntime]
    $roleValue = [Windows.Media.Devices.AudioDeviceRole]::Default
    if ($Role -eq 'Communications') { $roleValue = [Windows.Media.Devices.AudioDeviceRole]::Communications }
    if ($Kind -eq 'render') {
      return [Windows.Media.Devices.MediaDevice]::GetDefaultAudioRenderId($roleValue)
    }
    return [Windows.Media.Devices.MediaDevice]::GetDefaultAudioCaptureId($roleValue)
  } catch {
    return $null
  }
}

function Get-EndpointGuid {
  param([string]$DeviceId)
  # render endpoints use {0.0.0.00000000}.{guid}, capture endpoints {0.0.1.00000000}.{guid}
  if ($DeviceId -and $DeviceId -match '\{0\.0\.[01]\.00000000\}\.\{([0-9a-fA-F\-]+)\}') { return $Matches[1].ToLower() }
  return $null
}

function Get-EndpointStore {
  param([ValidateSet('Render', 'Capture')][string]$Flow = 'Render')
  $root = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\$Flow"
  $map = @{}
  foreach ($k in @(Get-ChildItem $root -ErrorAction SilentlyContinue)) {
    $guid = ([string]$k.PSChildName).Trim('{}').ToLower()
    $state = (Get-ItemProperty -Path $k.PSPath -Name DeviceState -ErrorAction SilentlyContinue).DeviceState
    $props = Get-ItemProperty -Path (Join-Path $k.PSPath 'Properties') -ErrorAction SilentlyContinue
    $name = ''
    if ($props) { $name = [string]$props.'{a45c254e-df1c-4efd-8020-67d146a850e0},14' }
    if (-not $name -and $props) { $name = [string]$props.'{a45c254e-df1c-4efd-8020-67d146a850e0},2' }
    $map[$guid] = [pscustomobject]@{ Guid = $guid; Name = $name; DeviceState = $state }
  }
  return $map
}

function Format-Endpoint {
  param([string]$DeviceId, $Store)
  if (-not $DeviceId) { return 'none (the WinRT MediaDevice API is unavailable)' }
  $guid = Get-EndpointGuid -DeviceId $DeviceId
  if (-not $guid) { return ('id={0} (unrecognised id format)' -f $DeviceId) }
  $entry = $null
  if ($Store -and $Store.ContainsKey($guid)) { $entry = $Store[$guid] }
  $state = 'not in the MMDevices store'
  $name = ''
  if ($entry) {
    $stateMap = @{ 1 = 'ACTIVE'; 2 = 'DISABLED'; 4 = 'NOTPRESENT'; 8 = 'UNPLUGGED' }
    $state = 'state=' + $entry.DeviceState
    if ($null -ne $entry.DeviceState -and $stateMap.ContainsKey([int]$entry.DeviceState)) { $state = $stateMap[[int]$entry.DeviceState] }
    $name = $entry.Name
  }
  return ('state={0} name="{1}" id={2}' -f $state, $name, $DeviceId)
}

$renderStore = Get-EndpointStore -Flow 'Render'
$captureStore = Get-EndpointStore -Flow 'Capture'

# NOTE: Windows exposes only two endpoint roles through WinRT (Default and
# Communications). The Core Audio "console" role is the same endpoint as "multimedia",
# so the first two sections intentionally report the identical endpoint; the old COM
# build printed them separately because it could ask for role 0 and role 1 directly.
Write-Output '=== default render (console role = multimedia role) ==='
Format-Endpoint -DeviceId (Get-MediaDeviceId -Kind 'render' -Role 'Default') -Store $renderStore
Write-Output '=== default render (multimedia role) ==='
Format-Endpoint -DeviceId (Get-MediaDeviceId -Kind 'render' -Role 'Default') -Store $renderStore
Write-Output '=== default render (communications role) ==='
Format-Endpoint -DeviceId (Get-MediaDeviceId -Kind 'render' -Role 'Communications') -Store $renderStore
Write-Output '=== default capture (console role) ==='
Format-Endpoint -DeviceId (Get-MediaDeviceId -Kind 'capture' -Role 'Default') -Store $captureStore

Write-Output '=== all render endpoints ==='
foreach ($guid in @($renderStore.Keys | Sort-Object)) {
  $e = $renderStore[$guid]
  $stateMap = @{ 1 = 'ACTIVE'; 2 = 'DISABLED'; 4 = 'NOTPRESENT'; 8 = 'UNPLUGGED' }
  $state = 'state=' + $e.DeviceState
  if ($null -ne $e.DeviceState -and $stateMap.ContainsKey([int]$e.DeviceState)) { $state = $stateMap[[int]$e.DeviceState] }
  Write-Output ('[{0}] {{{1}}} {2}' -f $state, $guid, $e.Name)
}
