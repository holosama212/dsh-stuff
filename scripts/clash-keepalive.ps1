# Clash Verge keepalive: if proxy port 7897 is not listening, launch Verge.
#   -File clash-keepalive.ps1          -> check once, start if down
#   -File clash-keepalive.ps1 -Loop    -> resident, poll every IntervalSec
param(
  [switch]$Loop,
  [int]$IntervalSec = 60
)
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$exe  = 'C:\Users\USER\Desktop\Clash Verge\clash-verge.exe'
$work = 'C:\Users\USER\Desktop\Clash Verge'
$port = 7897
$log  = 'C:\Users\USER\dsh-plugins\clash-keepalive.log'

function Write-Log([string]$msg) {
  $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
  Add-Content -LiteralPath $log -Value $line -Encoding UTF8
}

function Test-ClashPort {
  $c = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq $port }
  return ($null -ne $c)
}

function Start-Clash {
  if (-not (Test-Path -LiteralPath $exe)) { Write-Log ('MISSING exe: ' + $exe); return $false }
  # If the Verge GUI is alive but the core is dead, relaunching the exe does
  # nothing (single instance). Kill the GUI too, then start fresh.
  Get-Process -Name 'verge-mihomo','verge-mihomo-alpha' -ErrorAction SilentlyContinue | Stop-Process -Force
  $gui = @(Get-Process -Name 'clash-verge' -ErrorAction SilentlyContinue)
  if ($gui.Count -gt 0) {
    Write-Log 'gui alive but core dead -> restarting gui'
    $gui | Stop-Process -Force
    Start-Sleep -Seconds 3
  }
  Start-Process -FilePath $exe -WorkingDirectory $work
  Write-Log 'started clash-verge'
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Seconds 2
    if (Test-ClashPort) { Write-Log ('port up after ' + (($i + 1) * 2) + 's'); return $true }
  }
  Write-Log 'FAILED to come up in 80s'
  return $false
}

if (-not $Loop) {
  if (Test-ClashPort) { Write-Output ('port ' + $port + ' OK'); exit 0 }
  Write-Output ('port ' + $port + ' down, starting')
  if (Start-Clash) { Write-Output 'started OK'; exit 0 }
  Write-Output 'start FAILED'
  exit 1
}

Write-Log 'keepalive loop start'
while ($true) {
  if (-not (Test-ClashPort)) {
    Write-Log 'port down, restarting'
    $null = Start-Clash
  }
  Start-Sleep -Seconds $IntervalSec
}