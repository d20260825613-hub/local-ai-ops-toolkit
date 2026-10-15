# Stop the Sydney (New Bing replica) llama.cpp server on port 8081.
$procs = @(Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -and $_.CommandLine -like '*--port 8081*' })
if ($procs.Count -eq 0) {
  Write-Host 'Sydney service is not running.'
} else {
  foreach ($p in $procs) {
    try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; Write-Host "stopped Sydney service (pid $($p.ProcessId))" }
    catch { Write-Host "stop failed: $($_.Exception.Message)" }
  }
}
