# Agent toolchain v3 - virtualenv based (uv-managed python is externally managed).
$ErrorActionPreference = 'Continue'
$Bin = 'D:\tools\bin'; $Dl = 'D:\tools\_downloads'
$Log = 'D:\ai\tools\install3-log.txt'
"=== run $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -LiteralPath $Log -Encoding UTF8
function L($m) { $line = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $m; Write-Host $line; Add-Content -LiteralPath $Log -Value $line -Encoding UTF8 }

$uv = Join-Path $Bin 'uv.exe'
$env:UV_PYTHON_INSTALL_DIR = 'D:\Python'
$env:UV_DEFAULT_INDEX = 'https://pypi.tuna.tsinghua.edu.cn/simple'
$venv = 'D:\Python\venv'
$py = Join-Path $venv 'Scripts\python.exe'

L '1) create venv'
if (Test-Path $py) { L '   venv exists' }
else { & $uv venv $venv --python 3.12 2>&1 | ForEach-Object { L ('   ' + $_) } }

L '2) install packages (tsinghua pypi)'
if (Test-Path $py) {
  $pkgs = @('yt-dlp','pypandoc-binary','imageio-ffmpeg','playwright','requests','httpx','beautifulsoup4','lxml','pillow','pypdf','openpyxl','python-docx','pandas')
  & $uv pip install --python $py @pkgs 2>&1 | ForEach-Object { L ('   ' + $_) }
} else { L '   no venv python' }

L '3) expose binaries'
if (Test-Path $py) {
  $ff = ([string](& $py -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())" 2>&1 | Select-Object -Last 1)).Trim()
  if ($ff -and (Test-Path $ff)) {
    New-Item -ItemType Directory -Force -Path 'D:\tools\ffmpeg\bin' | Out-Null
    Copy-Item $ff 'D:\tools\ffmpeg\bin\ffmpeg.exe' -Force; L ('   ffmpeg -> ' + $ff)
  } else { L '   ffmpeg missing' }
  $pd = ([string](& $py -c "import pypandoc;print(pypandoc.get_pandoc_path())" 2>&1 | Select-Object -Last 1)).Trim()
  if ($pd -and (Test-Path $pd)) {
    New-Item -ItemType Directory -Force -Path 'D:\tools\pandoc' | Out-Null
    Copy-Item $pd 'D:\tools\pandoc\pandoc.exe' -Force; L ('   pandoc -> ' + $pd)
  } else { L '   pandoc missing' }
  $yd = Join-Path $venv 'Scripts\yt-dlp.exe'
  if (Test-Path $yd) { Copy-Item $yd (Join-Path $Bin 'yt-dlp.exe') -Force; L '   yt-dlp -> D:\tools\bin' } else { L '   yt-dlp script missing' }
}

L '4) playwright chromium (npmmirror)'
if (Test-Path $py) {
  $env:PLAYWRIGHT_BROWSERS_PATH = 'D:\tools\ms-playwright'
  $env:PLAYWRIGHT_DOWNLOAD_HOST = 'https://cdn.npmmirror.com/binaries/playwright'
  & $py -m playwright install chromium 2>&1 | ForEach-Object { L ('   ' + $_) }
}

L '5) PATH + mirror environment'
$add = @('D:\Python\venv\Scripts')
$cur = [Environment]::GetEnvironmentVariable('Path','User'); $parts = @(); if ($cur) { $parts = $cur -split ';' | Where-Object { $_ } }
$changed = $false
foreach ($a in $add) { if (-not ($parts -contains $a)) { $parts += $a; $changed = $true; L ('   + ' + $a) } }
if ($changed) { [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User'); L '   PATH updated' } else { L '   PATH already complete' }

# README 承诺"把镜像写成用户环境变量、一次配好永久生效":$env: 赋值只影响当前进程,
# 所以这里用 User 作用域真正持久化(与 Install-AgentTools.ps1 / 2 行为一致)。
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

L '6) verify'
if (Test-Path $py) {
  L ('   python : ' + ((& $py --version 2>&1) -join ''))
  $check = & $py -c "import importlib;[print(m, bool(importlib.util.find_spec(m))) for m in ['yt_dlp','pypandoc','imageio_ffmpeg','playwright','requests','httpx','bs4','lxml','PIL','pypdf','openpyxl','docx','pandas']]" 2>&1
  $check | ForEach-Object { L ('   ' + $_) }
}
foreach ($p in 'D:\tools\ffmpeg\bin\ffmpeg.exe','D:\tools\pandoc\pandoc.exe',(Join-Path $Bin 'yt-dlp.exe')) { L ('   ' + $p + ' : ' + (Test-Path $p)) }
L 'done'
