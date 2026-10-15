# audio/Fix-Audio-AllInOne.ps1
# All-in-one Windows audio fix for this laptop.
# Double-click 修复声音(双击我).cmd on the desktop (or run this file) -> click "Yes" on UAC.
# What it does:
#   1. records the original values (audio\audio-backup.json)
#   2. turns off Fast Startup            (sound vanishing after shutdown)
#   3. audio services auto-restart       (Windows Audio / Endpoint Builder crashes)
#   4. stops Windows powering down the audio controller
#   5. turns OFF exclusive mode on the default output device
#   6. disables the Nahimic effect layer (known cause of random silence)
#   7. installs DSH-AudioGuard, a watchdog that recovers automatically
# Everything is logged to D:\ai\audio\repair-log.txt and can be undone with Revert-Audio.ps1.

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
if (-not $root) { $root = 'D:\ai\audio' }

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host '需要管理员权限，正在重新启动并请求提权...'
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath
  ) | Out-Null
  exit
}

# --- log -------------------------------------------------------------------------
# The log is written by ONE writer, in ONE encoding, through PowerShell only.
# The cmd redirection used before (RunElevated-AudioFix.cmd: > repair-log.txt) made
# cmd.exe append UTF-16LE to a UTF-8 file, which left a file whose bytes were 47% NUL
# and unreadable in any editor. If an already-mixed file is found it is repaired once,
# then appended to as UTF-8 from then on.
. (Join-Path $root 'lib\AudioBackup.ps1')
$log = Join-Path $root 'repair-log.txt'
Repair-LaotLogEncoding -Path $log | Out-Null
"=== audio fix run at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Add-Content -LiteralPath $log -Encoding UTF8

# run the repair in-process: no cmd redirection, no second decoder
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Repair-WindowsAudio.ps1') 2>&1 |
  ForEach-Object { Add-Content -LiteralPath $log -Value ([string]$_) -Encoding UTF8 }

# ---- install the watchdog -----------------------------------------------------
$summary = @()
try {
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument ('-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $root 'AudioGuard.ps1'))
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
  $taskPrincipal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive -RunLevel Highest
  Register-ScheduledTask -TaskName 'DSH-AudioGuard' -Action $action -Trigger $trigger `
    -Settings $settings -Principal $taskPrincipal -Force -ErrorAction Stop | Out-Null
  Start-ScheduledTask -TaskName 'DSH-AudioGuard'
  $summary += '已安装声音守护任务 DSH-AudioGuard（开机自启，声音服务挂掉会自动重启）'
  "watchdog task DSH-AudioGuard installed and started" | Add-Content -LiteralPath $log -Encoding UTF8
} catch {
  $summary += ('守护任务安装失败: ' + $_.Exception.Message)
  ('watchdog install failed: ' + $_.Exception.Message) | Add-Content -LiteralPath $log -Encoding UTF8
}

$summary += ''
$summary += '修复项：'
$summary += ' 1) 记录原始设置（audio-backup.json，供一键还原）'
$summary += ' 2) 关闭快速启动'
$summary += ' 3) 声音服务崩溃自动重启'
$summary += ' 4) 关闭音频设备省电断电'
$summary += ' 5) 关闭独占模式'
$summary += ' 6) 停用 Nahimic 音效层'
$summary += ''
$summary += ('详细日志: ' + $log)
$summary += ('原始设置备份: ' + (Join-Path $root 'audio-backup.json'))
$summary += ('想还原：运行 ' + (Join-Path $root 'Revert-Audio.ps1'))

try {
  $ws = New-Object -ComObject WScript.Shell
  $ws.Popup(($summary -join "`n"), 0, '声音修复完成', 64) | Out-Null
} catch { }
