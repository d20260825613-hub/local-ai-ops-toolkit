@echo off
rem Auto-start DeepSeek Harness web profile (same command as the "deepseek harness" shortcut).
rem Skips when port 3080 is already serving, so it never starts a second instance.
rem
rem Paths: the log lives next to this launcher (%~dp0), which is D:\ai\dsh when the
rem repository is deployed there. node/npx are looked up in D:\nodejs, then next to
rem this launcher, then on PATH - if none of them has it, the launcher says so and
rem exits with an error instead of pretending it started something.
setlocal
set "LOG=%~dp0dsh-boot.log"

set "NPX="
if exist "D:\nodejs\npx.cmd" set "NPX=D:\nodejs\npx.cmd"
if not defined NPX if exist "%~dp0nodejs\npx.cmd" set "NPX=%~dp0nodejs\npx.cmd"
if not defined NPX for %%I in (npx.cmd) do if not "%%~$PATH:I"=="" set "NPX=%%~$PATH:I"

powershell.exe -NoLogo -NoProfile -Command "try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', 3080); $c.Close(); exit 9 } catch { exit 0 }"
if errorlevel 9 (
  echo [%DATE% %TIME%] port 3080 already in use, skip start>> "%LOG%"
  exit /b 0
)

if not defined NPX (
  echo [%DATE% %TIME%] ERROR npx.cmd not found in D:\nodejs, next to this launcher, or on PATH - nothing started>> "%LOG%"
  echo [ERROR] npx.cmd not found: install Node.js, or put it in D:\nodejs.
  exit /b 2
)

echo [%DATE% %TIME%] starting: "%NPX%" @deepseek-ai/dsh web>> "%LOG%"
pushd "%~dp0"
call "%NPX%" --verbose @deepseek-ai/dsh web >> "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
popd
echo [%DATE% %TIME%] dsh exited with errorlevel %RC%>> "%LOG%"
exit /b %RC%
