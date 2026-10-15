@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File','D:\ai\audio\Revert-Audio.ps1')"

