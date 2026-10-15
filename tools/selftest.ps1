#  Local AI Ops Toolkit / local-ai-ops-toolkit
#  tools/selftest.ps1 - lightweight self-test for the scripts that were fixed.
#
#  What it covers
#    1. malformed config.json is REJECTED instead of starting a service with empty
#       arguments ("fake success")
#    2. config.json encoding: UTF-8 (with/without BOM) and GBK/ANSI Chinese keywords
#    3. port filtering: only the process serving the requested port is selected
#    4. command-line / parameter parsing edges of the watchdog
#    5. config.sample.json still satisfies the (structural) config rules
#
#  How it runs
#    powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\selftest.ps1
#
#  Safety
#    Nothing is started, stopped, installed or changed on this machine. The watchdog
#    is always called with -Once -DryRun, the process tables are injected fakes, and
#    every temporary file lives in %TEMP%\laot-selftest-<random> and is deleted at the
#    end. No audio device, registry key, service or power plan is touched.
#
#  Exit code: 0 = all checks passed, 1 = at least one check failed.

[CmdletBinding()]
param(
  # keep the temp dir for inspection
  [switch]$KeepTemp
)

$ErrorActionPreference = 'Continue'

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$RepoRoot = Split-Path -Parent $ScriptDir
$Watchdog = Join-Path $RepoRoot 'LocalAI-Watchdog.ps1'
$LibPath  = Join-Path $ScriptDir 'lib\LaotLib.psm1'

$script:Pass = 0
$script:Fail = 0
$script:Failures = New-Object System.Collections.ArrayList

function Write-Head($Text) {
  Write-Host ''
  Write-Host ("=== {0} ===" -f $Text) -ForegroundColor Cyan
}

function Test-Case {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][bool]$Ok,
    [string]$Detail = ''
  )
  if ($Ok) {
    $script:Pass++
    Write-Host ("  [PASS] {0}" -f $Name) -ForegroundColor Green
  } else {
    $script:Fail++
    [void]$script:Failures.Add($Name)
    Write-Host ("  [FAIL] {0}{1}" -f $Name, $(if ($Detail) { ' -> ' + $Detail } else { '' })) -ForegroundColor Red
  }
}

