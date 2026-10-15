# audio/lib/AudioBackup.ps1
#
# Shared by Repair-WindowsAudio.ps1 and Revert-Audio.ps1.
#
# The repair script used to change settings without recording what they were before,
# so the revert script had to guess "factory defaults" (Nahimic -> Automatic, fast
# startup -> 1, ...). On a machine where Nahimic was originally Disabled, or fast
# startup was originally 0, "revert" therefore moved the machine somewhere it had
# never been. This helper writes the real original values to audio\audio-backup.json
# before the first change is made, and the revert script restores exactly those
# values. Nothing here is Windows-version or machine specific.
#
# ASCII-only on purpose: Windows PowerShell 5.1 reads a file without a BOM as ANSI.

function Get-AudioBackupPath {
  [CmdletBinding()]
  param([string]$Dir)
  if (-not $Dir) {
    if ($PSScriptRoot) { $Dir = Split-Path -Parent $PSScriptRoot } else { $Dir = 'D:\ai\audio' }
    if (-not (Test-Path -LiteralPath $Dir)) { $Dir = 'D:\ai\audio' }
  }
  return (Join-Path $Dir 'audio-backup.json')
}

function Read-AudioBackup {
  [CmdletBinding()]
  param([string]$Path)
  if (-not $Path) { $Path = Get-AudioBackupPath }
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try {
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
  } catch {
    Write-Warning ("audio-backup.json is unreadable ({0}); refusing to guess original values" -f $_.Exception.Message)
    return $null
  }
}

function Write-AudioBackup {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)]$Data, [string]$Path)
  if (-not $Path) { $Path = Get-AudioBackupPath }
  if (-not $Data.created) { $Data | Add-Member -NotePropertyName created -NotePropertyValue (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Force }
  try {
    ($Data | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $Path -Encoding UTF8
    return $true
  } catch {
    Write-Warning ("could not write {0}: {1}" -f $Path, $_.Exception.Message)
    return $false
  }
}

# Create the backup once. If the file already exists the earlier (truly original)
# values win, so running the repair twice cannot overwrite the backup with values the
# repair itself wrote.
function New-AudioBackupIfMissing {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)]$Data, [string]$Path)
  if (-not $Path) { $Path = Get-AudioBackupPath }
  if (Test-Path -LiteralPath $Path) { return $false }
  return (Write-AudioBackup -Data $Data -Path $Path)
}

# Read a named property from the backup, or $null when it is unknown.
function Get-AudioBackupValue {
  [CmdletBinding()]
  param([string]$Name, [string]$Path)
  $bk = Read-AudioBackup -Path $Path
  if (-not $bk) { return $null }
  if ($null -eq $bk.PSObject.Properties[$Name]) { return $null }
  return $bk.$Name
}

function Get-AudioServiceStartType {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Name)
  $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
  if (-not $svc) { return $null }
  return [string]$svc.StartType
}

function Get-AudioHiberbootEnabled {
  [CmdletBinding()]
  param()
  $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  $v = (Get-ItemProperty -Path $p -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
  if ($null -eq $v) { return $null }
  return [int]$v
}

# Turn a StartType string back into the -StartupType argument Set-Service accepts.
function ConvertTo-ServiceStartupType {
  [CmdletBinding()]
  param([string]$Value)
  switch -Regex ([string]$Value) {
    '^(?i)auto'      { return 'Automatic' }
    '^(?i)manual'    { return 'Manual' }
    '^(?i)disabled'  { return 'Disabled' }
    '^(?i)boot'      { return 'Boot' }
    '^(?i)system'    { return 'System' }
    default          { return $null }
  }
}

# --- log encoding -----------------------------------------------------------------

# The audio log used to have two writers with incompatible encodings: PowerShell's
# -Encoding UTF8 (BOM) and cmd.exe's ">" redirection, which writes UTF-16LE when it
# captures a program's output. Appending one to the other produced a file that was
# ~47% NUL bytes and unreadable in a normal editor. Logs are now written only through
# Add-Content -Encoding UTF8 (see Fix-Audio-AllInOne.ps1), and this function repairs a
# file that was damaged by the old behaviour.
function Repair-LaotLogEncoding {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -eq 0) { return $false }
  $nul = 0
  foreach ($b in $bytes) { if ($b -eq 0) { $nul++ } }
  if ($nul -eq 0) { return $false }
  # UTF-16LE was decoded byte-by-byte as UTF-8; dropping the NULs restores most of the
  # text. A few multi-byte sequences are unrecoverable, so those runs are marked.
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  $text = $text.Replace("`0", '')
  $text = $text.TrimStart([char]0xFEFF)
  $header = '=== {0}: repaired a mixed-encoding log ({1} NUL bytes, UTF-8 + UTF-16LE written by two writers) ===' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $nul
  $body = @($header) + @($text -split "`r?`n")
  Set-Content -LiteralPath $Path -Value $body -Encoding UTF8
  return $true
}

# True when a log file can be read as plain UTF-8 (no NUL bytes, no lone surrogates).
function Test-LaotLogReadable {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  foreach ($b in $bytes) { if ($b -eq 0) { return $false } }
  return $true
}
