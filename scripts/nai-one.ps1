param([string]$Key,[string]$Out,[string]$Prompt,[string]$Size='832x1216',[string]$Base='https://nai.rinko.ai',[string]$Model='nai-diffusion-4-5-full',[int]$Steps=0,[double]$CfgScale=0,[string]$Seed='',[string]$Sampler='',[string]$NoiseSchedule='')
$ErrorActionPreference='Stop'
$neg = ''
$here = $PSScriptRoot
if (-not $here) { try { $here = Split-Path -Parent $PSCommandPath } catch { $here = '' } }
if (-not $here) { $here = 'C:\Users\USER\dsh-plugins' }
$negFile = Join-Path $here 'nai-negative.txt'
if (Test-Path -LiteralPath $negFile) { $neg = ((Get-Content -LiteralPath $negFile -Raw) -replace '\s+', ' ').Trim() }
$bodyFile = Join-Path $here 'nai-body.txt'
$bodyLock = ''
if (Test-Path -LiteralPath $bodyFile) { $bodyLock = ((Get-Content -LiteralPath $bodyFile -Raw) -replace '\s+', ' ').Trim() }
$fullPrompt = $Prompt
if ($bodyLock -ne '') { $fullPrompt = $Prompt + ', ' + $bodyLock }
$bodyObj = @{model=$Model;prompt=$fullPrompt;n=1;size=$Size;response_format='b64_json'}
if ($neg -ne '') { $bodyObj.negative_prompt = $neg }
if ($Steps -gt 0) { $bodyObj.steps = $Steps }
if ($CfgScale -gt 0) { $bodyObj.cfg_scale = $CfgScale }
if ($Seed -ne '') { if ($Model -match 'nai-diffusion-5') { $bodyObj.seed = [string]$Seed } else { $bodyObj.seed = [int64]$Seed } }
if ($Sampler -ne '') { $bodyObj.sampler = $Sampler }
if ($NoiseSchedule -ne '') { $bodyObj.noise_schedule = $NoiseSchedule }
$body = $bodyObj | ConvertTo-Json -Compress
$h = @{ Authorization = "Bearer $Key"; 'Content-Type' = 'application/json' }
$sw = [Diagnostics.Stopwatch]::StartNew()
$uri = $Base.TrimEnd('/') + '/v1/images/generations'
try {
  $r = Invoke-RestMethod -Uri $uri -Method Post -Headers $h -Body $body -TimeoutSec 300
  $bytes = [Convert]::FromBase64String($r.data[0].b64_json)
  [IO.File]::WriteAllBytes($Out,$bytes)
  Write-Output ("OK " + $Out + " " + $bytes.Length + " bytes " + [math]::Round($sw.Elapsed.TotalSeconds,1) + "s model=" + $Model)
} catch {
  Write-Output ("FAIL " + $sw.Elapsed.TotalSeconds.ToString("0.0") + "s " + $_.Exception.Message)
}