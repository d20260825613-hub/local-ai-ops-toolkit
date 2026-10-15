<#
  LaotLib.psm1 - Local AI Ops Toolkit / local-ai-ops-toolkit

  Pure helpers shared by LocalAI-Watchdog.ps1 and tools/selftest.ps1, so that the
  self-test exercises exactly the code the watchdog runs (no second copy of the
  rules, no service is touched by the tests).

  Everything here is Windows PowerShell 5.1 compatible and ASCII-only on purpose:
  PowerShell 5.1 reads a file without a BOM as ANSI, and non-ASCII text would come
  out garbled. See tools/selftest.ps1 for how to run the checks.
#>

Set-StrictMode -Off

# --- config -----------------------------------------------------------------------

# Read config.json without trusting a single encoding. A BOM decides; otherwise try
# UTF-8 first and fall back to the ANSI code page (Notepad "ANSI" = GBK on a Chinese
# system, which is what the repository's Chinese quick-start notes tell users to edit).
# Reading GBK bytes as UTF-8 would silently turn the Chinese game keywords into
# garbage, so the fallback matters.
function Read-LaotConfigText {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path)

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $strict = New-Object System.Text.UTF8Encoding($false, $true)

  if ($hasBom) {
    return [pscustomobject]@{
      Text     = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
      Encoding = 'utf8-bom'
    }
  }
  try {
    return [pscustomobject]@{ Text = $strict.GetString($bytes); Encoding = 'utf8' }
  } catch {
    return [pscustomobject]@{
      Text     = [System.Text.Encoding]::Default.GetString($bytes)
      Encoding = 'ansi'
    }
  }
}

# JSON has no comment syntax, but ConvertFrom-Json silently accepts it. A commented
# config would start the service with values the user believes are switched off, so
# comments are rejected explicitly.
function Test-LaotJsonComment {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
  $stripped = [regex]::Replace($Text, '"(?:\\.|[^"\\])*"', '""')
  return [bool]([regex]::IsMatch($stripped, '//|/\*'))
}

function Get-LaotFieldCount {
  [CmdletBinding()]
  param($Object)
  $n = 0
  foreach ($p in $Object.PSObject.Properties) { $n++ }
  return $n
}

function Test-LaotIsScalar {
  [CmdletBinding()]
  param($Value)
  if ($null -eq $Value) { return $false }
  if ($Value -is [string]) { return $true }
  if ($Value -is [bool]) { return $true }
  if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) { return $true }
  return $false
}

function Test-LaotIsPositiveInt {
  [CmdletBinding()]
  param($Value)
  if ($null -eq $Value) { return $false }
  if ($Value -is [bool]) { return $false }
  $n = 0
  if (-not [int]::TryParse(([string]$Value).Trim(), [ref]$n)) { return $false }
  return ($n -ge 1)
}

function Test-LaotIsPort {
  [CmdletBinding()]
  param($Value)
  if ($null -eq $Value) { return $false }
  if ($Value -is [bool]) { return $false }
  $n = 0
  if (-not [int]::TryParse(([string]$Value).Trim(), [ref]$n)) { return $false }
  return ($n -ge 1 -and $n -le 65535)
}

