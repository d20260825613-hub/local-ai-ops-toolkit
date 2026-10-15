# All-in-one Windows audio fix for this laptop.
# Double-click 修复声音(双击我).cmd on the desktop (or run this file) -> click "Yes" on UAC.
# What it does:
#   1. turns off Fast Startup            (sound vanishing after shutdown)
#   2. audio services auto-restart       (Windows Audio / Endpoint Builder crashes)
#   3. stops Windows powering down the audio controller
#   4. turns OFF exclusive mode on the default output device
#   5. disables the Nahimic effect layer (known cause of random silence)
#   6. installs DSH-AudioGuard, a watchdog that recovers automatically
# Everything is logged to D:\ai\audio\repair-log.txt and can be undone with Revert-Audio.ps1.

$ErrorActionPreference = 'Continue'
$root = 'D:\ai\audio'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host '需要管理员权限，正在重新启动并请求提权...'
  Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath
  ) | Out-Null
  exit
}

$log = Join-Path $root 'repair-log.txt'
"=== audio fix run at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content -LiteralPath $log -Encoding UTF8
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'Repair-WindowsAudio.ps1') 2>&1 |
  Tee-Object -FilePath $log -Append | Out-Null

# ---- install the watchdog -----------------------------------------------------
$summary = @()
try {
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument '-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "D:\ai\audio\AudioGuard.ps1"'
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
$summary += ' 1) 关闭快速启动'
$summary += ' 2) 声音服务崩溃自动重启'
$summary += ' 3) 关闭音频设备省电断电'
$summary += ' 4) 关闭独占模式'
$summary += ' 5) 停用 Nahimic 音效层'
$summary += ''
$summary += ('详细日志: ' + $log)
$summary += '想还原：运行 D:\ai\audio\Revert-Audio.ps1'

try {
  $ws = New-Object -ComObject WScript.Shell
  $ws.Popup(($summary -join "`n"), 0, '声音修复完成', 64) | Out-Null
} catch { }
