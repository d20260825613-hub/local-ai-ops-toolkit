# Install a no-admin, all-on-D: toolchain for the DSH agent.
# Sources: npmmirror binary mirror + ghproxy (GitHub proxy) + tsinghua pypi.
# Idempotent: existing installs are skipped. Log: D:\ai\tools\install-log.txt
$ErrorActionPreference = 'Continue'
$Root = 'D:\tools'
$Bin = Join-Path $Root 'bin'
$Dl = Join-Path $Root '_downloads'
foreach ($d in @($Root, $Bin, $Dl)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null } }
$Log = 'D:\ai\tools\install-log.txt'
if (-not (Test-Path 'D:\ai\tools')) { New-Item -ItemType Directory -Force -Path 'D:\ai\tools' | Out-Null }
"=== install run $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -LiteralPath $Log -Encoding UTF8

function Write-Log($m) {
  $line = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $m
  Write-Host $line
  Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
}

$SevenZip = 'D:\7-Zip\7z.exe'
if (-not (Test-Path $SevenZip)) { Write-Log "WARN: 7z not found at $SevenZip" }
$Proxy = 'https://ghproxy.net/'
$Mirror = 'https://registry.npmmirror.com/-/binary/'
$EnvRecord = 'D:\tools\mirror-env.json'

# --- mirror environment (user level) --------------------------------------------
# README promises "write the mirrors into user environment variables, configure once
# and every tool uses them". Assigning $env:NAME only affects this process and is lost
# when the script exits, so the persistent values are written with
# [Environment]::SetEnvironmentVariable(name, value, 'User') - user scope, no admin,
# and only entries that differ are touched. Remove them with:
#   foreach ($n in (Get-Content D:\ai\tools\mirror-env.json | ConvertFrom-Json).names)
#     { [Environment]::SetEnvironmentVariable($n, $null, 'User') }
$MirrorEnv = [ordered]@{
  'PIP_INDEX_URL'             = 'https://pypi.tuna.tsinghua.edu.cn/simple'
  'PIP_TRUSTED_HOST'          = 'pypi.tuna.tsinghua.edu.cn'
  'UV_DEFAULT_INDEX'          = 'https://pypi.tuna.tsinghua.edu.cn/simple'
  'UV_PYTHON_INSTALL_DIR'     = 'D:\Python'
  'UV_PYTHON_INSTALL_MIRROR'  = 'https://registry.npmmirror.com/-/binary/python-build-standalone'
  'NPM_CONFIG_REGISTRY'       = 'https://registry.npmmirror.com'
  'HF_ENDPOINT'               = 'https://hf-mirror.com'
  'HF_HOME'                   = 'D:\hf-cache'
  'PLAYWRIGHT_DOWNLOAD_HOST'  = 'https://cdn.npmmirror.com/binaries/playwright'
  'PLAYWRIGHT_BROWSERS_PATH'  = 'D:\tools\ms-playwright'
}

function Set-MirrorEnv {
  $changed = @()
  foreach ($name in $MirrorEnv.Keys) {
    $want = [string]$MirrorEnv[$name]
    $have = [Environment]::GetEnvironmentVariable($name, 'User')
    if ($have -ne $want) {
      try {
        [Environment]::SetEnvironmentVariable($name, $want, 'User')
        $changed += $name
        Write-Log ("  env + {0} = {1}" -f $name, $want)
      } catch {
        Write-Log ("  env FAILED {0}: {1}" -f $name, $_.Exception.Message)
      }
    }
  }
  if ($changed.Count -eq 0) { Write-Log '  user mirror environment already complete' }
  else { Write-Log '  user mirror environment updated (takes effect in new processes)' }
  try {
    @{ updated = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); names = @($MirrorEnv.Keys); values = $MirrorEnv } |
      ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $EnvRecord -Encoding UTF8
  } catch { }
}

