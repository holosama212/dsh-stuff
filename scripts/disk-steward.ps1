param(
  [ValidateSet('report','clean','protect')][string]$Cmd = 'report',
  [int]$TempHours = 6,
  [int]$KeepDshBackups = 2,
  [switch]$DryRun
)
# disk-steward.ps1 - keep this machine's disk healthy without collateral damage.
# HARD RULE: never touch anything whose path matches the protect list
# (astrbot, NapCat, and the live bot dirs). AstrBot is a companion, not junk.
# ASCII only. Run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File <this> -Cmd report|clean

$LOG = 'C:\Users\USER\dsh-plugins\disk-steward.log'
$PROTECT = @('astrbot', 'napcat', 'qq-bridge', 'dsh-desktop\harness\profiles')

function L($m) {
  $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m
  Add-Content -LiteralPath $LOG -Value $line -Encoding UTF8
  Write-Output $line
}
function Guard($p) {
  $low = $p.ToLower()
  foreach ($k in $PROTECT) { if ($low.Contains($k)) { return $false } }
  return $true
}
function DirGB($p) {
  if (-not (Test-Path -LiteralPath $p)) { return 0 }
  $s = (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
  if ($null -eq $s) { return 0 }
  return [math]::Round($s / 1GB, 2)
}
function FreeGB {
  $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
  return [math]::Round($d.FreeSpace / 1GB, 2)
}
function Purge($p, $hours) {
  if (-not (Test-Path -LiteralPath $p)) { return 0 }
  if (-not (Guard $p)) { L ('  SKIP (protected): ' + $p); return 0 }
  $cut = (Get-Date).AddHours(-1 * $hours)
  $items = @(Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cut })
  $n = $items.Count
  if ($n -eq 0) { return 0 }
  if ($DryRun) { L ('  would remove ' + $n + ' item(s) in ' + $p); return 0 }
  foreach ($i in $items) { Remove-Item -LiteralPath $i.FullName -Recurse -Force -ErrorAction SilentlyContinue }
  return $n
}

switch ($Cmd) {

  'protect' {
    Write-Output 'PROTECT LIST (never deleted by this script):'
    foreach ($k in $PROTECT) { Write-Output ('  * ' + $k) }
    Write-Output ''
    Write-Output 'Live bot processes right now:'
    Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'QQ|NapCat|astrbot' } |
      Select-Object -First 8 | ForEach-Object {
        Write-Output ('  pid ' + $_.ProcessId + '  ' + $_.Name + '  ' + $_.ExecutablePath)
      }
  }

  'report' {
    $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
    Write-Output ('C:  total ' + [math]::Round($d.Size/1GB,1) + ' GB   free ' + [math]::Round($d.FreeSpace/1GB,1) + ' GB   used ' + [math]::Round(100*($d.Size-$d.FreeSpace)/$d.Size,1) + '%')
    Write-Output ''
    Write-Output 'known junk candidates:'
    $junk = @(
      @{N='Windows Update download cache'; P='C:\Windows\SoftwareDistribution\Download'},
      @{N='User Temp'; P='C:\Users\USER\AppData\Local\Temp'},
      @{N='Windows Temp'; P='C:\Windows\Temp'},
      @{N='pip cache'; P='C:\Users\USER\AppData\Local\pip\cache'},
      @{N='npm cache'; P='C:\Users\USER\AppData\Local\npm-cache'},
      @{N='Recycle Bin'; P='C:\$Recycle.Bin'}
    )
    foreach ($j in $junk) { Write-Output ('  {0,7} GB  {1}' -f (DirGB $j.P), $j.N) }
    Write-Output ''
    Write-Output 'DSH backup zips on Desktop (oldest pruned first):'
    Get-ChildItem 'C:\Users\USER\Desktop' -File -Filter '*.zip' -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match 'dsh-backup|DSH-selfbackup|LCS-full' } |
      Sort-Object LastWriteTime | ForEach-Object { Write-Output ('  {0,7} MB  {1}  {2}' -f [math]::Round($_.Length/1MB,1), $_.LastWriteTime.ToString('yyyy-MM-dd'), $_.Name) }
  }

  'clean' {
    $before = FreeGB
    L ('clean start, free=' + $before + ' GB, dryRun=' + [bool]$DryRun)

    $wu = 'C:\Windows\SoftwareDistribution\Download'
    $wuGB = DirGB $wu
    L ('[1] Windows Update download cache: ' + $wuGB + ' GB')
    if (-not $DryRun) {
      try { Stop-Service wuauserv -Force -ErrorAction Stop } catch { L ('    wuauserv stop failed: ' + $_.Exception.Message) }
      Get-ChildItem -LiteralPath $wu -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
      try { Start-Service wuauserv -ErrorAction Stop } catch { L ('    wuauserv start failed: ' + $_.Exception.Message) }
    }
    L ('    after: ' + (DirGB $wu) + ' GB')

    L ('[2] User Temp (' + $TempHours + 'h+)')
    $n = Purge 'C:\Users\USER\AppData\Local\Temp' $TempHours
    L ('    removed ' + $n + ' items, now ' + (DirGB 'C:\Users\USER\AppData\Local\Temp') + ' GB')

    L ('[3] Windows Temp (24h+)')
    $n = Purge 'C:\Windows\Temp' 24
    L ('    removed ' + $n + ' items')

    foreach ($c in @('C:\Users\USER\AppData\Local\pip\cache', 'C:\Users\USER\AppData\Local\npm-cache')) {
      $g = DirGB $c
      L ('[4] cache ' + $c + ': ' + $g + ' GB')
      if (-not $DryRun -and (Guard $c)) { Remove-Item -LiteralPath $c -Recurse -Force -ErrorAction SilentlyContinue }
    }

    L ('[5] prune old DSH backup zips, keep newest ' + $KeepDshBackups)
    $zips = @(Get-ChildItem 'C:\Users\USER\Desktop' -File -Filter '*.zip' -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match 'dsh-backup|DSH-selfbackup|LCS-full' } | Sort-Object LastWriteTime -Descending)
    $idx = 0
    foreach ($z in $zips) {
      $idx++
      if ($idx -le $KeepDshBackups) { L ('    keep  ' + $z.Name); continue }
      if ($DryRun) { L ('    would delete ' + $z.Name); continue }
      Remove-Item -LiteralPath $z.FullName -Force -ErrorAction SilentlyContinue
      L ('    deleted ' + $z.Name + ' (' + [math]::Round($z.Length/1MB,1) + ' MB)')
    }

    $after = FreeGB
    L ('clean done, free=' + $after + ' GB, freed=' + [math]::Round($after - $before, 2) + ' GB')
  }
}
