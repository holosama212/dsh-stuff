@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\USER\dsh-plugins\mute-mode.ps1" -Mode toggle
echo toggle done
timeout /t 2 >nul