function Get-Remote($url, $out) {
  if ((Test-Path $out) -and ((Get-Item $out).Length -gt 1024)) { Write-Log "  cached: $(Split-Path $out -Leaf)"; return $true }
  Write-Log "  download: $url"
  & curl.exe -L --retry 3 --retry-delay 2 -C - --max-time 3600 -o $out $url 2>$null
  if ((Test-Path $out) -and ((Get-Item $out).Length -gt 1024)) {
    Write-Log ("  ok: {0:N1} MB" -f ((Get-Item $out).Length / 1MB))
    return $true
  }
  Write-Log "  FAILED: $url"
  return $false
}

function Expand-With7z($archive, $dest) {
  if (-not (Test-Path $SevenZip)) { return $false }
  if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }
  & $SevenZip x -y -bso0 -bsp0 ("-o" + $dest) $archive | Out-Null
  return ($LASTEXITCODE -eq 0)
}

function Tool-Version($exe, $arg) {
  if (-not (Test-Path $exe)) { return 'MISSING' }
  try {
    $out = & $exe $arg 2>&1 | Select-Object -First 1
    return ([string]$out).Trim()
  } catch { return 'ERROR' }
}

# ---------------------------------------------------------------- 1. Git
Write-Log '1) PortableGit'
if (Test-Path 'D:\Git\cmd\git.exe') { Write-Log '  already installed' }
else {
  $f = Join-Path $Dl 'PortableGit.7z.exe'
  if (Get-Remote ($Mirror + 'git-for-windows/v2.56.0.windows.2/PortableGit-2.56.0.2-64-bit.7z.exe') $f) {
    if (Expand-With7z $f 'D:\Git') { Write-Log '  extracted to D:\Git' } else { Write-Log '  extract FAILED' }
  }
}

# ---------------------------------------------------------------- 2. aria2
Write-Log '2) aria2'
if (Test-Path 'D:\tools\aria2\aria2c.exe') { Write-Log '  already installed' }
else {
  $f = Join-Path $Dl 'aria2.zip'
  if (Get-Remote ($Proxy + 'https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip') $f) {
    if (Expand-With7z $f 'D:\tools\aria2') { Write-Log '  extracted to D:\tools\aria2' } else { Write-Log '  extract FAILED' }
  }
}

