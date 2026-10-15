# List all render audio endpoints (name, state, key properties) and the current
# default devices, using the WinRT MediaDevice API plus the MMDevices registry store.
$ErrorActionPreference = 'Continue'

try {
  [void][Windows.Media.Devices.MediaDevice, Windows.Media.Devices, ContentType = WindowsRuntime]
  $roleDefault = [Windows.Media.Devices.AudioDeviceRole]::Default
  $roleComm    = [Windows.Media.Devices.AudioDeviceRole]::Communications
  Write-Output ('default render  : ' + [Windows.Media.Devices.MediaDevice]::GetDefaultAudioRenderId($roleDefault))
  Write-Output ('default comm    : ' + [Windows.Media.Devices.MediaDevice]::GetDefaultAudioRenderId($roleComm))
  Write-Output ('default capture : ' + [Windows.Media.Devices.MediaDevice]::GetDefaultAudioCaptureId($roleDefault))
} catch {
  Write-Output ('WinRT MediaDevice failed: ' + $_.Exception.Message)
}

$root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
$stateMap = @{ 1 = 'ACTIVE'; 2 = 'DISABLED'; 4 = 'NOTPRESENT'; 8 = 'UNPLUGGED' }
$propMap = @{
  '{a45c254e-df1c-4efd-8020-67d146a850e0},14' = 'name'
  '{a45c254e-df1c-4efd-8020-67d146a850e0},2'  = 'desc'
  '{b3f8fa53-0004-438e-9003-51a46e139bfc},3'  = 'exclusive-allow'
  '{b3f8fa53-0004-438e-9003-51a46e139bfc},4'  = 'exclusive-priority'
  '{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},0'  = 'disable-sys-effects'
  '{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},3'  = 'disable-enhancements'
  '{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},5'  = 'disable-spatial'
}

Write-Output ''
Write-Output '=== render endpoints ==='
Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
  $guid = $_.PSChildName
  $state = (Get-ItemProperty $_.PSPath -Name DeviceState -ErrorAction SilentlyContinue).DeviceState
  $props = Get-ItemProperty (Join-Path $_.PSPath 'Properties') -ErrorAction SilentlyContinue
  $name = ''
  if ($props) { $name = $props.'{a45c254e-df1c-4efd-8020-67d146a850e0},14' }
  $stateText = 'state=' + $state
  if ($stateMap.ContainsKey([int]$state)) { $stateText = $stateMap[[int]$state] }
  $line = '[{0}] {1}  {2}' -f $stateText, $guid, $name
  Write-Output $line
  if ($props) {
    foreach ($k in $propMap.Keys) {
      $v = $props.$k
      if ($null -ne $v) { Write-Output ('      {0} = {1}' -f $propMap[$k], $v) }
    }
  }
}
