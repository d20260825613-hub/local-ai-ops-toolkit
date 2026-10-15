<#
  LocalAI-Watchdog.ps1

  NOTE: this file is intentionally ASCII-only. Windows PowerShell 5.1 reads files
  without a BOM as ANSI, so non-ASCII text here would come out garbled.

  What it does
    1. After logon, starts the local llama.cpp model service (port 8080) and Chatbox.
    2. While a NON-AI game is running it stops the model service, so the whole 4 GB
       of VRAM belongs to the game. When the game is closed the service comes back.
       ("AI games" are listed in config.json under aiGameKeywords; those games use
        the local model, so the model keeps running for them.)
    3. While any game is in the foreground it pauses animated wallpapers
       (Wallpaper Engine / Lively) and restores them afterwards.
    4. While a game is running it drops the model service to BelowNormal CPU priority.

  Usage
    powershell -NoProfile -ExecutionPolicy Bypass -File D:\ai\LocalAI-Watchdog.ps1
    -Once     run one cycle and exit
    -DryRun   decide and log, but change nothing
    -Force    keep the AI running even when a game is detected
#>
[CmdletBinding()]
param(
  [switch]$Once,
  [switch]$DryRun,
  [switch]$Force
)

$Root      = 'D:\ai'
$CfgPath   = Join-Path $Root 'config.json'
$StatePath = Join-Path $Root 'state.json'
$LogDir    = Join-Path $Root 'logs'
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$LogPath = Join-Path $LogDir ('watchdog-{0}.log' -f (Get-Date -Format 'yyyyMMdd'))

function Write-Log {
  param([string]$Message, [string]$Level = 'INFO')
  $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
  try { Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 } catch { }
  Write-Host $line
}

if (-not (Test-Path -LiteralPath $CfgPath)) { Write-Log "config not found: $CfgPath" 'ERROR'; exit 1 }
try {
  $cfg = Get-Content -LiteralPath $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
  Write-Log "config parse failed: $($_.Exception.Message)" 'ERROR'
  exit 1
}

# --- housekeeping: drop old logs -------------------------------------------------
try {
  $cut = (Get-Date).AddDays(-1 * [int]$cfg.logKeepDays)
  Get-ChildItem -LiteralPath $LogDir -Filter '*.log' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt $cut } | Remove-Item -Force -ErrorAction SilentlyContinue
} catch { }

# --- foreground window helper ---------------------------------------------------
$script:HasFg = $false
try {
  if (-not ('Native.Fg' -as [type])) {
    Add-Type -Namespace Native -Name Fg -MemberDefinition @'
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, out uint lpdwProcessId);
'@
  }
  $script:HasFg = $true
} catch {
  Write-Log "foreground detection unavailable: $($_.Exception.Message)" 'WARN'
}

# --- state ----------------------------------------------------------------------
$script:State = [ordered]@{
  updated          = ''
  mode             = ''
  games            = @()
  otherGames       = @()
  foregroundGame   = $false
  aiRunning        = $false
  stoppedWallpapers = @()
}
if (Test-Path -LiteralPath $StatePath) {
  try {
    $prev = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($prev.stoppedWallpapers) { $script:State.stoppedWallpapers = @($prev.stoppedWallpapers) }
  } catch { }
}

function Save-State {
  try {
    $script:State.updated = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    ($script:State | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $StatePath -Encoding UTF8
  } catch { }
}

# --- process helpers ------------------------------------------------------------
function Get-ProcPath {
  param($Process)
  if (-not $Process) { return $null }
  $key = '{0}-{1}' -f $Process.Id, $Process.StartTime.Ticks
  if ($script:PathCache.ContainsKey($key)) { return $script:PathCache[$key] }
  $path = $null
  try { $path = $Process.Path } catch { }
  $script:PathCache[$key] = $path
  return $path
}
$script:PathCache = @{}

function Get-LlamaProcesses {
  return @(Get-Process -Name 'llama-server' -ErrorAction SilentlyContinue)
}

function Start-ChatboxApp {
  if (-not $cfg.startChatbox) { return }
  if (Get-Process -Name 'Chatbox' -ErrorAction SilentlyContinue) { return }
  if (-not (Test-Path -LiteralPath $cfg.chatbox)) { Write-Log "chatbox not found: $($cfg.chatbox)" 'WARN'; return }
  Write-Log 'start Chatbox'
  if ($DryRun) { return }
  try {
    Start-Process -FilePath $cfg.chatbox -WorkingDirectory (Split-Path -Parent $cfg.chatbox) | Out-Null
  } catch {
    Write-Log "Chatbox start failed: $($_.Exception.Message)" 'WARN'
  }
}

$script:LastAiStartAttempt = [datetime]::MinValue

function Get-SydneyProcesses {
  $sy = $cfg.sydney
  if (-not $sy -or -not $sy.enabled) { return @() }
  $needle = '*--port ' + [string]$sy.port + '*'
  return @(Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like $needle })
}