# ---------------------------------------------------------------- 3. yt-dlp / jq
Write-Log '3) yt-dlp + jq'
$dl = @(
  @{ url = ($Proxy + 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe'); out = (Join-Path $Bin 'yt-dlp.exe') },
  @{ url = ($Proxy + 'https://github.com/jqlang/jq/releases/latest/download/jq-windows-amd64.exe'); out = (Join-Path $Bin 'jq.exe') }
)
foreach ($d in $dl) { if (Test-Path $d.out) { Write-Log ("  already: " + (Split-Path $d.out -Leaf)) } else { [void](Get-Remote $d.url $d.out) } }

# ---------------------------------------------------------------- 4. ffmpeg
Write-Log '4) ffmpeg'
if (Test-Path 'D:\tools\ffmpeg\bin\ffmpeg.exe') { Write-Log '  already installed' }
else {
  $f = Join-Path $Dl 'ffmpeg.zip'
  if (Get-Remote ($Proxy + 'https://github.com/BtbN/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip') $f) {
    $tmp = Join-Path $Dl 'ffmpeg-x'
    if (Expand-With7z $f $tmp) {
      $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
      if ($inner) {
        if (Test-Path 'D:\tools\ffmpeg') { Remove-Item 'D:\tools\ffmpeg' -Recurse -Force -ErrorAction SilentlyContinue }
        Move-Item $inner.FullName 'D:\tools\ffmpeg' -Force
        Write-Log '  installed to D:\tools\ffmpeg'
      }
    } else { Write-Log '  extract FAILED' }
  }
}

# ---------------------------------------------------------------- 5. pandoc
Write-Log '5) pandoc'
if (Test-Path 'D:\tools\pandoc\pandoc.exe') { Write-Log '  already installed' }
else {
  $f = Join-Path $Dl 'pandoc.zip'
  if (Get-Remote ($Proxy + 'https://github.com/jgm/pandoc/releases/download/3.12.1/pandoc-3.12.1-windows-x86_64.zip') $f) {
    $tmp = Join-Path $Dl 'pandoc-x'
    if (Expand-With7z $f $tmp) {
      $exe = Get-ChildItem $tmp -Recurse -Filter 'pandoc.exe' | Select-Object -First 1
      if ($exe) {
        if (Test-Path 'D:\tools\pandoc') { Remove-Item 'D:\tools\pandoc' -Recurse -Force -ErrorAction SilentlyContinue }
        New-Item -ItemType Directory -Force -Path 'D:\tools\pandoc' | Out-Null
        Copy-Item $exe.FullName 'D:\tools\pandoc\pandoc.exe' -Force
        Write-Log '  installed to D:\tools\pandoc'
      }
    } else { Write-Log '  extract FAILED' }
  }
}

# ---------------------------------------------------------------- 6. uv + Python
Write-Log '6) uv'
$uv = Join-Path $Bin 'uv.exe'
if (Test-Path $uv) { Write-Log '  already installed' }
else {
  $f = Join-Path $Dl 'uv.zip'
  if (Get-Remote ($Proxy + 'https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip') $f) {
    if (Expand-With7z $f $Bin) { Write-Log '  uv.exe -> D:\tools\bin' } else { Write-Log '  extract FAILED' }
  }
}

Write-Log '7) portable CPython 3.12 (via uv, mirror: npmmirror)'
$env:UV_PYTHON_INSTALL_DIR = 'D:\Python'
$env:UV_PYTHON_INSTALL_MIRROR = 'https://registry.npmmirror.com/-/binary/python-build-standalone'
if (Test-Path $uv) {
  if (-not (Test-Path 'D:\Python')) { New-Item -ItemType Directory -Force -Path 'D:\Python' | Out-Null }
  & $uv python install 3.12 2>&1 | ForEach-Object { Write-Log ("  " + $_) }
  $pyExe = (& $uv python find 3.12 2>&1 | Select-Object -Last 1)
  if ($pyExe -and (Test-Path ([string]$pyExe).Trim())) { Write-Log ("  python: " + ([string]$pyExe).Trim()) } else { Write-Log '  python not resolved' }
} else { Write-Log '  skipped (no uv)' }

# ---------------------------------------------------------------- 8. PATH (user)
Write-Log '8) user PATH'
$add = @('D:\tools\bin', 'D:\tools\aria2', 'D:\tools\ffmpeg\bin', 'D:\tools\pandoc', 'D:\Git\cmd', 'D:\Python')
$cur = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @()
if ($cur) { $parts = $cur -split ';' | Where-Object { $_ } }
$changed = $false
foreach ($a in $add) {
  if (-not ($parts -contains $a)) { $parts += $a; $changed = $true; Write-Log ("  + " + $a) }
}
if ($changed) {
  [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
  Write-Log '  user PATH updated (takes effect in new processes)'
} else { Write-Log '  PATH already complete' }

# ---------------------------------------------------------------- 9. mirror env (user)
Write-Log '9) user mirror environment'
Set-MirrorEnv

# ---------------------------------------------------------------- 10. manifest
Write-Log '10) versions'
$manifest = @()
$manifest += 'git      : ' + (Tool-Version 'D:\Git\cmd\git.exe' '--version')
$manifest += 'aria2c   : ' + (Tool-Version 'D:\tools\aria2\aria2c.exe' '--version')
$manifest += 'yt-dlp   : ' + (Tool-Version (Join-Path $Bin 'yt-dlp.exe') '--version')
$manifest += 'jq       : ' + (Tool-Version (Join-Path $Bin 'jq.exe') '--version')
$manifest += 'ffmpeg   : ' + (Tool-Version 'D:\tools\ffmpeg\bin\ffmpeg.exe' '-version')
$manifest += 'pandoc   : ' + (Tool-Version 'D:\tools\pandoc\pandoc.exe' '--version')
$manifest += 'uv       : ' + (Tool-Version $uv '--version')
foreach ($m in $manifest) { Write-Log ("  " + $m) }
$manifest | Set-Content -LiteralPath 'D:\tools\MANIFEST.txt' -Encoding UTF8
Write-Log 'done'