# Validate a parsed config. Returns an array of human-readable problems; an empty
# array means "usable". This is the rule that stops an empty / {} / null config from
# "successfully" starting llama-server with an empty argument list.
function Test-LaotConfig {
  [CmdletBinding()]
  param(
    $Config,
    [string]$BaseDir = '.',
    [switch]$CheckFiles
  )

  $problems = New-Object System.Collections.ArrayList

  if ($null -eq $Config) {
    [void]$problems.Add('file is empty or contains only null')
    return @($problems)
  }
  if (Test-LaotIsScalar $Config) {
    [void]$problems.Add('top level must be a JSON object, got ' + $Config.GetType().Name)
    return @($problems)
  }
  if ($Config -is [array]) {
    [void]$problems.Add('top level must be a JSON object, got an array')
    return @($problems)
  }
  if ((Get-LaotFieldCount $Config) -eq 0) {
    [void]$problems.Add('{} has no fields')
    return @($problems)
  }

  foreach ($k in @('llamaServer', 'model', 'host', 'port')) {
    $v = $Config.$k
    if ($null -eq $v -or ([string]$v).Trim() -eq '') {
      [void]$problems.Add('required field missing or empty: ' + $k)
    }
  }

  if (-not (Test-LaotIsPort $Config.port)) {
    [void]$problems.Add('port must be an integer 1-65535, got "' + $Config.port + '"')
  }
  if (-not (Test-LaotIsPositiveInt $Config.pollSeconds)) {
    [void]$problems.Add('pollSeconds must be a positive integer, got "' + $Config.pollSeconds + '"')
  }

  if ($null -ne $Config.logKeepDays -and ([string]$Config.logKeepDays).Trim() -ne '') {
    if (-not (Test-LaotIsPositiveInt $Config.logKeepDays)) {
      [void]$problems.Add('logKeepDays must be a positive integer, got "' + $Config.logKeepDays + '"')
    }
  }

  foreach ($k in @('gamePathKeywords', 'gameExeNames', 'gameExcludeKeywords', 'gameExcludeNames',
                   'aiGameKeywords', 'aiGameExeNames', 'wallpaperProcessNames')) {
    $v = $Config.$k
    if ($null -eq $v) { continue }
    if (Test-LaotIsScalar $v) {
      [void]$problems.Add($k + ' must be a JSON array, got ' + $v.GetType().Name)
    }
  }

  if ($Config.sydney -and $Config.sydney.enabled) {
    foreach ($k in @('exe', 'model', 'host')) {
      $v = $Config.sydney.$k
      if ($null -eq $v -or ([string]$v).Trim() -eq '') {
        [void]$problems.Add('sydney.enabled is true but sydney.' + $k + ' is missing or empty')
      }
    }
    if (-not (Test-LaotIsPort $Config.sydney.port)) {
      [void]$problems.Add('sydney.port must be an integer 1-65535, got "' + $Config.sydney.port + '"')
    } elseif ((Test-LaotIsPort $Config.port) -and [int]$Config.sydney.port -eq [int]$Config.port) {
      [void]$problems.Add('sydney.port equals the main port (' + $Config.port + '); the two services cannot share a port')
    }
    if ($null -ne $Config.sydneyStartCooldownSeconds -and ([string]$Config.sydneyStartCooldownSeconds).Trim() -ne '') {
      if (-not (Test-LaotIsPositiveInt $Config.sydneyStartCooldownSeconds)) {
        [void]$problems.Add('sydneyStartCooldownSeconds must be a positive integer, got "' + $Config.sydneyStartCooldownSeconds + '"')
      }
    }
  }

  if ($CheckFiles) {
    if (([string]$Config.llamaServer).Trim() -ne '') {
      $p = Resolve-LaotPath -Path ([string]$Config.llamaServer) -BaseDir $BaseDir
      if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { [void]$problems.Add('llamaServer not found: ' + $Config.llamaServer) }
    }
    if (([string]$Config.model).Trim() -ne '') {
      $p = Resolve-LaotPath -Path ([string]$Config.model) -BaseDir $BaseDir
      if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { [void]$problems.Add('model not found: ' + $Config.model) }
    }
    if ($Config.sydney -and $Config.sydney.enabled -and ([string]$Config.sydney.exe).Trim() -ne '') {
      $p = Resolve-LaotPath -Path ([string]$Config.sydney.exe) -BaseDir $BaseDir
      if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { [void]$problems.Add('sydney.exe not found: ' + $Config.sydney.exe) }
    }
  }

  return @($problems)
}

# Relative paths in a config are resolved against the config's own folder, which is
# what makes "copy the repo to a temp dir and redirect D:\ai" testable.
function Resolve-LaotPath {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path, [string]$BaseDir = '.')
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return (Join-Path $BaseDir $Path)
}

# --- process / port scoping -------------------------------------------------------

