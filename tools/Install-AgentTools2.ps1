# Agent toolchain v2 - mirror-only sources (no slow GitHub proxy dependence).
#   uv        : gh-proxy.com  (fast proxy for GitHub assets)
#   Python    : npmmirror python-build-standalone, installed to D:\Python
#   packages  : tsinghua pypi mirror
#   chromium  : npmmirror playwright binaries
# Log: D:\ai\tools\install2-log.txt
$ErrorActionPreference = 'Continue'
$Root = 'D:\tools'; $Bin = Join-Path $Root 'bin'; $Dl = Join-Path $Root '_downloads'
foreach ($d in @($Root, $Bin, $Dl)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null } }
$Log = 'D:\ai\tools\install2-log.txt'
"=== run $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -LiteralPath $Log -Encoding UTF8
function L($m) { $line = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $m; Write-Host $line; Add-Content -LiteralPath $Log -Value $line -Encoding UTF8 }

$Proxy = 'https://gh-proxy.com/'
$SevenZip = 'D:\7-Zip\7z.exe'

# ---------------------------------------------------------------- 1) uv
L '1) uv'
$uv = Join-Path $Bin 'uv.exe'
if (Test-Path $uv) { L '   already installed' }
else {
  $z = Join-Path $Dl 'uv.zip'
  L '   downloading uv (~15MB)'
  & curl.exe -L --retry 3 --max-time 900 -o $z ($Proxy + 'https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip') 2>$null
  if ((Test-Path $z) -and ((Get-Item $z).Length -gt 1MB)) {
    & $SevenZip x -y -bso0 -bsp0 ("-o" + $Bin) $z | Out-Null
    L ("   extracted, uv present: " + (Test-Path $uv))
  } else { L '   uv download FAILED' }
}

# ---------------------------------------------------------------- 2) Python via uv
L '2) portable CPython 3.12'
$env:UV_PYTHON_INSTALL_DIR = 'D:\Python'
$env:UV_PYTHON_INSTALL_MIRROR = 'https://registry.npmmirror.com/-/binary/python-build-standalone'
if (-not (Test-Path 'D:\Python')) { New-Item -ItemType Directory -Force -Path 'D:\Python' | Out-Null }
$py = $null
if (Test-Path $uv) {
  & $uv python install 3.12 2>&1 | ForEach-Object { L ("   " + $_) }
  $py = ([string](& $uv python find 3.12 2>&1 | Select-Object -Last 1)).Trim()
  L ("   python = " + $py)
} else { L '   skipped (no uv)' }
if ($py -and -not (Test-Path $py)) { L '   python path not found'; $py = $null }

# ---------------------------------------------------------------- 3) python packages
L '3) python packages (tsinghua pypi)'
if ($py) {
  $env:UV_DEFAULT_INDEX = 'https://pypi.tuna.tsinghua.edu.cn/simple'
  $pkgs = @(
    'yt-dlp', 'pypandoc-binary', 'imageio-ffmpeg', 'playwright',
    'requests', 'httpx', 'beautifulsoup4', 'lxml', 'pillow',
    'pypdf', 'openpyxl', 'python-docx', 'pandas'
  )
  & $uv pip install --python $py @pkgs 2>&1 | ForEach-Object { L ("   " + $_) }
} else { L '   skipped (no python)' }

