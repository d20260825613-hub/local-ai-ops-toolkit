# tools/portfilter.ps1
#
# Find (and optionally stop) the llama-server that serves ONE port.
#
# Why this exists: the watchdog owns one llama-server per port (the main model port
# and the Sydney port). Selecting by process name ("taskkill /IM llama-server.exe")
# or by a substring match on the command line stops BOTH services - and any other
# llama-server the user started by hand - which is the opposite of what the README
# promises. The port is matched as a whole argument, so "--port 8080" does not match
# a process running "--port 80801".
#
# Used by AI-Stop.cmd. Safe by design: -List only reports, and stopping requires the
# caller to pass -Stop.
[CmdletBinding()]
param(
  [int]$Port = 8080,
  # read the main port from a config.json (default: next to this script, then D:\ai)
  [string]$ConfigPath,
  [switch]$List,
  [switch]$Stop
)

$ErrorActionPreference = 'Continue'

if (-not $ConfigPath) {
  $candidates = @((Join-Path (Split-Path -Parent $PSScriptRoot) 'config.json'), (Join-Path $PSScriptRoot 'config.json'), 'D:\ai\config.json')
  foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { $ConfigPath = $c; break } }
}
if ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath)) {
  try {
    $cfgPort = (Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json).port
    if ($cfgPort) { $Port = [int]$cfgPort }
  } catch { }
}

$pattern = '(?i)--port[ =]+' + $Port + '(?![0-9])'
$procs = @(Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match $pattern })

if ($procs.Count -eq 0) {
  Write-Host ('Model service on port {0} is not running.' -f $Port)
  exit 0
}

if ($List -or -not $Stop) {
  foreach ($p in $procs) {
    Write-Host ('would stop pid {0} (port {1}): {2}' -f $p.ProcessId, $Port, $p.CommandLine)
  }
  exit 0
}

foreach ($p in $procs) {
  try {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
    Write-Host ('stopped model service (pid {0}, port {1})' -f $p.ProcessId, $Port)
  } catch {
    Write-Host ('stop failed for pid {0}: {1}' -f $p.ProcessId, $_.Exception.Message)
  }
}
exit 0
