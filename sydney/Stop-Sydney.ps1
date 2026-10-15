# Stop the Sydney (New Bing replica) llama.cpp server on port 8081.
# The port is matched as a whole argument, never as a substring: "*--port 8081*"
# would also match a server started with "--port 80810".
param(
  [int]$Port = 8081
)

$pattern = '(?i)--port[ =]+' + $Port + '(?![0-9])'
$procs = @(Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -match $pattern })
if ($procs.Count -eq 0) {
  Write-Host ("Sydney service (port {0}) is not running." -f $Port)
} else {
  foreach ($p in $procs) {
    try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; Write-Host "stopped Sydney service (pid $($p.ProcessId), port $Port)" }
    catch { Write-Host "stop failed: $($_.Exception.Message)" }
  }
}