$script:LastSydneyStartAttempt = [datetime]::MinValue

function Get-GpuFreeMiB {
  try {
    $v = (& nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
    $n = 0
    if ([int]::TryParse(([string]$v).Trim(), [ref]$n)) { return $n }
  } catch { }
  return -1
}

function Stop-SydneyServer {
  $sy = $cfg.sydney
  if (-not $sy -or -not $sy.enabled) { return }
  $procs = @(Get-SydneyProcesses)
  if ($procs.Count -eq 0) { return }
  Write-Log ('stop sydney service ({0} process(es)) to free VRAM' -f $procs.Count)
  if ($DryRun) { return }
  foreach ($p in $procs) {
    try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop } catch { Write-Log "sydney stop failed: $($_.Exception.Message)" 'WARN' }
  }
  $script:LastSydneyStartAttempt = Get-Date
}

function Start-SydneyServer {
  $sy = $cfg.sydney
  if (-not $sy -or -not $sy.enabled) { return }
  if (@(Get-SydneyProcesses).Count -gt 0) { return }
  if (-not (Test-Path -LiteralPath $sy.model)) { Write-Log "sydney model not found: $($sy.model)" 'WARN'; return }
  if ($sy.minFreeMiB) {
    $free = Get-GpuFreeMiB
    if ($free -ge 0 -and $free -lt [int]$sy.minFreeMiB) {
      Write-Log ('sydney start deferred: only {0} MiB VRAM free, need {1} MiB' -f $free, [int]$sy.minFreeMiB)
      return
    }
  }
  $waited = ((Get-Date) - $script:LastSydneyStartAttempt).TotalSeconds
  if ($waited -lt [int]$cfg.aiStartCooldownSeconds) { return }
  $script:LastSydneyStartAttempt = Get-Date
  $argList = @(
    '-m', $sy.model,
    '--host', $sy.host,
    '--port', [string]$sy.port,
    '--alias', $sy.alias,
    '-c', [string]$sy.ctx,
    '--parallel', '1',
    '-ngl', [string]$sy.ngl
  )
  if ($sy.extraArgs) { $argList += @($sy.extraArgs) }
  Write-Log ('start sydney service on port {0} (ngl {1})' -f $sy.port, $sy.ngl)
  if ($DryRun) { return }
  $out = Join-Path $LogDir 'sydney-server.out.log'
  $err = Join-Path $LogDir 'sydney-server.err.log'
  try {
    Start-Process -FilePath $sy.exe -ArgumentList $argList `
      -WorkingDirectory (Split-Path -Parent $sy.exe) `
      -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err | Out-Null
  } catch {
    Write-Log "sydney service start failed: $($_.Exception.Message)" 'ERROR'
  }
}

function Start-AiStack {
  $waited = ((Get-Date) - $script:LastAiStartAttempt).TotalSeconds
  if ($waited -lt [int]$cfg.aiStartCooldownSeconds) {
    Write-Log ('start skipped, cooldown {0}s left' -f ([int]$cfg.aiStartCooldownSeconds - $waited))
    return
  }
  $script:LastAiStartAttempt = Get-Date
  $argList = @(
    '-m', $cfg.model,
    '--host', $cfg.host,
    '--port', [string]$cfg.port,
    '--alias', $cfg.alias,
    '-c', [string]$cfg.ctx,
    '--parallel', [string]$cfg.parallel,
    '-ngl', [string]$cfg.ngl,
    '-fa', $cfg.fa
  )
  if ($cfg.extraArgs) { $argList += @($cfg.extraArgs) }
  Write-Log ('start model service: {0} {1}' -f $cfg.llamaServer, ($argList -join ' '))
  if ($DryRun) { return }
  $out = Join-Path $LogDir 'llama-server.out.log'
  $err = Join-Path $LogDir 'llama-server.err.log'
  try {
    Start-Process -FilePath $cfg.llamaServer -ArgumentList $argList `
      -WorkingDirectory (Split-Path -Parent $cfg.llamaServer) `
      -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err | Out-Null
  } catch {
    Write-Log "model service start failed: $($_.Exception.Message)" 'ERROR'
    return
  }
  Start-ChatboxApp
  # wait until it answers on the port (max 120s)
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 2
    if (@(Get-LlamaProcesses).Count -eq 0) { Write-Log 'model service died during startup, see llama-server.err.log' 'ERROR'; return }
    if (Test-AiPort) { Write-Log 'model service is up on port ' + $cfg.port; break }
  }
  if (-not (Test-AiPort)) { Write-Log 'model service did not answer within 120s' 'WARN' }
  Start-SydneyServer
}