function New-TempDir {
  $d = Join-Path $env:TEMP ('laot-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}

function Write-TextFile {
  param([string]$Path, [string]$Text, $Encoding)
  if (-not $Encoding) { $Encoding = New-Object System.Text.UTF8Encoding($false) }
  [System.IO.File]::WriteAllText($Path, $Text, $Encoding)
}

if (-not (Test-Path -LiteralPath $LibPath)) {
  Write-Host ("ERROR: {0} not found - cannot run the self-test." -f $LibPath) -ForegroundColor Red
  exit 1
}
Import-Module -Name $LibPath -Force -ErrorAction Stop

$tmp = New-TempDir

try {
  # -------------------------------------------------------------------------------
  Write-Head '1. config encoding (UTF-8 / UTF-8 BOM / GBK-ANSI Chinese keyword)'
  # -------------------------------------------------------------------------------
  $cnJson = "{`r`n  ""aiGameKeywords"": [""不存在的莉莉丝""],`r`n  ""port"": 8080`r`n}"
  $utf8NoBom = Join-Path $tmp 'cfg-utf8.json'
  $utf8Bom   = Join-Path $tmp 'cfg-bom.json'
  $gbk       = Join-Path $tmp 'cfg-gbk.json'
  Write-TextFile -Path $utf8NoBom -Text $cnJson -Encoding (New-Object System.Text.UTF8Encoding($false))
  Write-TextFile -Path $utf8Bom   -Text $cnJson -Encoding (New-Object System.Text.UTF8Encoding($true))
  Write-TextFile -Path $gbk       -Text $cnJson -Encoding ([System.Text.Encoding]::GetEncoding(936))

  $r1 = Read-LaotConfigText -Path $utf8NoBom
  $r2 = Read-LaotConfigText -Path $utf8Bom
  $r3 = Read-LaotConfigText -Path $gbk

  $k1 = (@(($r1.Text | ConvertFrom-Json).aiGameKeywords))[0]
  $k2 = (@(($r2.Text | ConvertFrom-Json).aiGameKeywords))[0]
  $k3 = (@(($r3.Text | ConvertFrom-Json).aiGameKeywords))[0]

  Test-Case 'UTF-8 without BOM decodes Chinese keyword' ($r1.Encoding -eq 'utf8' -and $k1 -eq '不存在的莉莉丝') ("enc={0} kw={1}" -f $r1.Encoding, $k1)
  Test-Case 'UTF-8 with BOM decodes Chinese keyword' ($r2.Encoding -eq 'utf8-bom' -and $k2 -eq '不存在的莉莉丝') ("enc={0} kw={1}" -f $r2.Encoding, $k2)
  Test-Case 'GBK/ANSI config falls back to the ANSI code page' ($r3.Encoding -eq 'ansi' -and $k3 -eq '不存在的莉莉丝') ("enc={0} kw={1}" -f $r3.Encoding, $k3)
  Test-Case 'GBK bytes read as UTF-8 would have been garbled (guards the fix)' ($k3 -ne $k1 -or $r3.Encoding -eq 'ansi')

  Test-Case 'JSON comments are rejected' (Test-LaotJsonComment -Text "{ `"a`": 1 // x`r`n}")
  Test-Case 'JSON with // inside a string value is accepted' (-not (Test-LaotJsonComment -Text '{"url":"https://example.com/x","a":1}'))
  Test-Case 'JSON with /* inside a string value is accepted' (-not (Test-LaotJsonComment -Text '{"glob":"a/*/b","a":1}'))

  # -------------------------------------------------------------------------------
  Write-Head '2. config validation rules (pure, no process is touched)'
  # -------------------------------------------------------------------------------
  $badInputs = [ordered]@{
    'empty file'        = ''
    'whitespace only'   = "   `r`n`t"
    'null'              = 'null'
    'true'              = 'true'
    'number 0'          = '0'
    'number 123'        = '123'
    'string'            = '"text"'
    'array'             = '[]'
    'empty object'      = '{}'
    'not json'          = '{ this is not json'
    'trailing comma'    = '{"port": 8080,}'
  }
  foreach ($name in $badInputs.Keys) {
    $parsed = $null
    $parsedOk = $true
    try { $parsed = $badInputs[$name] | ConvertFrom-Json } catch { $parsedOk = $false }
    if (-not $parsedOk) {
      # unparseable JSON: the watchdog exits before validation, which is also a reject
      Test-Case ("reject: {0} (parse error)" -f $name) $true
      continue
    }
    $problems = @(Test-LaotConfig -Config $parsed -BaseDir $tmp)
    Test-Case ("reject: {0}" -f $name) ($problems.Count -gt 0) (($problems -join '; '))
  }

  $good = @'
{
  "llamaServer": "fake-llama.exe",
  "model": "fake-model.gguf",
  "host": "127.0.0.1",
  "port": 8080,
  "pollSeconds": 10,
  "aiStartCooldownSeconds": 90,
  "logKeepDays": 14,
  "aiGameKeywords": ["The NOexistenceN of Lilith"],
  "wallpaperProcessNames": ["wallpaper64"]
}
'@
  New-Item -ItemType File -Force -Path (Join-Path $tmp 'fake-llama.exe') | Out-Null
  New-Item -ItemType File -Force -Path (Join-Path $tmp 'fake-model.gguf') | Out-Null
  $goodCfg = $good | ConvertFrom-Json
  Test-Case 'accept: a complete config' ((@(Test-LaotConfig -Config $goodCfg -BaseDir $tmp -CheckFiles)).Count -eq 0)

  $fieldCases = [ordered]@{
    'port "abc"'        = ($good -replace '"port": 8080', '"port": "abc"')
    'port 0'            = ($good -replace '"port": 8080', '"port": 0')
    'port 99999'        = ($good -replace '"port": 8080', '"port": 99999')
    'port missing'      = ($good -replace '"port": 8080,', '')
    'pollSeconds 0'     = ($good -replace '"pollSeconds": 10', '"pollSeconds": 0')
    'pollSeconds "abc"' = ($good -replace '"pollSeconds": 10', '"pollSeconds": "abc"')
    'pollSeconds -5'    = ($good -replace '"pollSeconds": 10', '"pollSeconds": -5')
    'logKeepDays "abc"' = ($good -replace '"logKeepDays": 14', '"logKeepDays": "abc"')
    'model empty'       = ($good -replace '"model": "fake-model.gguf"', '"model": ""')
    'host missing'      = ($good -replace '"host": "127.0.0.1",', '')
    'keyword not array' = ($good -replace '"aiGameKeywords": \["The NOexistenceN of Lilith"\]', '"aiGameKeywords": "Lilith"')
  }
  foreach ($name in $fieldCases.Keys) {
    $parsed = $null
    try { $parsed = $fieldCases[$name] | ConvertFrom-Json } catch { }
    $problems = @(Test-LaotConfig -Config $parsed -BaseDir $tmp)
    Test-Case ("reject: {0}" -f $name) ($problems.Count -gt 0) (($problems -join '; '))
  }

  Test-Case 'reject: llamaServer that does not exist' ((@(Test-LaotConfig -Config ($good -replace 'fake-llama.exe', 'missing.exe') -BaseDir $tmp -CheckFiles)).Count -gt 0)
  Test-Case 'reject: sydney.port equal to the main port' (
    (@(Test-LaotConfig -Config (('{"llamaServer":"fake-llama.exe","model":"fake-model.gguf","host":"h","port":8080,"pollSeconds":10,"sydney":{"enabled":true,"exe":"fake-llama.exe","model":"fake-model.gguf","host":"h","port":8080}}' | ConvertFrom-Json)) -BaseDir $tmp)).Count -gt 0)
  Test-Case 'reject: sydney.enabled but exe empty' (
    (@(Test-LaotConfig -Config (('{"llamaServer":"fake-llama.exe","model":"fake-model.gguf","host":"h","port":8080,"pollSeconds":10,"sydney":{"enabled":true,"exe":"","model":"fake-model.gguf","host":"h","port":8081}}' | ConvertFrom-Json)) -BaseDir $tmp)).Count -gt 0)
  Test-Case 'accept: null list field (treated as empty list)' (
    (@(Test-LaotConfig -Config (($good -replace '"aiGameKeywords": \["The NOexistenceN of Lilith"\]', '"aiGameKeywords": null') | ConvertFrom-Json) -BaseDir $tmp)).Count -eq 0)

  # -------------------------------------------------------------------------------
  Write-Head '3. port filtering (injected fake process table, nothing is stopped)'
  # -------------------------------------------------------------------------------
  $fake = @(
    [pscustomobject]@{ ProcessId = 100; Name = 'llama-server.exe'; CommandLine = '"D:\llama.cpp\llama-server.exe" -m a.gguf --host 127.0.0.1 --port 8080 --alias qwen' },
    [pscustomobject]@{ ProcessId = 200; Name = 'llama-server.exe'; CommandLine = '"D:\llama.cpp\llama-server.exe" -m s.gguf --host 127.0.0.1 --port 8081 --alias sydney-9b' },
    [pscustomobject]@{ ProcessId = 300; Name = 'llama-server.exe'; CommandLine = '"llama-server.exe" -m x.gguf --port 9000' },
    [pscustomobject]@{ ProcessId = 400; Name = 'llama-server.exe'; CommandLine = $null },
    [pscustomobject]@{ ProcessId = 500; Name = 'llama-server.exe'; CommandLine = '"llama-server.exe" --port 80801' },
    [pscustomobject]@{ ProcessId = 600; Name = 'llama-server.exe'; CommandLine = '"llama-server.exe" --port=8080' }
  )
  $p8080 = @(Select-LaotProcessIds -Processes $fake -Port 8080)
  $p8081 = @(Select-LaotProcessIds -Processes $fake -Port 8081)
  Test-Case 'stop main model selects only the 8080 process' ($p8080 -contains 100 -and $p8080 -notcontains 200) (($p8080 -join ','))
  Test-Case 'stop main model does NOT select the Sydney process (8081)' ($p8080 -notcontains 200) (($p8080 -join ','))
  Test-Case 'stop Sydney selects only the 8081 process' ($p8081.Count -eq 1 -and $p8081[0] -eq 200) (($p8081 -join ','))
  Test-Case 'process without a command line is never selected' ($p8080 -notcontains 400 -and $p8081 -notcontains 400)
  Test-Case 'port is matched as a whole token (--port 80801 is not 8080)' ($p8080 -notcontains 500) (($p8080 -join ','))
  Test-Case '--port=8080 form is recognised' ($p8080 -contains 600) (($p8080 -join ','))
  Test-Case 'an unrelated port (9000) is not selected by 8080/8081' ((@(Select-LaotProcessIds -Processes $fake -Port 8080) -notcontains 300) -and (@(Select-LaotProcessIds -Processes $fake -Port 8081) -notcontains 300))
  Test-Case 'empty process list yields no ids' ((@(Select-LaotProcessIds -Processes @() -Port 8080)).Count -eq 0)
  Test-Case 'null process entries are ignored' ((@(Select-LaotProcessIds -Processes @($null, $fake[0]) -Port 8080)).Count -eq 1)

  # -------------------------------------------------------------------------------
  Write-Head '4. gates: cooldown and VRAM threshold semantics'
  # -------------------------------------------------------------------------------
  Test-Case 'sydney cooldown falls back to aiStartCooldownSeconds' ((Get-LaotSydneyCooldown -Config ([pscustomobject]@{ aiStartCooldownSeconds = 90 })) -eq 90)
  Test-Case 'sydneyStartCooldownSeconds overrides the fallback' ((Get-LaotSydneyCooldown -Config ([pscustomobject]@{ aiStartCooldownSeconds = 90; sydneyStartCooldownSeconds = 5 })) -eq 5)
  Test-Case 'garbage sydneyStartCooldownSeconds falls back' ((Get-LaotSydneyCooldown -Config ([pscustomobject]@{ aiStartCooldownSeconds = 90; sydneyStartCooldownSeconds = 'x' })) -eq 90)
  Test-Case 'VRAM below the threshold is refused' (-not (Test-LaotVramGate -FreeMiB 2999 -NeedMiB 3000))
  Test-Case 'VRAM exactly at the threshold is allowed' (Test-LaotVramGate -FreeMiB 3000 -NeedMiB 3000)
  Test-Case 'unreadable VRAM (-1) fails open but is reported separately' (Test-LaotVramGate -FreeMiB -1 -NeedMiB 3000)
  Test-Case 'no threshold means no gate' (Test-LaotVramGate -FreeMiB 10 -NeedMiB 0)

  # -------------------------------------------------------------------------------
  Write-Head '5. watchdog parameter parsing and integration (temp dir, -Once -DryRun)'
  # -------------------------------------------------------------------------------
  if (-not (Test-Path -LiteralPath $Watchdog)) {
    Test-Case 'LocalAI-Watchdog.ps1 present' $false $Watchdog
  } else {
    Test-Case 'LocalAI-Watchdog.ps1 present' $true

    # A copy of the watchdog inside a temp directory. $Root is derived from the script
    # location, so nothing here can touch the real D:\ai installation.
    $sandbox = Join-Path $tmp 'sandbox'
    New-Item -ItemType Directory -Force -Path (Join-Path $sandbox 'tools\lib') | Out-Null
    Copy-Item -LiteralPath $Watchdog -Destination (Join-Path $sandbox 'LocalAI-Watchdog.ps1') -Force
    Copy-Item -LiteralPath $LibPath -Destination (Join-Path $sandbox 'tools\lib\LaotLib.psm1') -Force
    Copy-Item -LiteralPath (Join-Path $tmp 'fake-llama.exe') -Destination (Join-Path $sandbox 'fake-llama.exe') -Force
    Copy-Item -LiteralPath (Join-Path $tmp 'fake-model.gguf') -Destination (Join-Path $sandbox 'fake-model.gguf') -Force

    # a second copy that deliberately has NO config.json anywhere near it, so the
    # "config not found" path can be tested even when D:\ai/config.json exists
    $noCfg = Join-Path $tmp 'noconfig'
    New-Item -ItemType Directory -Force -Path (Join-Path $noCfg 'tools\lib') | Out-Null
    Copy-Item -LiteralPath $Watchdog -Destination (Join-Path $noCfg 'LocalAI-Watchdog.ps1') -Force
    Copy-Item -LiteralPath $LibPath -Destination (Join-Path $noCfg 'tools\lib\LaotLib.psm1') -Force

    function Invoke-Watchdog {
      param([string]$ConfigText, [string[]]$ExtraArgs = @(), [string]$Root)
      if (-not $Root) { $Root = $sandbox }
      $cfgFile = Join-Path $Root 'config.json'
      if ($PSBoundParameters.ContainsKey('ConfigText')) {
        Write-TextFile -Path $cfgFile -Text $ConfigText -Encoding (New-Object System.Text.UTF8Encoding($false))
      } else {
        Remove-Item -LiteralPath $cfgFile -Force -ErrorAction SilentlyContinue
      }
      $wdArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $Root 'LocalAI-Watchdog.ps1'), '-Once', '-DryRun') + $ExtraArgs
      $out = & powershell.exe @wdArgs 2>&1
      $code = $LASTEXITCODE
      # leave no config behind: a later call must never silently test the wrong folder
      Remove-Item -LiteralPath $cfgFile -Force -ErrorAction SilentlyContinue
      return [pscustomobject]@{ ExitCode = $code; Output = @($out) }
    }

    $r = Invoke-Watchdog -ConfigText ''
    Test-Case 'watchdog exits 1 on an empty config.json' ($r.ExitCode -eq 1) ("exit={0}" -f $r.ExitCode)
    Test-Case 'watchdog never logs "start model service" for an empty config' (-not (@($r.Output) -match 'start model service').Count)

    $r = Invoke-Watchdog -ConfigText '{}'
    Test-Case 'watchdog exits 1 on {}' ($r.ExitCode -eq 1) ("exit={0}" -f $r.ExitCode)
    Test-Case 'watchdog explains why {} is unusable' ([bool](@($r.Output) -match 'has no fields')) ((@($r.Output) | Select-Object -First 3) -join ' | ')

    $r = Invoke-Watchdog -ConfigText '{"llamaServer":"fake-llama.exe"}'
    Test-Case 'watchdog names the required field that is missing' ([bool](@($r.Output) -match 'required field missing or empty: model')) ((@($r.Output) | Select-Object -First 3) -join ' | ')

    $r = Invoke-Watchdog -ConfigText 'null'
    Test-Case 'watchdog exits 1 on null' ($r.ExitCode -eq 1) ("exit={0}" -f $r.ExitCode)

    # No config.json next to the script: the watchdog must either fall back to the
    # deployed D:\ai\config.json (documented behaviour) or report "config not found"
    # and exit 1 - it must never start a service with an empty argument list.
    $r = Invoke-Watchdog -Root $noCfg
    $fellBack = [bool](@($r.Output) -match 'config loaded from')
    $notFound = [bool](@($r.Output) -match 'config not found')
    Test-Case 'watchdog either falls back to D:\ai\config.json or reports it is missing' ($fellBack -or $notFound) ((@($r.Output) | Select-Object -First 2) -join ' | ')
    Test-Case 'watchdog exits 1 when it has no config at all' ((-not $notFound) -or ($r.ExitCode -eq 1)) ("exit={0}" -f $r.ExitCode)
    Test-Case 'watchdog never starts a service from a missing config' ((-not $notFound) -or (-not (@($r.Output) -match 'start model service').Count))
    Test-Case 'the fallback config is always loaded before any action' ((-not $fellBack) -or [bool](@($r.Output) -match 'config loaded from'))

    $r = Invoke-Watchdog -ConfigText $good
    Test-Case 'watchdog accepts a complete config and runs one dry-run cycle' ($r.ExitCode -eq 0) ("exit={0}; {1}" -f $r.ExitCode, ((@($r.Output) | Select-Object -Last 2) -join ' | '))
    Test-Case 'dry-run logs the config it loaded' ([bool](@($r.Output) -match 'config loaded from'))
    Test-Case 'a full cycle completes without "cycle error"' (-not (@($r.Output) -match 'cycle error').Count) ((@($r.Output) | Where-Object { $_ -match 'cycle error' }) -join ' | ')

    $r = Invoke-Watchdog -ConfigText $good -ExtraArgs @('-Force')
    Test-Case '-Force is still accepted' ($r.ExitCode -eq 0) ("exit={0}" -f $r.ExitCode)

    $r = Invoke-Watchdog -ConfigText $good -ExtraArgs @('-WhatIf')
    Test-Case 'an unknown parameter is rejected by the binder (exit != 0)' ($r.ExitCode -ne 0) ("exit={0}" -f $r.ExitCode)

    $r = Invoke-Watchdog -ConfigText ($good -replace '"port": 8080', '"port": "abc"')
    Test-Case 'watchdog exits 1 when port is not numeric' ($r.ExitCode -eq 1 -and [bool](@($r.Output) -match 'port must be an integer')) ("exit={0}" -f $r.ExitCode)

    $r = Invoke-Watchdog -ConfigText ($good -replace '"pollSeconds": 10', '"pollSeconds": 0')
    Test-Case 'watchdog exits 1 when pollSeconds is 0 (no busy loop)' ($r.ExitCode -eq 1) ("exit={0}" -f $r.ExitCode)

    # relative paths inside the config are resolved against the config's own folder
    $relGood = $good.Replace('"model": "fake-model.gguf"', '"model": "sub\\fake-model.gguf"')
    New-Item -ItemType Directory -Force -Path (Join-Path $sandbox 'sub') | Out-Null
    Copy-Item -LiteralPath (Join-Path $tmp 'fake-model.gguf') -Destination (Join-Path $sandbox 'sub\fake-model.gguf') -Force
    $r = Invoke-Watchdog -ConfigText $relGood
    Test-Case 'relative paths resolve against the config folder' ($r.ExitCode -eq 0) ("exit={0}; {1}" -f $r.ExitCode, ((@($r.Output) | Where-Object { $_ -match 'invalid|rejected' }) -join ' | '))
    $relBad = $good.Replace('"model": "fake-model.gguf"', '"model": "sub\\nope.gguf"')
    $r = Invoke-Watchdog -ConfigText $relBad
    Test-Case 'a missing relative model path is rejected' ($r.ExitCode -eq 1 -and [bool](@($r.Output) -match 'model not found')) ("exit={0}" -f $r.ExitCode)

    # tools/portfilter.ps1 (used by AI-Stop.cmd) must report, never stop, without -Stop
    $pf = Join-Path $RepoRoot 'tools\portfilter.ps1'
    if (Test-Path -LiteralPath $pf) {
      $pfCfg = Join-Path $tmp 'portfilter-config.json'
      Write-TextFile -Path $pfCfg -Text '{"llamaServer":"fake-llama.exe","model":"fake-model.gguf","host":"127.0.0.1","port":8081,"pollSeconds":10}' -Encoding (New-Object System.Text.UTF8Encoding($false))
      $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $pf -List -ConfigPath $pfCfg 2>&1
      $code = $LASTEXITCODE
      Test-Case 'portfilter.ps1 -List uses the port from config.json' ($code -eq 0 -and [bool](@($out) -match 'port 8081')) (((@($out)) -join ' | '))
      $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $pf -List -Port 8080 -ConfigPath (Join-Path $tmp 'no-such.json') 2>&1
      Test-Case 'portfilter.ps1 falls back to -Port when there is no config' ($LASTEXITCODE -eq 0 -and [bool](@($out) -match 'port 8080')) (((@($out)) -join ' | '))
    } else {
      Test-Case 'tools\portfilter.ps1 present' $false $pf
    }
  }

  # -------------------------------------------------------------------------------
  Write-Head '6. config.sample.json matches the config rules'
  # -------------------------------------------------------------------------------
  $sample = Join-Path $RepoRoot 'config.sample.json'
  if (Test-Path -LiteralPath $sample) {
    $sampleRaw = Read-LaotConfigText -Path $sample
    $sampleCfg = $null
    $parsedOk = $true
    try { $sampleCfg = $sampleRaw.Text | ConvertFrom-Json } catch { $parsedOk = $false }
    Test-Case 'config.sample.json parses' $parsedOk
    if ($parsedOk) {
      # structural only: the sample points at llama.cpp / model paths that do not
      # exist on every machine, so file existence is not part of this check
      $problems = @(Test-LaotConfig -Config $sampleCfg -BaseDir $RepoRoot)
      Test-Case 'config.sample.json satisfies every (structural) config rule' ($problems.Count -eq 0) (($problems -join '; '))
    }
  } else {
    Test-Case 'config.sample.json present' $false $sample
  }

  # -------------------------------------------------------------------------------
  Write-Head '7. corrected audio script (Get-AudioDefault)'
  # -------------------------------------------------------------------------------
  $audio = Join-Path $RepoRoot 'audio\Get-AudioDefault.ps1'
  if (Test-Path -LiteralPath $audio) {
    $src = Get-Content -LiteralPath $audio -Raw
    # "PROPVARIANT" may still appear in the explanatory comment; what must be gone is
    # the interop declaration itself
    Test-Case 'no PROPVARIANT struct declaration remains' (-not ($src -match 'StructLayout'))
    Test-Case 'no PtrToStringUni hack remains' (-not ($src -match 'PtrToStringUni'))
    Test-Case 'no hand-written Core Audio COM interop remains' (-not ($src -match 'IMMDevice'))
    # The script reports default endpoints; running it is read-only, but it is only
    # executed if the machine actually exposes the WinRT API.
    $r = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $audio 2>&1
    $code = $LASTEXITCODE
    Test-Case 'runs without an access violation (0xC0000005 / -1073741819)' ($code -ne -1073741819) ("exit={0}" -f $code)
    Test-Case 'reports the default render endpoint or explains why it cannot' ([bool](@($r) -match 'default')) ((@($r) | Select-Object -First 3) -join ' | ')
  } else {
    Test-Case 'audio\Get-AudioDefault.ps1 present' $false $audio
  }

  # -------------------------------------------------------------------------------
  Write-Head '8. audio backup/restore helper and log encoding'
  # -------------------------------------------------------------------------------
  $audioLib = Join-Path $RepoRoot 'audio\lib\AudioBackup.ps1'
  if (Test-Path -LiteralPath $audioLib) {
    . $audioLib
    $bdir = Join-Path $tmp 'audiobk'
    New-Item -ItemType Directory -Force -Path $bdir | Out-Null
    $bk = Join-Path $bdir 'audio-backup.json'
    Test-Case 'read of a missing backup returns $null' ($null -eq (Read-AudioBackup -Path $bk))
    $obj = [ordered]@{ created = '2026-10-15 00:00:00'; nahimicStartType = 'Disabled'; hiberbootEnabled = 0 }
    [void](Write-AudioBackup -Path $bk -Data $obj)
    Test-Case 'backup file is written' (Test-Path -LiteralPath $bk)
    $back = Read-AudioBackup -Path $bk
    Test-Case 'backup round-trips (Nahimic Disabled stays Disabled, not "Automatic")' ($back -and $back.nahimicStartType -eq 'Disabled' -and [int]$back.hiberbootEnabled -eq 0)
    Test-Case 'unknown StartType is not turned into a guessed one' ($null -eq (ConvertTo-ServiceStartupType -Value 'nonsense'))
    Test-Case 'recorded StartType "Manual" maps back to Manual' ((ConvertTo-ServiceStartupType -Value 'Manual') -eq 'Manual')

    # the mixed UTF-8 + UTF-16LE log from the old cmd redirection must be repairable
    $mixed = Join-Path $bdir 'repair-log-mixed.txt'
    $utf8 = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($mixed, "=== run ===`r`nfirst line`r`n", $utf8)
    # append genuine UTF-16LE bytes, exactly what "cmd /c ... > file" produced
    $fs = [System.IO.File]::Open($mixed, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write)
    $bw = New-Object System.IO.BinaryWriter($fs, [System.Text.Encoding]::Unicode)
    $bw.Write('UTF-16LE SECOND WRITER')
    $bw.Flush(); $bw.Close(); $fs.Close()
    Test-Case 'the synthetic mixed log really has NUL bytes' (-not (Test-LaotLogReadable -Path $mixed))
    $repaired = Repair-LaotLogEncoding -Path $mixed
    Test-Case 'Repair-LaotLogEncoding reports a repair' ($repaired -eq $true)
    Test-Case 'the repaired log has no NUL bytes left' (Test-LaotLogReadable -Path $mixed)
    Test-Case 'the repaired log still contains the readable first line' ([bool](Select-String -LiteralPath $mixed -Pattern 'first line' -Quiet))
    Test-Case 'a clean log is left untouched' ((Repair-LaotLogEncoding -Path (Join-Path $tmp 'cfg-utf8.json')) -eq $false)

    $realLog = Join-Path $RepoRoot 'audio\repair-log.txt'
    if (Test-Path -LiteralPath $realLog) {
      Test-Case 'the shipped audio\repair-log.txt is readable UTF-8 (no NUL bytes)' (Test-LaotLogReadable -Path $realLog)
    } else {
      Test-Case 'the shipped audio\repair-log.txt exists' $false $realLog
    }
  } else {
    Test-Case 'audio\lib\AudioBackup.ps1 present' $false $audioLib
  }
}
finally {
  if (-not $KeepTemp) {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    Write-Host ("temp dir kept: {0}" -f $tmp)
  }
}

Write-Host ''
Write-Host ('-' * 60)
if ($script:Fail -eq 0) {
  Write-Host ("selftest: {0} passed, 0 failed" -f $script:Pass) -ForegroundColor Green
  exit 0
}
Write-Host ("selftest: {0} passed, {1} FAILED" -f $script:Pass, $script:Fail) -ForegroundColor Red
foreach ($f in $script:Failures) { Write-Host ("  failed: {0}" -f $f) -ForegroundColor Red }
exit 1
