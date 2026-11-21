param(
  [Parameter(Mandatory = $true)][string]$Prompt,
  [string]$Name = 'free',
  [int]$Count = 1,
  [string]$Size = '832x1216',
  [int]$PerKeyTimeout = 40,
  [int]$MaxParallel = 8,
  [string]$Proxy = 'http://127.0.0.1:7897',
  [int]$KeyOffset = 0,
  [string[]]$Keys = @(),
  [int]$Redundant = 2,
  # Artist string, Chef-gallery style: "name:0.8, other:0.6" -> (artist:name:0.8), (artist:other:0.6)
  # appended to the prompt head. Bare "name" without weight -> (artist:name:0.8) default weight.
  [string]$Artist = '',
  # Skip the free pool entirely and go straight to the paid relay, which happily
  # takes several images at once. Use when the free relay is queueing badly and
  # speed matters more than quota.
  [switch]$SkipFree,
  [string]$Model = 'nai-diffusion-4-5-full',
  [int]$Steps = 0,
  [double]$CfgScale = 0,
  [string]$Seed = '',
  [string]$Sampler = '',
  [string]$NoiseSchedule = ''
)

# Free relay batch generator.
# One image per key, 40s cap. Each image is fired on two free keys at once
# (Redundant=2) and the first lane back wins; whatever still misses goes
# straight to the paid relay in the same run.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'nai-keys.ps1')

# ---- artist string (same convention as the gallery page's copy button) ----
if ($Artist -ne '') {
  $ap = @()
  foreach ($a in ($Artist -split ',')) {
    $t = $a.Trim()
    if ($t -eq '') { continue }
    if ($t -match '^\(artist:') { $ap += $t }
    elseif ($t -match '^([^:]+):([0-9.]+)$') { $ap += ('(artist:' + $Matches[1].Trim() + ':' + $Matches[2] + ')') }
    else { $ap += ('(artist:' + $t + ':0.8)') }
  }
  if ($ap.Count -gt 0) { $Prompt = (($ap -join ', ') + ', ' + $Prompt) }
}

$mediaDir = 'C:\Users\USER\AppData\Roaming\dsh-desktop\harness\media\onebot'
if (-not (Test-Path -LiteralPath $mediaDir)) { New-Item -ItemType Directory -Force -Path $mediaDir | Out-Null }

# ---- residue-sweep: a killed run leaves <name>.req.json / <name>.resp.json next to
# the png in the media dir (finally never executes). Sweep stale ones (>30 min) so the
# image dir does not slowly fill with multi-megabyte response dumps.
try {
  $rsCut = (Get-Date).AddMinutes(-30)
  $rsOld = @(Get-ChildItem -LiteralPath $mediaDir -File -Force -ErrorAction SilentlyContinue |
             Where-Object { ($_.Extension -eq '.json') -and ($_.Name -like '*.req.json' -or $_.Name -like '*.resp.json') -and ($_.LastWriteTime -lt $rsCut) })
  $rsBytes = 0
  foreach ($rsF in $rsOld) { $rsBytes += $rsF.Length; Remove-Item -LiteralPath $rsF.FullName -Force -ErrorAction SilentlyContinue }
  if ($rsOld.Count -gt 0) { Write-Output ('residue-sweep: removed ' + $rsOld.Count + ' file(s) ' + [math]::Round($rsBytes/1KB,0) + ' KB') }
} catch {}

$keys = @()
if ($Keys.Count -gt 0) {
  foreach ($k0 in $Keys) { if ($k0 -ne ''-and $keys -notcontains [string]$k0) { $keys += [string]$k0 } }
} else {
  foreach ($item in @(Get-NaiKeys)) {
    if ($item -is [System.Array]) {
      foreach ($x in $item) { if ($keys -notcontains [string]$x) { $keys += [string]$x } }
    }
    elseif ($keys -notcontains [string]$item) { $keys += [string]$item }
  }
}
if ($keys.Count -eq 0) { throw 'no NAI_API_KEY entries in credentials.yaml' }
$guard = Join-Path $PSScriptRoot 'nai-node.ps1'
if (Test-Path -LiteralPath $guard) {
  try { $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $guard -Quiet 2>&1 } catch { }
}
Write-Output ("keys: " + $keys.Count + " -> " + (($keys | ForEach-Object { $_.Substring(5,6) }) -join ' '))

