param(
  [Parameter(Mandatory = $true)][string]$Prompt,
  [string]$Name = 'nai',
  [int]$Count = 1,
  [string]$Size = '832x1216',
  [switch]$Parallel,
  [switch]$FreeOnly,
  [switch]$PaidOnly
)

# Generic NAI (danbooru-tag) image generator with two key pools:
#   free:  nai.rinko.ai            keys NAI_API_KEY / NAI_API_KEY_2 ...    -> ONE image per key per run, then queues (~20s, sometimes 401)
#   paid:  love.auroralove.cc/api  keys AURORA_API_KEY / AURORA_API_KEY_2 -> many concurrent images on one key (verified 4 at once)
# Prompt MUST be English danbooru-style tags; Chinese prose produces unrelated images.
# Files land in the QQ media dir (only sendable dir), named sticker-<Name>-<HHmmss>-<i>.png

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot 'nai-keys.ps1')

$mediaDir = 'C:\Users\USER\AppData\Roaming\dsh-desktop\harness\media\onebot'
if (-not (Test-Path $mediaDir)) { New-Item -ItemType Directory -Force -Path $mediaDir | Out-Null }

$stamp = Get-Date -Format 'HHmmss'
$worker = Join-Path $PSScriptRoot 'nai-one.ps1'

# -Parallel: one child process per image => real concurrency.
# Slot plan: spend each free key on exactly one image (they queue after that),
# then put every remaining slot on the paid relay. A failed free slot is
# re-run on the paid relay with the same output path.
if ($Parallel) {
  $freeKeys = @()
  if (-not $PaidOnly) {
    # Get-NaiKeys hands back a NESTED array (return ,$keys), so a plain
    # @(Get-NaiKeys) gives Count=1 whose [0] is the whole key list. That blob as
    # one Bearer header = 401 and the run silently slides onto the paid relay.
    # Flatten it the same way nai-free.ps1 / nai-parallel.ps1 already do (2026-11-20).
    try {
      foreach ($item in @(Get-NaiKeys)) {
        if ($item -is [System.Array]) {
          foreach ($x in $item) { if ([string]$x -ne '' -and $freeKeys -notcontains [string]$x) { $freeKeys += [string]$x } }
        }
        elseif ([string]$item -ne '' -and $freeKeys -notcontains [string]$item) { $freeKeys += [string]$item }
      }
    } catch { $freeKeys = @() }
  }
  $aur = $null
  if (-not $FreeOnly) {
    try { $aur = Get-AuroraConfig } catch { $aur = $null }
  }
  if ($null -eq $aur -and $freeKeys.Count -eq 0) { throw 'no usable key (free and paid both empty)' }

  $slots = New-Object System.Collections.ArrayList
  $i = 0
  $freeSlots = [Math]::Min($freeKeys.Count, $Count)
  for ($k = 0; $k -lt $freeSlots; $k++) {
    $i++
    $out = Join-Path $mediaDir ('sticker-' + $Name + '-' + $stamp + '-' + $i + '.png')
    $j = Start-Job -FilePath $worker -ArgumentList $freeKeys[$k], $out, $Prompt, $Size, 'https://nai.rinko.ai'
    [void]$slots.Add([pscustomobject]@{ job = $j; out = $out; paid = $false })
  }
  while ($i -lt $Count) {
    $i++
    $out = Join-Path $mediaDir ('sticker-' + $Name + '-' + $stamp + '-' + $i + '.png')
    if ($null -ne $aur) {
      $ak = $aur.keys[($i - 1) % $aur.keys.Count]
      $j = Start-Job -FilePath $worker -ArgumentList $ak, $out, $Prompt, $Size, $aur.base
      [void]$slots.Add([pscustomobject]@{ job = $j; out = $out; paid = $true })
    } else {
      $fk = $freeKeys[($i - 1) % $freeKeys.Count]
      $j = Start-Job -FilePath $worker -ArgumentList $fk, $out, $Prompt, $Size, 'https://nai.rinko.ai'
      [void]$slots.Add([pscustomobject]@{ job = $j; out = $out; paid = $false })
    }
  }

  $slots | ForEach-Object { $_.job } | Wait-Job | Out-Null
  $retry = @()
  foreach ($s in $slots) {
    $lines = @(Receive-Job $s.job)
    $lines | ForEach-Object { Write-Output $_ }
    $txt = $lines -join "`n"
    if ((-not $s.paid) -and ($null -ne $aur) -and ($txt -match 'FAIL')) { $retry += $s.out }
  }
  $slots | ForEach-Object { Remove-Job $_.job }

  if ($retry.Count -gt 0) {
    Write-Output ('retry ' + $retry.Count + ' failed slot(s) on paid relay')
    $rj = @()
    $n = 0
    foreach ($o in $retry) {
      $ak = $aur.keys[$n % $aur.keys.Count]
      $n++
      $rj += Start-Job -FilePath $worker -ArgumentList $ak, $o, $Prompt, $Size, $aur.base
    }
    $rj | Wait-Job | Out-Null
    $rj | Receive-Job | ForEach-Object { Write-Output $_ }
    $rj | Remove-Job
  }
  return
}

$resp = Invoke-NaiImage -Prompt $Prompt -N $Count -Size $Size

$i = 0
foreach ($item in $resp.data) {
  $i++
  if (-not $item.b64_json) { Write-Output ('NO_B64 item ' + $i); continue }
  $bytes = [Convert]::FromBase64String($item.b64_json)
  $file = Join-Path $mediaDir ('sticker-' + $Name + '-' + $stamp + '-' + $i + '.png')
  [IO.File]::WriteAllBytes($file, $bytes)
  Write-Output ('OK ' + $file + ' ' + $bytes.Length + ' bytes')
}
