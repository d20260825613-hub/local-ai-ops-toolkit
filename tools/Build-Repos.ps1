# Build local git repositories for everything the agent wrote that is not on GitHub yet.
# Copies filtered file sets into D:\repos\<name>, initialises git, and makes the first commit.
# Nothing is pushed here - the network path to GitHub is decided separately.
$ErrorActionPreference = 'Continue'
$Root = 'D:\repos'
if (-not (Test-Path $Root)) { New-Item -ItemType Directory -Force -Path $Root | Out-Null }

function New-Repo($name) {
  $p = Join-Path $Root $name
  if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
  return $p
}
function Copy-Into($src, $dst, $excludeRegex) {
  if (-not (Test-Path $src)) { return 0 }
  $n = 0
  Get-ChildItem $src -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $rel = $_.FullName.Substring($src.Length).TrimStart('\')
    if ($excludeRegex -and ($rel -match $excludeRegex)) { return }
    $target = Join-Path $dst $rel
    $dir = Split-Path $target -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Copy-Item $_.FullName $target -Force -ErrorAction SilentlyContinue
    $n++
  }
  return $n
}

# ---------------------------------------------------------------- 1) local-ai-ops-toolkit
Write-Output '=== repo 1: local-ai-ops-toolkit ==='
$r1 = New-Repo 'local-ai-ops-toolkit'
# scripts + docs from D:\ai (skip secrets/logs/state/big artefacts)
$ex1 = '(?i)\\logs\\|\\backup\\|_downloads|\.log$|^state\.json$|^config\.json$|guard-state\.json|pkg\.json$|install\d?-log\.txt$|final_resp\.json$|bench.*\.json$|final_test\.json$|req.*\.json$' +
       '|^交接摘要\.txt$|^工具与插件清单\.txt$|^sydney/2b-readme\.md$'
$c = Copy-Into 'D:\ai' $r1 $ex1
Write-Output "  copied $c files from D:\ai"
# config as sample
if (Test-Path 'D:\ai\config.json') {
  $cfg = Get-Content 'D:\ai\config.json' -Raw -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $r1 'config.sample.json') -Value $cfg -Encoding UTF8
}

# ---------------------------------------------------------------- 2) dsh-toolbox
Write-Output '=== repo 2: dsh-toolbox ==='
$r2 = New-Repo 'dsh-toolbox'
$ex2 = '(?i)\.exe$|\.zip$|\.png$|\.log$|gh-token\.txt|gh-device-challenge\.txt|^edge-direct\\|^edge-profile\\|^node\\|^pnpm\\|^npm-cache\\|^gh\\|^git\\|^hugo-bin\\|^papermod|^qrverify\\|^lockbox-clone\\|^clone-test\\|^dj-test\\|^tabkit-out\\|^ci-steps\\'
$c2 = Copy-Into 'D:\dsh\_tools' (Join-Path $r2 'github-automation') $ex2
Write-Output "  copied $c2 files from D:\dsh\_tools"
# agent inspector utilities written in the 2026-10 DSH sessions
$c3 = Copy-Into 'C:\Users\ADMIN\.dsh\dsh_wechat' (Join-Path $r2 'agent-inspectors') '(?i)\.jsonl$|\.txt$'
Write-Output "  copied $c3 inspector files"
# hugo blog bootstrap tooling
$c4 = Copy-Into 'D:\dsh\hugo-blog-setup' (Join-Path $r2 'hugo-blog-setup') '(?i)\.exe$'
Write-Output "  copied $c4 hugo-blog-setup files"

# ---------------------------------------------------------------- 3) 12306-ticket-radar
Write-Output '=== repo 3: 12306-ticket-radar ==='
$r3 = New-Repo '12306-ticket-radar'
$ex3 = '(?i)\\node_modules\\|\\build\\.*\.exe$|^data\\config\.json$|^data\\state\.json$|^data\\port\.txt$|\\runtime\\'
$c5 = Copy-Into 'D:\dsh\12306-assistant' $r3 $ex3
Write-Output "  copied $c5 files"

# ---------------------------------------------------------------- 4) music-player
Write-Output '=== repo 4: music-player ==='
$r4 = New-Repo 'music-player'
$ex4 = '(?i)\.exe$|\\obj\\|\\bin\\'
$c6 = Copy-Into 'D:\dsh\music-player' $r4 $ex4
Write-Output "  copied $c6 files"

# ---------------------------------------------------------------- git init + commit
$git = 'D:\Git\cmd\git.exe'
foreach ($repo in 'local-ai-ops-toolkit','dsh-toolbox','12306-ticket-radar','music-player') {
  $p = Join-Path $Root $repo
  if (-not (Test-Path (Join-Path $p '.git'))) {
    & $git -C $p init -q -b main 2>&1 | Out-Null
  }
  & $git -C $p add -A 2>&1 | Out-Null
  $msg = "Initial commit: $repo (written by the DSH agent)"
  & $git -C $p -c user.name='DSH agent' -c user.email='agent@localhost' commit -q -m $msg 2>&1 | Out-Null
  $files = (& $git -C $p ls-files | Measure-Object).Count
  $size = [math]::Round(((Get-ChildItem $p -Recurse -File -Force | Where-Object { $_.FullName -notmatch '\\\.git\\' } | Measure-Object Length -Sum).Sum)/1MB, 2)
  "{0,-26} files={1,-6} size={2} MB" -f $repo, $files, $size
}