$fastFile = Join-Path $PSScriptRoot 'nai-free-fast.txt'
$ordered = New-Object System.Collections.ArrayList
if (Test-Path -LiteralPath $fastFile) {
  $fast = (Get-Content -LiteralPath $fastFile -First 1).Trim()
  if ($fast -ne ''-and ($keys -contains $fast)) { [void]$ordered.Add($fast) }
}
foreach ($k in $keys) { if (-not $ordered.Contains($k)) { [void]$ordered.Add($k) } }

$stamp = Get-Date -Format 'HHmmss'
$worker = Join-Path $PSScriptRoot 'nai-free-one.ps1'
$sw0 = [Diagnostics.Stopwatch]::StartNew()
$slots = @()

$plans = @()
for ($i = 1; $i -le $Count; $i++) {
  $outPath = [string](Join-Path $mediaDir ("sticker-" + $Name + "-" + $stamp + "-" + $i + ".png"))
  $offset = (($i - 1) + $KeyOffset) % $ordered.Count
  $rot = @()
  for ($j = 0; $j -lt $ordered.Count; $j++) { $rot += [string]$ordered[($offset + $j) % $ordered.Count] }
  $off2 = ($offset + 2) % $ordered.Count
  $rot2 = @()
  for ($j = 0; $j -lt $ordered.Count; $j++) { $rot2 += [string]$ordered[($off2 + $j) % $ordered.Count] }
  $plans += [pscustomobject]@{ out = $outPath; keyList = [string]($rot -join ','); keyList2 = [string]($rot2 -join ','); idx = $i }
}

# The free relay throttles per account: 2 keys in flight come back in ~16s,
# 4 keys in flight leave one or two queued past any sane cap. So run in waves.
$runner = {
  param($workerExe, $keyString, $outFile, $promptText, $sizeText, $capSeconds, $proxyUrl)
  & $workerExe -Keys $keyString -Out $outFile -Prompt $promptText -Size $sizeText -PerKeyTimeout $capSeconds -Proxy $proxyUrl
}

$waveSize = $MaxParallel
if ($waveSize -lt 1) { $waveSize = 1 }
# Redundant lanes: one image is fired on two different free keys at once and the
# first one back wins. A key that queues past the cap is the single biggest time
# sink (~40s wasted per image), and free quota is plentiful, so spend two keys.
$lanes = 2
if ($Redundant -lt 1) { $lanes = 1 } elseif ($Redundant -gt 3) { $lanes = 2 } else { $lanes = [int]$Redundant }
if (-not $SkipFree) {
for ($p = 0; $p -lt $plans.Count; $p += $waveSize) {
  $batch = @($plans | Select-Object -Skip $p -First $waveSize)
  $live = New-Object System.Collections.ArrayList
  foreach ($pl in $batch) {
    $outA = [string]$pl.out
    $keysA = [string]$pl.keyList
    $job = Start-Job -ScriptBlock $runner -ArgumentList ([string]$worker), $keysA, $outA, $Prompt, $Size, $PerKeyTimeout, $Proxy
    [void]$live.Add([pscustomobject]@{ job = $job; out = $outA; idx = $pl.idx })
    if ($lanes -ge 2) {
      $out2 = $outA + '.b'
      $keysB = [string]$pl.keyList2
      $job2 = Start-Job -ScriptBlock $runner -ArgumentList ([string]$worker), $keysB, $out2, $Prompt, $Size, $PerKeyTimeout, $Proxy
      [void]$live.Add([pscustomobject]@{ job = $job2; out = $out2; idx = $pl.idx })
    }
  }
  while ($live.Count -gt 0) {
    $jobIds = @($live | ForEach-Object { $_.job })
    $hit = Wait-Job -Job $jobIds -Any
    $pos = -1
    for ($q = 0; $q -lt $live.Count; $q++) { if ($live[$q].job.Id -eq $hit.Id) { $pos = $q; break } }
    if ($pos -lt 0) { break }
    $s = $live[$pos]
    $txt = ((Receive-Job -Job $s.job) -join "`n")
    if ($txt) {
      $keep = @($txt -split "`n" | Where-Object { $_ -ne ''-and -not (($s.out -like '*.b') -and ($_ -like 'FAIL*')) })
      if ($keep.Count -gt 0) { Write-Output ($keep -join "`n") }
    }
    Remove-Job -Job $s.job -Force
    $live.RemoveAt($pos)
    if (Test-Path -LiteralPath $s.out) {
      # This lane produced the image; rename to the canonical name and kill its twin.
      $final = [string](Join-Path $mediaDir ("sticker-" + $Name + "-" + $stamp + "-" + $s.idx + ".png"))
      if ($s.out -ne $final) { Move-Item -LiteralPath $s.out -Destination $final -Force }
      $twins = @($live | Where-Object { $_.idx -eq $s.idx })
      foreach ($o in $twins) {
        try { Stop-Job -Job $o.job -ErrorAction SilentlyContinue } catch { }
        try { Remove-Job -Job $o.job -Force -ErrorAction SilentlyContinue } catch { }
        [void]$live.Remove($o)
      }
    }
  }
  Get-ChildItem -LiteralPath $mediaDir -Filter ('sticker-' + $Name + '-' + $stamp + '*.b*') -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}
}
Write-Output ("free-done: " + [math]::Round($sw0.Elapsed.TotalSeconds,1) + "s")

