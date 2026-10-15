# Revert-GameTweaks.ps1 - restore the registry values saved by Apply-GameTweaks.ps1
$ErrorActionPreference = 'Continue'
$BackupFile = 'D:\ai\backup\registry-backup.json'
if (-not (Test-Path -LiteralPath $BackupFile)) { Write-Host "no backup found: $BackupFile"; exit 1 }

$backup = Get-Content -LiteralPath $BackupFile -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($e in $backup.entries) {
  if ($null -eq $e.value) {
    Remove-ItemProperty -Path $e.path -Name $e.name -ErrorAction SilentlyContinue
    Write-Host ("removed {0}\{1}" -f $e.path, $e.name)
  } else {
    Set-ItemProperty -Path $e.path -Name $e.name -Value $e.value -Type DWord -ErrorAction SilentlyContinue
    Write-Host ("restored {0}\{1} = {2}" -f $e.path, $e.name, $e.value)
  }
}
Write-Host 'done (backup file kept for reference)'