# The watchdog owns exactly one llama-server per port (main model port, Sydney port).
# Selecting by process name alone would also stop the other service, so the port in
# the command line is the only reliable discriminator. Kept pure so the self-test can
# feed it fake command lines.
#
# The port is matched as a whole argument, not as a substring: a plain
# "*--port 8080*" would also match a process started with "--port 80801".
function Select-LaotProcessIds {
  [CmdletBinding()]
  param(
    [object[]]$Processes,
    [Parameter(Mandatory = $true)]$Port
  )
  $pattern = '(?i)--port[ =]+"?{0}"?(?=$|\s)' -f [regex]::Escape([string]$Port)
  $ids = @()
  foreach ($p in @($Processes)) {
    if ($null -eq $p) { continue }
    if (-not $p.CommandLine) { continue }
    if ($p.CommandLine -match $pattern) {
      if ($null -ne $p.ProcessId) { $ids += [int]$p.ProcessId }
    }
  }
  return @($ids)
}

function Test-LaotCommandLinePort {
  [CmdletBinding()]
  param([string]$CommandLine, [Parameter(Mandatory = $true)]$Port)
  return (@(Select-LaotProcessIds -Processes @([pscustomobject]@{ ProcessId = 1; CommandLine = $CommandLine }) -Port $Port).Count -gt 0)
}

function Get-LaotLlamaPortFromArgs {
  [CmdletBinding()]
  param([string]$CommandLine)
  if (-not $CommandLine) { return $null }
  if ($CommandLine -match '(?i)--port[ =]+"?([0-9]{1,5})"?') { return [int]$Matches[1] }
  return $null
}

# --- cooldown / VRAM gates --------------------------------------------------------

function Get-LaotSydneyCooldown {
  [CmdletBinding()]
  param($Config)
  if ($null -ne $Config.sydneyStartCooldownSeconds -and ([string]$Config.sydneyStartCooldownSeconds).Trim() -ne '') {
    if (Test-LaotIsPositiveInt $Config.sydneyStartCooldownSeconds) { return [int]$Config.sydneyStartCooldownSeconds }
  }
  if (Test-LaotIsPositiveInt $Config.aiStartCooldownSeconds) { return [int]$Config.aiStartCooldownSeconds }
  return 0
}

# $FreeMiB = -1 means "could not probe" (nvidia-smi missing / unreadable). That must
# not be confused with "plenty free": the caller logs a WARN in that case.
function Test-LaotVramGate {
  [CmdletBinding()]
  param([int]$FreeMiB, [int]$NeedMiB)
  if ($NeedMiB -le 0) { return $true }
  if ($FreeMiB -lt 0) { return $true }
  return ($FreeMiB -ge $NeedMiB)
}

# --- rendering helpers ------------------------------------------------------------

# Build the llama-server argument list from a config object. Exposed so the self-test
# can prove that a validated config never produces an empty argument list.
function Format-LaotArgList {
  [CmdletBinding()]
  param($Config, [switch]$Sydney)
  if ($Sydney) {
    return @(
      '-m', [string]$Config.sydney.model,
      '--host', [string]$Config.sydney.host,
      '--port', [string]$Config.sydney.port,
      '--alias', [string]$Config.sydney.alias,
      '-c', [string]$Config.sydney.ctx,
      '--parallel', '1',
      '-ngl', [string]$Config.sydney.ngl
    )
  }
  return @(
    '-m', [string]$Config.model,
    '--host', [string]$Config.host,
    '--port', [string]$Config.port,
    '--alias', [string]$Config.alias,
    '-c', [string]$Config.ctx,
    '--parallel', [string]$Config.parallel,
    '-ngl', [string]$Config.ngl,
    '-fa', [string]$Config.fa
  )
}

Export-ModuleMember -Function @(
  'Read-LaotConfigText', 'Test-LaotJsonComment', 'Get-LaotFieldCount', 'Test-LaotIsScalar',
  'Test-LaotIsPositiveInt', 'Test-LaotIsPort', 'Test-LaotConfig', 'Resolve-LaotPath',
  'Select-LaotProcessIds', 'Test-LaotCommandLinePort', 'Get-LaotLlamaPortFromArgs',
  'Get-LaotSydneyCooldown', 'Test-LaotVramGate', 'Format-LaotArgList'
)
