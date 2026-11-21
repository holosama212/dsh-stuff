param(
  [Parameter(Mandatory = $true)][string]$Specs,
  # How many spec jobs may be in flight at once. The free relay queues past ~3
  # concurrent generations (measured 2026-10-31: 8 parallel -> 2 of 8 stalled
  # past 45s), so firing all specs at once wastes more time than it saves.
  [int]$MaxJobs = 8,
  # Paid relay only: skip the free pool completely. The paid key handles several
  # images at once, so this is the fastest route when quota does not matter.
  [switch]$Paid,
  [string]$Model = '',
  [int]$Steps = 0,
  [double]$CfgScale = 0,
  [string]$Seed = ''
)
# Run nai-free.ps1 for many lines at the same time.
# Specs file: one entry per line,  name|prompt
# Each job rotates its own free keys, so N entries use N keys concurrently.
$ErrorActionPreference = 'Continue'
$runner = Join-Path $PSScriptRoot 'nai-free.ps1'
if (-not (Test-Path -LiteralPath $runner)) { throw ('missing runner: ' + $runner) }
$lines = @(Get-Content -LiteralPath $Specs -Encoding UTF8 | Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith('#') })
if ($lines.Count -eq 0) { throw 'empty specs' }
Write-Output ('specs loaded: ' + $lines.Count)
$sw = [Diagnostics.Stopwatch]::StartNew()
$jobs = @()
$ki = 0
$freeKeyCount = 4
try {
  . (Join-Path $PSScriptRoot 'nai-keys.ps1')
  $fk = @()
  foreach ($item in @(Get-NaiKeys)) {
    if ($item -is [System.Array]) { foreach ($x in $item) { if ($fk -notcontains [string]$x) { $fk += [string]$x } } }
    elseif ($fk -notcontains [string]$item) { $fk += [string]$item }
  }
  if ($fk.Count -ge 1) { $freeKeyCount = $fk.Count }
} catch { }
Write-Output ('free keys: ' + $freeKeyCount)
foreach ($line in $lines) {
  $i = $line.IndexOf('|')
  if ($i -lt 1) { Write-Output ('skip bad line: ' + $line); continue }
  $nm = $line.Substring(0, $i).Trim().TrimStart([char]0xFEFF)
  $rest = $line.Substring($i + 1)
  $j = $rest.IndexOf('|')
  $ar = ''
  if ($j -ge 0) {
    $pr = $rest.Substring(0, $j).Trim()
    $ar = $rest.Substring($j + 1).Trim()
  } else {
    $pr = $rest.Trim()
  }
  # artist field: '-' = opt out; empty = default artist string from nai-artist.txt
  if ($ar -eq '-') { $ar = '' }
  elseif ($ar -eq '') {
    $af = Join-Path $PSScriptRoot 'nai-artist.txt'
    if (Test-Path -LiteralPath $af) { $ar = (Get-Content -LiteralPath $af -TotalCount 1 -Encoding UTF8).Trim() }
  }
  # each spec starts on a DIFFERENT free key: 4 specs = 4 keys, no queueing
  $off = $ki % $freeKeyCount
  $ki++
  Write-Output ('queue: ' + $nm + ' keyOffset: ' + $off + ' artist: ' + $(if ($ar -ne '') { 'yes' } else { 'no' }))
  $jobs += Start-Job -ScriptBlock {
    param($sc, $p, $n, $koff, $a, $sf, $mdl, $steps, $cfg, $seed)
    $c = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $sc, '-Prompt', $p, '-Name', $n, '-Count', '1', '-KeyOffset', $koff, '-PerKeyTimeout', '25', '-MaxParallel', '8', '-Redundant', '2')
    if ($a -ne '') { $c += @('-Artist', $a) }
    if ($sf) { $c += '-SkipFree' }
    if ($mdl -ne '') { $c += @('-Model',$mdl) }
    if ($steps -gt 0) { $c += @('-Steps',$steps) }
    if ($cfg -gt 0) { $c += @('-CfgScale',$cfg) }
    if ($seed -ne '') { $c += @('-Seed',$seed) }
    & powershell.exe @c *>&1
  } -ArgumentList @($runner, $pr, $nm, $off, $ar, [bool]$Paid, $Model, $Steps, $CfgScale, $Seed)
  # Rolling window: keep at most $MaxJobs generations alive.
  while (@($jobs | Where-Object { $_.State -eq 'Running' }).Count -ge $MaxJobs) {
    $hit = Wait-Job -Job $jobs -Any
    try { Receive-Job -Job $hit -ErrorAction Continue } catch { Write-Output ('job-error: ' + $_.Exception.Message) }
    Remove-Job -Job $hit -Force -ErrorAction SilentlyContinue
    $jobs = @($jobs | Where-Object { $_.Id -ne $hit.Id })
  }
}
$null = $jobs | Wait-Job -Timeout 900
foreach ($j in $jobs) {
  try { Receive-Job -Job $j -ErrorAction Continue } catch { Write-Output ('job-error: ' + $_.Exception.Message) }
  Remove-Job -Job $j -Force -ErrorAction SilentlyContinue
}
$sw.Stop()
Write-Output ('parallel-done: ' + $lines.Count + ' spec(s) in ' + [int]$sw.Elapsed.TotalSeconds + 's')
