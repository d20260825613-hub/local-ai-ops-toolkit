@echo off
rem Auto-start DeepSeek Harness web profile (same command as the "deepseek harness" shortcut).
rem Skips when port 3080 is already serving, so it never starts a second instance.
set "LOG=D:\ai\dsh\dsh-boot.log"
if not exist "D:\ai\dsh" mkdir "D:\ai\dsh"
powershell.exe -NoLogo -NoProfile -Command "try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', 3080); $c.Close(); exit 9 } catch { exit 0 }"
if errorlevel 9 (
  echo [%DATE% %TIME%] port 3080 already in use, skip start>> "%LOG%"
  exit /b 0
)
echo [%DATE% %TIME%] starting: npx @deepseek-ai/dsh web>> "%LOG%"
cd /d "D:\nodejs"
call "D:\nodejs\npx.cmd" --verbose @deepseek-ai/dsh web >> "%LOG%" 2>&1
echo [%DATE% %TIME%] dsh exited with errorlevel %ERRORLEVEL%>> "%LOG%"
