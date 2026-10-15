# Benchmark one Sydney server configuration.
param(
  [Parameter(Mandatory=$true)][string]$Name,
  [int]$Ctx = 4096,
  [string[]]$Extra = @()
)
$exe   = 'D:\llama.cpp\llama-server.exe'
$model = 'D:\models\sydney\Qwen3.5-Sydney-9B-Q4_K_M.gguf'
$tpl   = 'D:\ai\sydney\sydney_template.jinja'
$bench = 'D:\ai\sydney\final_test.json'
$logDir = 'D:\ai\logs'

function Stop-Sydney {
  Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*--port 8081*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 3
}

# animated wallpapers eat VRAM that the model could use
Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '(?i)^wallpaper(32|64)$|^lively$' } |
  ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }

Stop-Sydney
$out = Join-Path $logDir "bm-$Name.out.log"
$err = Join-Path $logDir "bm-$Name.err.log"
$base = @('-m',$model,'--alias','sydney-9b','--host','127.0.0.1','--port','8081','--parallel','1',
          '-c',[string]$Ctx,
          '-fa','on','-ngl','auto','-fit','on','-fitt','350','--jinja','--reasoning','off',
          '--chat-template-file',$tpl) + $Extra
Start-Process -FilePath $exe -ArgumentList $base -WorkingDirectory 'D:\llama.cpp' `
  -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err | Out-Null

$ready = $false
for ($i=0; $i -lt 80; $i++) {
  Start-Sleep -Seconds 3
  if ((& curl.exe -s -o NUL -w "%{http_code}" --max-time 4 'http://127.0.0.1:8081/health') -eq '200') { $ready = $true; break }
}
if (-not $ready) { "RESULT $Name LOAD-FAILED"; Stop-Sydney; exit 1 }
$vramFreeBefore = (nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits)
$resp = Join-Path $logDir "bm-$Name.json"
$sw = [Diagnostics.Stopwatch]::StartNew()
& curl.exe -s --max-time 600 -H 'Content-Type: application/json' --data-binary "@$bench" 'http://127.0.0.1:8081/v1/chat/completions' -o $resp
$sw.Stop()
$vramUsed = (nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
$parsed = & node 'D:\ai\sydney\parse-timings.mjs' $resp
"RESULT $Name ctx=$Ctx extra=[$($Extra -join ' ')] wall=$([math]::Round($sw.Elapsed.TotalSeconds,1))s vramUsed=$vramUsed MiB freeBeforeLoad=$vramFreeBefore MiB"
"       $parsed"
Stop-Sydney
