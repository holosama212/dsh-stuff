#Requires -Version 5.1
# Open the DSH Web GUI with the CURRENT token.
# A bare http://127.0.0.1:43129/ always answers 401; the token changes on every DSH restart,
# so it is read from harness.log instead of being hard-coded.
param([switch]$Print)

$ErrorActionPreference = 'Stop'
$log  = Join-Path $env:APPDATA 'dsh-desktop\logs\harness.log'
$port = 43129
$base = "http://127.0.0.1:$port/"

if (-not (Test-Path $log)) { Write-Host "[x] harness.log not found: $log"; Start-Sleep -Seconds 4; exit 2 }

$listen = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if (-not $listen) { Write-Host "[x] DSH is not running (:$port not listening). Start DSH Desktop first."; Start-Sleep -Seconds 5; exit 3 }

$pat = 'dsh web: http://127\.0\.0\.1:' + $port + '/\?token=([A-Za-z0-9_-]+)'
$hits = Select-String -Path $log -Pattern $pat -ErrorAction SilentlyContinue
if (-not $hits) { Write-Host "[x] no web token in log yet (DSH just started? retry in a few seconds)."; Start-Sleep -Seconds 5; exit 4 }

$tokens = @($hits | ForEach-Object { $_.Matches[0].Groups[1].Value })
[array]::Reverse($tokens)
$tried = 0
$ok = $null
foreach ($t in $tokens) {
  if ($tried -ge 6) { break }
  $tried++
  $url = $base + '?token=' + $t
  try {
    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 6
    if ($r.StatusCode -eq 200) { $ok = $url; break }
  } catch { }
}

if (-not $ok) {
  Write-Host "[x] none of the last $tried tokens work. Restart DSH Desktop, then run this again."
  Write-Host "    log: $log"
  Start-Sleep -Seconds 6
  exit 5
}

if ($Print) { Write-Host $ok; exit 0 }
Write-Host "[ok] $ok"
Start-Process $ok
exit 0