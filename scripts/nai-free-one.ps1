param(
  [Parameter(Mandatory = $true)][string]$Keys,
  [Parameter(Mandatory = $true)][string]$Out,
  [Parameter(Mandatory = $true)][string]$Prompt,
  [string]$Size = '832x1216',
  [int]$PerKeyTimeout = 40,
  [string]$Proxy = 'http://127.0.0.1:7897'
)

# One image, try each key in order with a short timeout, first success wins.
# Free relay returns 402 for n>1, so n is always 1 here.

$ErrorActionPreference = 'Stop'
$uri = 'https://nai.rinko.ai/v1/images/generations'
$neg = ''
$negFile = Join-Path $PSScriptRoot 'nai-negative.txt'
if (Test-Path -LiteralPath $negFile) { $neg = ((Get-Content -LiteralPath $negFile -Raw) -replace '\s+', ' ').Trim() }

$bodyFile = Join-Path $PSScriptRoot 'nai-body.txt'
$bodyLock = ''
if (Test-Path -LiteralPath $bodyFile) { $bodyLock = ((Get-Content -LiteralPath $bodyFile -Raw) -replace '\s+', ' ').Trim() }
$fullPrompt = $Prompt
if ($bodyLock -ne '') { $fullPrompt = $Prompt + ', ' + $bodyLock }

$payloadObj = @{ model = 'nai-diffusion-4-5-full'; prompt = $fullPrompt; n = 1; size = $Size; response_format = 'b64_json' }
if ($neg -ne '') { $payloadObj.negative_prompt = $neg }
$payload = $payloadObj | ConvertTo-Json -Compress

if (-not $Keys) { Write-Output 'EMPTY-PARAM Keys'; exit 2 }
if (-not $Out) { Write-Output 'EMPTY-PARAM Out'; exit 2 }
if (-not $Prompt) { Write-Output 'EMPTY-PARAM Prompt'; exit 2 }

# One key gets exactly one shot: if it misses the cap, the slot goes to the paid relay in nai-free.ps1.
# No serial second-key retry -- that only doubles the failure time.
$tried = 0
foreach ($k in ($Keys -split ',')) {
  if ($tried -ge 1) { break }
  $key = $k.Trim()
  if ($key -eq '') { continue }
  $tried++
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $tmpReq = $Out + '.req.json'
  $tmpResp = $Out + '.resp.json'
  try {
    # Use curl.exe instead of the .NET HTTP stack: same key, same body -> curl 200, HttpClient 401.
    # curl --max-time is also a hard gate while the body trickles.
    [IO.File]::WriteAllText($tmpReq, $payload, (New-Object System.Text.UTF8Encoding($false)))
    # Must call inline: splatting '@path' via @() makes curl report
    # "option --data-binary: error encountered when reading a file"; inline "@$tmpReq" works.
    if ($Proxy -and $Proxy -ne 'DIRECT') {
      $raw = (& curl.exe -s -o $tmpResp -w '%{http_code}|%{time_starttransfer}|%{time_total}' -X POST $uri -H "Authorization: Bearer $key" -H 'Content-Type: application/json' --data-binary "@$tmpReq" --max-time $PerKeyTimeout --proxy $Proxy 2>&1) -join ''
    } else {
      $raw = (& curl.exe -s -o $tmpResp -w '%{http_code}|%{time_starttransfer}|%{time_total}' -X POST $uri -H "Authorization: Bearer $key" -H 'Content-Type: application/json' --data-binary "@$tmpReq" --max-time $PerKeyTimeout 2>&1) -join ''
    }
    $raw = ([string]$raw).Trim()
    $mm = [regex]::Match($raw, '(\d{3})\|([0-9.]+)\|([0-9.]+)')
    if ($mm.Success) {
      $code = $mm.Groups[1].Value
      $stat = ' ttfb=' + $mm.Groups[2].Value + ' total=' + $mm.Groups[3].Value
    } else {
      $code = '000'
      $stat = ' raw=' + $raw.Substring(0, [Math]::Min(120, $raw.Length))
    }
    if ($code -ne '200') { throw ('http ' + $code + $stat) }
    $json = [IO.File]::ReadAllText($tmpResp, [System.Text.Encoding]::UTF8)
    # ConvertFrom-Json in PS 5.1 blows up on multi-megabyte payloads
    # ("string length exceeded max allowed length"), so pull b64_json by regex.
    $m = [regex]::Match($json, '"b64_json"\s*:\s*"([A-Za-z0-9+/=]+)"')
    if (-not $m.Success) { Write-Output ('no-b64 ' + [math]::Round($sw.Elapsed.TotalSeconds,1) + 's'); continue }
    $b64 = $m.Groups[1].Value
    $bytes = [Convert]::FromBase64String($b64)
    [IO.File]::WriteAllBytes($Out, $bytes)
    Write-Output ('OK ' + $Out + ' ' + $bytes.Length + ' bytes ' + [math]::Round($sw.Elapsed.TotalSeconds,1) + 's')
    exit 0
  } catch {
    Write-Output ('key-fail ' + [math]::Round($sw.Elapsed.TotalSeconds,1) + 's ' + $_.Exception.Message)
  } finally {
    Remove-Item -LiteralPath $tmpReq, $tmpResp -Force -ErrorAction SilentlyContinue
  }
}
Write-Output ('FAIL ' + $Out)
exit 1