function Test-AiPort {
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    $iar = $c.BeginConnect('127.0.0.1', [int]$cfg.port, $null, $null)
    $ok = $iar.AsyncWaitHandle.WaitOne(500)
    $c.Close()
    return $ok
  } catch { return $false }
}

function Stop-AiStack {
  param([string]$Reason)
  $ps = Get-LlamaProcesses
  if ($ps.Count -eq 0) { return }
  Write-Log ("stop model service ({0}) - freeing VRAM for the game" -f $Reason)
  if ($DryRun) { return }
  foreach ($p in $ps) {
    try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { Write-Log "stop failed: $($_.Exception.Message)" 'WARN' }
  }
  if ($cfg.stopChatboxDuringGame) {
    foreach ($p in @(Get-Process -Name 'Chatbox' -ErrorAction SilentlyContinue)) {
      try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { }
    }
  }
}

function Set-AiPriority {
  param([string]$Level)
  foreach ($p in Get-LlamaProcesses) {
    try {
      if ($p.PriorityClass.ToString() -ne $Level) {
        Write-Log "model service priority -> $Level"
        if (-not $DryRun) { $p.PriorityClass = $Level }
      }
    } catch { }
  }
}

function Stop-Wallpapers {
  $stopped = @()
  foreach ($name in @($cfg.wallpaperProcessNames)) {
    foreach ($p in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
      $path = Get-ProcPath $p
      if ($path) { $stopped += $path }
      Write-Log ("pause wallpaper {0} (pid {1}) {2}" -f $p.ProcessName, $p.Id, $path)
      if ($DryRun) { continue }
      try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { Write-Log "wallpaper stop failed: $($_.Exception.Message)" 'WARN' }
    }
  }
  return $stopped
}

function Restore-Wallpapers {
  $keep = @()
  foreach ($path in @($script:State.stoppedWallpapers)) {
    if (-not $path) { continue }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($path)
    if (Get-Process -Name $name -ErrorAction SilentlyContinue) { continue }
    if (-not (Test-Path -LiteralPath $path)) { continue }
    Write-Log "restore wallpaper: $path"
    if ($DryRun) { continue }
    try { Start-Process -FilePath $path | Out-Null } catch { Write-Log "wallpaper restore failed: $($_.Exception.Message)" 'WARN'; $keep += $path }
  }
  $script:State.stoppedWallpapers = @($keep)
  Save-State
}

# --- one decision cycle ---------------------------------------------------------
$script:CycleCount = 0
$script:LastMode = ''

