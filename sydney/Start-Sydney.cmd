@echo off
rem Sydney (New Bing replica) local inference service - llama.cpp
rem port 8081   OpenAI-compatible endpoint: http://127.0.0.1:8081/v1
set "DIR=%~dp0"
"D:\llama.cpp\llama-server.exe" ^
  -m "D:\models\sydney\Qwen3.5-Sydney-9B-Q4_K_M.gguf" ^
  --alias sydney-9b ^
  --host 127.0.0.1 --port 8081 ^
  -c 4096 --parallel 1 ^
  -ngl auto -fit on -fitt 350 -fa on ^
  -ctk q8_0 -ctv q8_0 ^
  --prio -1 --jinja --reasoning off ^
  --chat-template-file "%DIR%sydney_template.jinja" ^
  --sleep-idle-seconds 1800
