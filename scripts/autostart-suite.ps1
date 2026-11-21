param(
  [int]$InitialDelaySeconds = 15,
  [switch]$IncludeAstrbot,
  [switch]$Now
)

# DSH-AutoStart-All : one-shot idempotent bootstrapper, fired at logon by the
# scheduled task "DSH-AutoStart-All". Safe to run manually at any time:
# every component is only started when it is not already running.
#
# SCOPE (owner's call, 2026-10-27): logon autostart covers ONLY the two things
# that must be alive for the QQ bot:
#   1. DSH Desktop  -> owned by dsh-guard.ps1 (logon task "DSH Guard");
#                       this script calls Ensure only as a fallback.
#   2. NapCat DSH   -> NapCatDsh\NapCatWinBootMain.exe BOT_QQ
#                       (reverse ws://127.0.0.1:8643/ws to the dsh-onebot plugin)
#
# AstrBot and its NapCat (3154517648) are NOT started at logon any more: pass
# -IncludeAstrbot to bring the old four-tier behaviour back without editing
# this file. The AstrBot code paths are kept intact below, just gated.
#
# Boot order matters: the OneBot server (DSH 8643) should be listening before
# its NapCat connects; NapCat also auto-reconnects, so a slight race is harmless.
#
# Kill switch: create file C:\Users\USER\dsh-plugins\autostart-suite.off
# and the whole suite exits immediately.
# -Now skips the 15 s logon delay (useful when running by hand).

$Log = 'C:\Users\USER\dsh-plugins\autostart-suite.log'
$Off = 'C:\Users\USER\dsh-plugins\autostart-suite.off'

$DshPort  = 43129
$GuardPs1 = 'C:\Users\USER\dsh-plugins\dsh-guard.ps1'

$NapDshDir = 'C:\Users\USER\NapCatDsh'
$NapDshExe = Join-Path $NapDshDir 'NapCatWinBootMain.exe'
$NapDshUin = 'BOT_QQ'

$AstrPort = 6199
$AstrRoot = 'C:\Users\USER\.astrbot_launcher\instances\c2765c0c-9c1f-443e-8243-a38e9b771c0a'
$AstrCore = Join-Path $AstrRoot 'core'
$AstrPy   = Join-Path $AstrRoot 'venv\Scripts\python.exe'
$AstrMain = Join-Path $AstrCore 'main.py'

$NapAstrDir = 'C:\Users\USER\Desktop\NapCat.Shell.Windows.OneKey (2)\NapCat.44498.Shell'
$NapAstrExe = Join-Path $NapAstrDir 'NapCatWinBootMain.exe'
$NapAstrUin = '3154517648'

function L($m) {
  try { Add-Content -Path $Log -Value ((Get-Date -Format o) + '  ' + $m) -Encoding UTF8 } catch { }
}

function PortListening([int]$p) {
  return (@(Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue).Count -gt 0)
}

function NapCatRunning([string]$exe) {
  return (@(Get-CimInstance Win32_Process -Filter "Name='NapCatWinBootMain.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq $exe }).Count -gt 0)
}

if (Test-Path -LiteralPath $Off) { L 'off-file present, suite skipped'; exit 0 }

if (-not $Now) { Start-Sleep -Seconds $InitialDelaySeconds }
L ('=== suite run start pid=' + $PID + ' ===')

# ---- 1. DSH Desktop (fallback for the DSH Guard task) ----
if (PortListening $DshPort) {
  L 'dsh already up (port 43129)'
} else {
  L 'dsh not up, calling dsh-guard Ensure'
  try {
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$GuardPs1,'-Mode','Ensure') -WindowStyle Hidden
  } catch { L ('guard ensure spawn failed: ' + $_.Exception.Message) }
  $deadline = (Get-Date).AddSeconds(120)
  while ((Get-Date) -lt $deadline) {
    if (PortListening $DshPort) { break }
    Start-Sleep -Seconds 3
  }
  if (PortListening $DshPort) { L 'dsh up after ensure' } else { L 'dsh still down after 120s (guard watchdog will keep trying)' }
}

# ---- 2. NapCat for DSH (BOT_QQ) ----
if (NapCatRunning $NapDshExe) {
  L 'napcat-dsh already running'
} elseif (-not (Test-Path -LiteralPath $NapDshExe)) {
  L ('napcat-dsh exe missing: ' + $NapDshExe)
} else {
  try {
    Start-Process -FilePath $NapDshExe -ArgumentList $NapDshUin -WorkingDirectory $NapDshDir -WindowStyle Hidden
    L ('napcat-dsh started (account ' + $NapDshUin + ', ws 8643)')
  } catch { L ('napcat-dsh start failed: ' + $_.Exception.Message) }
}

# ---- 3. AstrBot instance (opt-in via -IncludeAstrbot) ----
if (-not $IncludeAstrbot) {
  L 'astrbot tier skipped (autostart covers dsh + napcat-dsh only)'
} else {
# Running = something already listens on 6199 (single-instance marker) OR any
# python process runs this instance's core\main.py (venv python + launcher py312).
$astrRunning = PortListening $AstrPort
if (-not $astrRunning) {
  $astrRunning = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains($AstrMain) }).Count -gt 0
}
if ($astrRunning) {
  L 'astrbot instance already running'
} elseif (-not (Test-Path -LiteralPath $AstrPy)) {
  L ('astrbot venv python missing: ' + $AstrPy)
} else {
  try {
    Start-Process -FilePath $AstrPy -ArgumentList ('"' + $AstrMain + '"') -WorkingDirectory $AstrCore -WindowStyle Hidden
    L 'astrbot instance spawn issued (c2765c0c core/main.py, ws 6199)'
  } catch { L ('astrbot start failed: ' + $_.Exception.Message) }
  $deadline = (Get-Date).AddSeconds(90)
  while ((Get-Date) -lt $deadline) {
    if (PortListening $AstrPort) { break }
    Start-Sleep -Seconds 3
  }
  if (PortListening $AstrPort) { L 'astrbot instance up (port 6199 listening)' } else { L 'astrbot port 6199 not up after 90s' }
}

Start-Sleep -Seconds 5

# ---- 4. NapCat for AstrBot (3154517648) ----
if (NapCatRunning $NapAstrExe) {
  L 'napcat-astrbot already running'
} elseif (-not (Test-Path -LiteralPath $NapAstrExe)) {
  L ('napcat-astrbot exe missing: ' + $NapAstrExe)
} else {
  try {
    Start-Process -FilePath $NapAstrExe -ArgumentList $NapAstrUin -WorkingDirectory $NapAstrDir -WindowStyle Hidden
    L ('napcat-astrbot started (account ' + $NapAstrUin + ', 44498 shell, ws 6199)')
  } catch { L ('napcat-astrbot start failed: ' + $_.Exception.Message) }
  }
}

# ---- summary ----
if ($IncludeAstrbot) { $astrTag = (PortListening $AstrPort) } else { $astrTag = 'skipped' }
if ($IncludeAstrbot) { $napAstrTag = (NapCatRunning $NapAstrExe) } else { $napAstrTag = 'skipped' }
$s = 'summary: dsh=' + (PortListening $DshPort) +
     ' napcat-dsh=' + (NapCatRunning $NapDshExe) +
     ' astrbot=' + $astrTag +
     ' napcat-astrbot=' + $napAstrTag
L $s
L '=== suite run end ==='
