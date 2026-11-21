# Nai node race v2: rank Clash nodes by control-plane delay, then by real 2 MB
# download through the mixed port. PS 5.1 mangles UTF-8 names from the mihomo
# API (Content-Type carries no charset), so every name is repaired by Fix-Moji.
# ASCII only. Run: powershell -NoProfile -ExecutionPolicy Bypass -File nai-race.ps1
param(
  [string]$Api = 'http://127.0.0.1:9097',
  [string]$Proxy = 'http://127.0.0.1:7897',
  [string]$ProbeUrl = 'https://speed.cloudflare.com/__down?bytes=2000000',
  [int]$Top = 4,
  [switch]$NoSwitch
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Fix-Moji([string]$s) {
  if ([string]::IsNullOrEmpty($s)) { return $s }
  $b = [Text.Encoding]::GetEncoding('ISO-8859-1').GetBytes($s)
  return [Text.Encoding]::UTF8.GetString($b)
}
function Enc([string]$s) { return [Uri]::EscapeDataString($s) }
function Switch-Group([string]$group, [string]$node) {
  $json = '{"name":' + (ConvertTo-Json $node) + '}'
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  Invoke-RestMethod -Uri ($Api + '/proxies/' + (Enc $group)) -Method Put -Body $bytes -ContentType 'application/json; charset=utf-8' -TimeoutSec 10 | Out-Null
}

$px = Invoke-RestMethod -Uri ($Api + '/proxies') -TimeoutSec 15

# manual selector group (the rule table falls through to it)
$sel = $null
$props = @($px.proxies.PSObject.Properties | Where-Object { $null -ne $_.Value.all })
foreach ($p in $props) {
  if ($p.Name -eq 'GLOBAL') { continue }
  if ($p.Value.type -ieq 'selector') { $sel = (Fix-Moji $p.Name); break }
}
if (-not $sel) { throw 'no selector group found' }
Write-Output ('selector-group: ' + $sel)

# candidate names from every group's member list; skip DIRECT/REJECT
$cand = @()
foreach ($p in $props) {
  if ($p.Name -eq 'GLOBAL') { continue }
  foreach ($m in $p.Value.all) {
    if ($m -eq 'DIRECT' -or $m -eq 'REJECT') { continue }
    $nm = (Fix-Moji $m)
    if ($cand -notcontains $nm) { $cand += $nm }
  }
}
Write-Output ('candidates: ' + $cand.Count)

$rows = @()
foreach ($n in $cand) {
  $d = -1
  try {
    $u = $Api + '/proxies/' + (Enc $n) + '/delay?url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204&timeout=5000'
    $r = Invoke-RestMethod -Uri $u -TimeoutSec 12
    $d = [int]$r.delay
  } catch { $d = -1 }
  $rows += [pscustomobject]@{ node = $n; delay = $d }
}

$ranked = @($rows | Sort-Object -Property @{E={ if ($_.delay -lt 0) { 999999 } else { $_.delay } }})
Write-Output '--- control-plane delay (ms) ---'
foreach ($r in $ranked) {
  $t = if ($r.delay -lt 0) { 'FAIL' } else { [string]$r.delay }
  Write-Output ('delay ' + $t + '  ' + $r.node)
}

$short = @($ranked | Where-Object { $_.delay -ge 0 } | Select-Object -First $Top)
Write-Output ('--- real 2MB download through ' + $Proxy + ', top ' + $short.Count + ' ---')
$results = @()
foreach ($s in $short) {
  if (-not $NoSwitch) {
    try { Switch-Group $sel $s.node } catch { Write-Output ('switch-fail ' + $s.node); continue }
  }
  $t = '0'
  $sz = '0'
  for ($try = 1; $try -le 2; $try++) {
    $w = (& curl.exe -s -o NUL -w '%{time_total} %{size_download}' --max-time 25 --proxy $Proxy $ProbeUrl 2>&1) -join ''
    $m = [regex]::Match($w, '([0-9.]+)\s+([0-9]+)')
    if ($m.Success) { $t = $m.Groups[1].Value; $sz = $m.Groups[2].Value }
  }
  Write-Output ('dl ' + $t + 's bytes=' + $sz + ' delay=' + $s.delay + '  ' + $s.node)
  $results += [pscustomobject]@{ node = $s.node; delay = $s.delay; dl = [double]$t; bytes = [long]$sz }
}

$best = @($results | Where-Object { $_.bytes -gt 1000000 } | Sort-Object dl | Select-Object -First 1)
if ($best.Count -gt 0) {
  $b = $best[0]
  Write-Output ('BEST ' + $b.node + ' dl=' + $b.dl + 's delay=' + $b.delay)
  if (-not $NoSwitch) {
    Switch-Group $sel $b.node
    Write-Output ('switched-to: ' + $b.node)
  }
  [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'nai-proxy.txt'), [string]$b.node, (New-Object System.Text.UTF8Encoding($false)))
} else {
  Write-Output 'BEST none'
}
Write-Output 'race-done'
