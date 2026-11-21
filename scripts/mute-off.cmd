@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\USER\dsh-plugins\mute-mode.ps1" -Mode off
echo off done
timeout /t 2 >nul