function Invoke-Cycle {
  $script:CycleCount++
  $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
  $games = @(); $otherGames = @(); $aiGames = @()

  foreach ($p in $all) {
    $name = [string]$p.Name
    if ($name -match '\.exe$') { $name = $name.Substring(0, $name.Length - 4) }
    if (@($cfg.gameExcludeNames) -contains $name) { continue }
    $path = [string]$p.ExecutablePath
    if (-not $path) { continue }
    $skip = $false
    foreach ($k in @($cfg.gameExcludeKeywords)) { if ($path -like "*$k*") { $skip = $true; break } }
    if ($skip) { continue }

    $isGame = $false
    if (@($cfg.gameExeNames) -contains $name) { $isGame = $true }
    if (-not $isGame) { foreach ($k in @($cfg.gamePathKeywords)) { if ($path -like "*$k*") { $isGame = $true; break } } }
    if (-not $isGame) { continue }

    $needsAi = $false
    if (@($cfg.aiGameExeNames) -contains $name) { $needsAi = $true }
    if (-not $needsAi) { foreach ($k in @($cfg.aiGameKeywords)) { if ($path -like "*$k*") { $needsAi = $true; break } } }

    if ($needsAi) { $aiGames += $p } else { $otherGames += $p }
    $games += $p
  }

  # foreground window
  $fgPid = 0
  if ($script:HasFg) {
    try {
      $h = [Native.Fg]::GetForegroundWindow()
      if ($h -ne [System.IntPtr]::Zero) {
        $tmp = [uint32]0
        [void][Native.Fg]::GetWindowThreadProcessId($h, [ref]$tmp)
        $fgPid = [int]$tmp
      }
    } catch { }
  }
  $fgIsGame = $false
  foreach ($g in $games) { if ([int]$g.ProcessId -eq $fgPid) { $fgIsGame = $true; break } }

  $aiRunning = (@($all | Where-Object { $_.Name -eq 'llama-server.exe' -and $_.CommandLine -and $_.CommandLine -like ('*--port ' + [string]$cfg.port + '*') }).Count -gt 0)
  $aiShouldRun = $true
  if ($cfg.pauseAiWhenOtherGameRuns -and $otherGames.Count -gt 0) { $aiShouldRun = $false }
  if ($Force) { $aiShouldRun = $true }

  $mode = 'AI-ON'
  if (-not $aiShouldRun) { $mode = 'AI-OFF(GAME)' }
  if ($Force) { $mode = $mode + '+FORCED' }

  # --- act ---------------------------------------------------------------------
  if ($aiShouldRun -and -not $aiRunning) {
    Start-AiStack
  } elseif ((-not $aiShouldRun) -and $aiRunning) {
    $names = (@($otherGames | ForEach-Object { $_.Name }) | Select-Object -Unique) -join ','
    Stop-AiStack "game: $names"
  }

  # an "AI game" in the FOREGROUND (the Lilith mod) uses the 8080 model and needs the
  # VRAM: park Sydney. A background Lilith process alone must not block Sydney.
  if ($aiGames.Count -gt 0 -and $fgIsGame) {
    Stop-SydneyServer
  } elseif ($aiShouldRun) {
    Start-SydneyServer
  }

  if ($cfg.lowerAiPriorityDuringGame) {
    if ($games.Count -gt 0) { Set-AiPriority 'BelowNormal' } else { Set-AiPriority 'Normal' }
  }

  $pauseWp = ($cfg.pauseWallpaperDuringGame -and $fgIsGame -and -not $Force)
  if ($pauseWp) {
    $stopped = Stop-Wallpapers
    if ($stopped.Count -gt 0) {
      $script:State.stoppedWallpapers = @(@($script:State.stoppedWallpapers) + $stopped | Select-Object -Unique)
      Save-State
    }
  } else {
    Restore-Wallpapers
  }

  # --- report ------------------------------------------------------------------
  $gameNamesArr = @($games | ForEach-Object { $_.Name } | Select-Object -Unique)
  $otherNamesArr = @($otherGames | ForEach-Object { $_.Name } | Select-Object -Unique)
  $gameNames = $gameNamesArr -join ','
  $otherNames = $otherNamesArr -join ','
  $line = 'mode={0} games=[{1}] otherGames=[{2}] fgGame={3} running={4}' -f $mode, $gameNames, $otherNames, $fgIsGame, $aiRunning

  $script:State.mode = $mode
  $script:State.games = $gameNamesArr
  $script:State.otherGames = $otherNamesArr
  $script:State.foregroundGame = $fgIsGame
  $script:State.aiRunning = $aiRunning
  Save-State

  if ($line -ne $script:LastMode) {
    Write-Log $line
    $script:LastMode = $line
  } elseif (($script:CycleCount % 180) -eq 0) {
    Write-Log ('heartbeat: ' + $line)
  }
}

# --- main ----------------------------------------------------------------------
Write-Log ('watchdog starting (dryRun={0} force={1} once={2}) pid={3}' -f [bool]$DryRun, [bool]$Force, [bool]$Once, $PID)

if (-not $Once -and [int]$cfg.startupDelaySeconds -gt 0) {
  Write-Log ('waiting {0}s for logon to settle' -f $cfg.startupDelaySeconds)
  Start-Sleep -Seconds ([int]$cfg.startupDelaySeconds)
}

while ($true) {
  try { Invoke-Cycle } catch { Write-Log "cycle error: $($_.Exception.Message)" 'ERROR' }
  if ($Once) { break }
  Start-Sleep -Seconds ([int]$cfg.pollSeconds)
}
Write-Log 'watchdog exit'
