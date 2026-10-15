# Sweep llama-server offload settings for the Sydney 9B model on a 4 GB GTX 1050 Ti.
$exe   = 'D:\llama.cpp\llama-server.exe'
$model = 'D:\models\sydney\Qwen3.5-Sydney-9B-Q4_K_M.gguf'
$tpl   = 'D:\ai\sydney\sydney_template.jinja'
$bench = 'D:\ai\sydney\bench.json'

function Stop-Sydney {
  Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*--port 8081*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 3
}

function Wait-Ready($port, $timeoutSec) {
  for ($i = 0; $i -lt ($timeoutSec / 3); $i++) {
    $h = & curl.exe -s -o NUL -w "%{http_code}" --max-time 5 "http://127.0.0.1:$port/health"
    if ($h -eq '200') { return $true }
    Start-Sleep -Seconds 3
  }
  return $false
}

$cases = @(
  @{ name = 'fit350';            args = @('-ngl','auto','-fit','on','-fitt','350') }
  @{ name = 'fit600';            args = @('-ngl','auto','-fit','on','-fitt','600') }
  @{ name = 'fit250';            args = @('-ngl','auto','-fit','on','-fitt','250') }
  @{ name = 'fit350+kvq8';       args = @('-ngl','auto','-fit','on','-fitt','350','-ctk','q8_0','-ctv','q8_0') }
)

$results = @()
foreach ($c in $cases) {
  Stop-Sydney
  $out = "D:\ai\logs\bench-$($c.name).out.log"
  $err = "D:\ai\logs\bench-$($c.name).err.log"
  $base = @('-m',$model,'--alias','sydney-9b','--host','127.0.0.1','--port','8081','-c','4096','--parallel','1',
            '-fa','on','--jinja','--reasoning','off','--chat-template-file',$tpl)
  $p = Start-Process -FilePath $exe -ArgumentList ($base + $c.args) -WorkingDirectory 'D:\llama.cpp' `
        -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
  $ok = Wait-Ready 8081 240
  if (-not $ok) { $results += [pscustomobject]@{ case=$c.name; ok=$false; toks=0; free=0 }; continue }
  $vram = (nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits) -replace '\D',''
  $sw = [Diagnostics.Stopwatch]::StartNew()
  & curl.exe -s --max-time 300 -H 'Content-Type: application/json' --data-binary "@$bench" 'http://127.0.0.1:8081/v1/chat/completions' -o "D:\ai\sydney\bench_$($c.name).json"
  $sw.Stop()
  $json = Get-Content "D:\ai\sydney\bench_$($c.name).json" -Raw | ConvertFrom-Json
  $toks = [math]::Round([double]$json.timings.predicted_per_second, 2)
  $results += [pscustomobject]@{ case=$c.name; ok=$true; toks=$toks; free=$vram; wall=[math]::Round($sw.Elapsed.TotalSeconds,1) }
}
Stop-Sydney
$results | Format-Table -AutoSize