# ---------------------------------------------------------------- 4) expose ffmpeg / pandoc / yt-dlp
L '4) expose bundled binaries'
if ($py) {
  $ff = ([string](& $py -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())" 2>&1 | Select-Object -Last 1)).Trim()
  if ($ff -and (Test-Path $ff)) {
    New-Item -ItemType Directory -Force -Path 'D:\tools\ffmpeg\bin' | Out-Null
    Copy-Item $ff 'D:\tools\ffmpeg\bin\ffmpeg.exe' -Force
    L ("   ffmpeg  -> D:\tools\ffmpeg\bin (from " + $ff + ")")
  } else { L '   ffmpeg not found in package' }
  $pd = ([string](& $py -c "import pypandoc;print(pypandoc.get_pandoc_path())" 2>&1 | Select-Object -Last 1)).Trim()
  if ($pd -and (Test-Path $pd)) {
    New-Item -ItemType Directory -Force -Path 'D:\tools\pandoc' | Out-Null
    Copy-Item $pd 'D:\tools\pandoc\pandoc.exe' -Force
    L ('   pandoc  -> D:\tools\pandoc')
  } else { L '   pandoc not found in package' }
  $scripts = Join-Path (Split-Path $py -Parent) 'Scripts'
  if (Test-Path (Join-Path $scripts 'yt-dlp.exe')) {
    Copy-Item (Join-Path $scripts 'yt-dlp.exe') (Join-Path $Bin 'yt-dlp.exe') -Force
    L '   yt-dlp  -> D:\tools\bin'
  } else { L '   yt-dlp console script not found' }
}

# ---------------------------------------------------------------- 5) chromium for playwright
L '5) playwright chromium (npmmirror)'
if ($py) {
  $env:PLAYWRIGHT_BROWSERS_PATH = 'D:\tools\ms-playwright'
  $env:PLAYWRIGHT_DOWNLOAD_HOST = 'https://cdn.npmmirror.com/binaries/playwright'
  & $py -m playwright install chromium 2>&1 | ForEach-Object { L ("   " + $_) }
}

# ---------------------------------------------------------------- 6) PATH + mirror env
L '6) user PATH + mirror environment'
$add = @('D:\tools\bin', 'D:\tools\ffmpeg\bin', 'D:\tools\pandoc', 'D:\Git\cmd', 'D:\Python')
$cur = [Environment]::GetEnvironmentVariable('Path', 'User')
$parts = @(); if ($cur) { $parts = $cur -split ';' | Where-Object { $_ } }
$changed = $false
foreach ($a in $add) { if (-not ($parts -contains $a)) { $parts += $a; $changed = $true; L ('   + ' + $a) } }
if ($changed) { [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User'); L '   PATH updated' } else { L '   PATH already complete' }

# README 承诺"把镜像写成用户环境变量、一次配好永久生效":$env: 赋值只影响当前进程,
# 脚本退出就没了,所以这里用 User 作用域真正持久化(不需要管理员,只写有变化的项)。
$MirrorEnv = [ordered]@{
  'PIP_INDEX_URL'            = 'https://pypi.tuna.tsinghua.edu.cn/simple'
  'PIP_TRUSTED_HOST'         = 'pypi.tuna.tsinghua.edu.cn'
  'UV_DEFAULT_INDEX'         = 'https://pypi.tuna.tsinghua.edu.cn/simple'
  'UV_PYTHON_INSTALL_DIR'    = 'D:\Python'
  'UV_PYTHON_INSTALL_MIRROR' = 'https://registry.npmmirror.com/-/binary/python-build-standalone'
  'NPM_CONFIG_REGISTRY'      = 'https://registry.npmmirror.com'
  'HF_ENDPOINT'              = 'https://hf-mirror.com'
  'HF_HOME'                  = 'D:\hf-cache'
  'PLAYWRIGHT_DOWNLOAD_HOST' = 'https://cdn.npmmirror.com/binaries/playwright'
  'PLAYWRIGHT_BROWSERS_PATH' = 'D:\tools\ms-playwright'
}
$envChanged = @()
foreach ($name in $MirrorEnv.Keys) {
  $want = [string]$MirrorEnv[$name]
  if ([Environment]::GetEnvironmentVariable($name, 'User') -ne $want) {
    try { [Environment]::SetEnvironmentVariable($name, $want, 'User'); $envChanged += $name; L ('   env + ' + $name + ' = ' + $want) }
    catch { L ('   env FAILED ' + $name + ': ' + $_.Exception.Message) }
  }
}
if ($envChanged.Count -eq 0) { L '   mirror environment already complete' } else { L '   mirror environment updated (new processes only)' }
try {
  @{ updated = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); names = @($MirrorEnv.Keys); values = $MirrorEnv } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath 'D:\tools\mirror-env.json' -Encoding UTF8
} catch { }

L '7) versions'
$m = @()
$m += 'git    : ' + ((& 'D:\Git\cmd\git.exe' --version 2>&1) -join '')
if (Test-Path $uv)  { $m += 'uv     : ' + ((& $uv --version 2>&1) -join '') }
if ($py)            { $m += 'python : ' + ((& $py --version 2>&1) -join '') }
if (Test-Path 'D:\tools\ffmpeg\bin\ffmpeg.exe') { $m += 'ffmpeg : ' + (((& 'D:\tools\ffmpeg\bin\ffmpeg.exe' -version 2>&1) | Select-Object -First 1) -join '') }
if (Test-Path 'D:\tools\pandoc\pandoc.exe')     { $m += 'pandoc : ' + (((& 'D:\tools\pandoc\pandoc.exe' --version 2>&1) | Select-Object -First 1) -join '') }
if (Test-Path (Join-Path $Bin 'yt-dlp.exe'))    { $m += 'yt-dlp : ' + ((& (Join-Path $Bin 'yt-dlp.exe') --version 2>&1) -join '') }
foreach ($line in $m) { L ('   ' + $line) }
$m | Set-Content -LiteralPath 'D:\tools\MANIFEST.txt' -Encoding UTF8
L 'done'