if ($SkipFree) { Write-Output 'skip-free: paid relay only' }

$missing = @()
foreach ($s in $plans) {
  $p = [string]$s.out
  if ($p -eq '') { continue }
  if (-not (Test-Path -LiteralPath $p)) { $missing += $p }
}
Write-Output ("free-hit: " + ($plans.Count - $missing.Count) + "/" + $plans.Count)

if ($missing.Count -eq 0) {
  Write-Output 'all-done'
  exit 0
}

# Paid relay takes over the missing slots right away.
$aur = $null
try { $aur = Get-AuroraConfig } catch { $aur = $null }
if ($null -eq $aur) {
  Write-Output 'paid-fallback: no aurora config'
  exit 1
}
$aurKeys = @($aur.keys)
$aurBase = [string]$aur.base
if ($aurKeys.Count -eq 0) {
  Write-Output 'paid-fallback: no aurora key'
  exit 1
}
Write-Output ("paid-fallback: " + $missing.Count + " slot(s), " + $aurKeys.Count + " key(s)")

$paidWorker = Join-Path $PSScriptRoot 'nai-one.ps1'
$round = 0
while ($missing.Count -gt 0 -and $round -lt 3) {
  $round++
  $jobs = @()
  $n = 0
  foreach ($p in $missing) {
    $pk = [string]$aurKeys[$n % $aurKeys.Count]
    $n++
    $pp = [string]$p
    if ($pp -notmatch '^[A-Za-z]:\\') { Write-Output ('bad-path skip: ' + $pp); continue }
    $jobs += Start-Job -ScriptBlock {
      param($workerExe, $apiKey, $outFile, $promptText, $sizeText, $baseUrl, $model, $steps, $cfg, $seed, $sampler, $noise)
      if ([string]::IsNullOrEmpty($model)) { $model = 'nai-diffusion-4-5-full' }
      $a2 = @{ Key = $apiKey; Out = $outFile; Prompt = $promptText; Size = $sizeText; Base = $baseUrl; Model = $model }
      if ([double]$steps -gt 0) { $a2.Steps = [int]$steps }
      if ([double]$cfg -gt 0) { $a2.CfgScale = [double]$cfg }
      if ($seed -ne '') { $a2.Seed = [string]$seed }
      if ($sampler -ne '') { $a2.Sampler = [string]$sampler }
      if ($noise -ne '') { $a2.NoiseSchedule = [string]$noise }
      & $workerExe @a2
    } -ArgumentList $paidWorker, $pk, $pp, $Prompt, $Size, $aurBase, $Model, $Steps, $CfgScale, $Seed, $Sampler, $NoiseSchedule
  }
  if ($jobs.Count -eq 0) { break }
  $jobs | Wait-Job | Out-Null
  $jobs | Receive-Job | ForEach-Object { Write-Output ([string]$_) }
  $jobs | Remove-Job -Force
  $still = @()
  foreach ($p in $missing) { if (-not (Test-Path -LiteralPath ([string]$p))) { $still += [string]$p } }
  $missing = $still
  if ($missing.Count -gt 0) { Write-Output ("paid-fallback round " + $round + ": still " + $missing.Count) }
}

Write-Output ("total: " + [math]::Round($sw0.Elapsed.TotalSeconds,1) + "s")
if ($missing.Count -eq 0) { Write-Output 'all-done'; exit 0 }
Write-Output ("FAILED " + $missing.Count + " slot(s)")
exit 1