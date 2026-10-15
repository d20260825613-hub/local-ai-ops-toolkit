# Apply-GameTweaks.ps1
# Small, reversible gaming-performance tweaks (backup is written first).
#   1. Xbox Game DVR background recording OFF  (frees GPU + CPU while gaming)
#   2. Windows Game Mode explicitly ON
# Run Revert-GameTweaks.ps1 to put the old values back.

$ErrorActionPreference = 'Stop'
$BackupDir  = 'D:\ai\backup'
$BackupFile = Join-Path $BackupDir 'registry-backup.json'
if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null }

$targets = @(
  @{ Path = 'HKCU:\System\GameConfigStore';                              Name = 'GameDVR_Enabled' },
  @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR';   Name = 'AppCaptureEnabled' },
  @{ Path = 'HKCU:\Software\Microsoft\GameBar';                          Name = 'AutoGameModeEnabled' },
  @{ Path = 'HKCU:\Software\Microsoft\GameBar';                          Name = 'AllowAutoGameMode' }
)

function Read-Value($path, $name) {
  try {
    $item = Get-ItemProperty -Path $path -Name $name -ErrorAction Stop
    return $item.$name
  } catch { return $null }
}

# backup once
if (-not (Test-Path -LiteralPath $BackupFile)) {
  $backup = [ordered]@{ timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); entries = @() }
  foreach ($t in $targets) {
    $backup.entries += [ordered]@{ path = $t.Path; name = $t.Name; value = (Read-Value $t.Path $t.Name) }
  }
  ($backup | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $BackupFile -Encoding UTF8
  Write-Host "backup written: $BackupFile"
} else {
  Write-Host "backup already exists: $BackupFile (left untouched)"
}

# apply
foreach ($t in $targets) {
  if (-not (Test-Path -LiteralPath $t.Path)) { New-Item -Path $t.Path -Force | Out-Null }
  $new = 0
  if ($t.Name -like 'AutoGameMode*' -or $t.Name -eq 'AllowAutoGameMode') { $new = 1 }
  $old = Read-Value $t.Path $t.Name
  if ($old -ne $new) {
    Set-ItemProperty -Path $t.Path -Name $t.Name -Value $new -Type DWord
    Write-Host ("set {0}\{1}: {2} -> {3}" -f $t.Path, $t.Name, $old, $new)
  } else {
    Write-Host ("already {0}\{1} = {2}" -f $t.Path, $t.Name, $old)
  }
}

Write-Host ''
Write-Host '--- verify ---'
foreach ($t in $targets) {
  Write-Host ("{0}\{1} = {2}" -f $t.Path, $t.Name, (Read-Value $t.Path $t.Name))
}
