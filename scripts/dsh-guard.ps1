param(
  [ValidateSet('Ensure', 'Watch', 'Restart')][string]$Mode = 'Ensure',
  [int]$WaitSeconds = 180,
  [int]$IntervalSeconds = 30,
  [string]$Log = 'C:\Users\USER\dsh-plugins\dsh-guard.log'
)

$ErrorActionPreference = 'Continue'
$App = 'C:\Program Files\DSH Desktop\DSH Desktop.exe'
$Root = 'C:\Program Files\DSH Desktop\'
$Port = 43129
$OffFile = 'C:\Users\USER\dsh-plugins\guard-off'

function L($m) {
  try {
    Add-Content -Path $Log -Value ((Get-Date -Format o) + '  [' + $PID + '/' + $Mode + '] ' + $m) -Encoding UTF8
  } catch { }
}

function Get-DshProcs {
  @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($Root) })
}

function Get-Alive { (Get-DshProcs).Count -gt 0 }

function Test-Port {
  @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue).Count -gt 0
}

function Start-Dsh {
  # 1) WMI create: leaves the caller's job object and inherits the service env,
  #    so the app is not killed when the process tree that spawned us dies.
  try {
    $r = ([wmiclass]'Win32_Process').Create('"' + $App + '"')
    L ('wmi create returnValue=' + $r.ReturnValue + ' pid=' + $r.ProcessId)
    if ($r.ReturnValue -eq 0) { return $true }
  } catch { L ('wmi create failed: ' + $_.Exception.Message) }

  # 2) fresh environment (drops ELECTRON_RUN_AS_NODE / DSH_* leftovers)
  try {
    Start-Process -FilePath $App -UseNewEnvironment -ErrorAction Stop
    L 'start-process -UseNewEnvironment ok'
    return $true
  } catch { L ('start-process failed: ' + $_.Exception.Message) }

  # 3) through explorer, so the app gets the interactive shell env
  try {
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $App + '"') -ErrorAction Stop
    L 'explorer launch ok'
    return $true
  } catch { L ('explorer launch failed: ' + $_.Exception.Message) }

  return $false
}

function Wait-Up($sec) {
  $deadline = (Get-Date).AddSeconds($sec)
  while ((Get-Date) -lt $deadline) {
    if (Test-Port) { return $true }
    Start-Sleep -Seconds 2
  }
  return (Test-Port)
}

function Stop-Dsh {
  $procs = Get-DshProcs
  L ('stop: procs=' + $procs.Count)
  foreach ($p in $procs) { try { $null = $p.CloseMainWindow() } catch { } }
  Start-Sleep -Seconds 8
  foreach ($p in (Get-DshProcs)) { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch { } }
  Start-Sleep -Seconds 3
  L ('stop done, alive=' + (Get-DshProcs).Count)
}

function Ensure-Running {
  if ((Get-Alive) -and (Test-Port)) { return 'already-up' }
  if (-not (Get-Alive)) {
    L 'dsh not running -> starting'
    if (-not (Start-Dsh)) { L 'all launch methods failed'; return 'launch-failed' }
    if (Wait-Up $WaitSeconds) { L 'dsh up after start'; return 'started' }
    L 'started but port never came up'
    return 'start-timeout'
  }
  L 'process alive but port down (still booting?)'
  if (Wait-Up $WaitSeconds) { L 'port came back by itself'; return 'recovered' }
  L 'process alive, port still down -> hard restart'
  Stop-Dsh
  $null = Start-Dsh
  if (Wait-Up $WaitSeconds) { L 'recovered after hard restart'; return 'restarted' }
  return 'still-down'
}

L ('--- start pid=' + $PID + ' mode=' + $Mode)

switch ($Mode) {
  'Ensure' {
    $r = Ensure-Running
    L ('ensure -> ' + $r)
    $r
  }
  'Restart' {
    Stop-Dsh
    $ok = $false
    for ($i = 1; $i -le 3 -and -not $ok; $i++) {
      L ('launch attempt ' + $i)
      $null = Start-Dsh
      $ok = Wait-Up 90
      L ('attempt ' + $i + ' port up=' + $ok)
      if (-not $ok) { Stop-Dsh }
    }
    L ('restart -> port ' + $ok)
    if ($ok) { 'restarted' } else { 'failed' }
  }
  'Watch' {
    L 'watch loop start'
    $tick = 0
    while (-not (Test-Path $OffFile)) {
      $tick++
      $r = Ensure-Running
      if ($r -ne 'already-up') { L ('watch ensure -> ' + $r) }
      elseif ($tick % 15 -eq 0) { L ('heartbeat tick=' + $tick + ' dsh alive, port up') }
      Start-Sleep -Seconds $IntervalSeconds
    }
    L 'guard-off present -> watch loop exit'
  }
}
