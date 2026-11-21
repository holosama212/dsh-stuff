$ErrorActionPreference = 'SilentlyContinue'
Start-Sleep -Seconds 10
Get-Process -Name 'DSH Desktop' | Stop-Process -Force
Start-Sleep -Seconds 4
Start-Process 'C:\Program Files\DSH Desktop\DSH Desktop.exe'