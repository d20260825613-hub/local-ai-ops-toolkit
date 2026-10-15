@echo off
rem Launcher: asks for administrator rights once (UAC "Yes"), then applies the audio fix.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File','D:\ai\audio\Fix-Audio-AllInOne.ps1')"
exit /b 0
