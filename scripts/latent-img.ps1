param(
  [Parameter(Mandatory=$true)][string]$Prompt,
  [string]$Negative = "",
  [int]$Width = 832,
  [int]$Height = 1216,
  [int]$Steps = 28,
  [string]$Sampler = "k_euler_ancestral",
  [string]$Out = ""
)
$ErrorActionPreference = "Stop"
$url   = "https://latent.moe/api/novelai/ai/generate-image"
$key   = "lat_sk_bo_Nuq0bNoZMZd99Ks8s6C-d7W1kSPpxVFeAtqlYCTg"
$media = "C:\Users\USER\AppData\Roaming\dsh-desktop\harness\media\onebot"
if (-not (Test-Path $media)) { New-Item -ItemType Directory -Force -Path $media | Out-Null }
if (-not $Out) { $Out = "ltimg_" + (Get-Date -Format "HHmmss") }

$params = [ordered]@{ width = $Width; height = $Height; steps = $Steps; sampler = $Sampler }
if ($Negative) { $params["uc"] = $Negative; $params["negative_prompt"] = $Negative }
$body = [ordered]@{ input = $Prompt; model = "nai-diffusion-4-5-full"; parameters = $params } | ConvertTo-Json -Compress -Depth 6
$bf = Join-Path $env:TEMP ("lti_" + [guid]::NewGuid().ToString() + ".json")
[IO.File]::WriteAllText($bf, $body, (New-Object System.Text.UTF8Encoding($false)))
$zip = Join-Path $env:TEMP ("lti_" + [guid]::NewGuid().ToString() + ".zip")

$code = curl.exe -s -m 180 -o $zip -w "%{http_code}" -X POST $url `
  -H "Authorization: Bearer $key" -H "Content-Type: application/json" `
  -H "Idempotency-Key: $([guid]::NewGuid())" --data-binary "@$bf" 2>$null
Remove-Item $bf -Force -ErrorAction SilentlyContinue

if ($code -ne "200" -or -not (Test-Path $zip)) {
  "FAIL http=$code"
  if (Test-Path $zip) { "BODY: " + (Get-Content $zip -Raw -ErrorAction SilentlyContinue) }
  exit 1
}
$dir = Join-Path $env:TEMP ("lti_x_" + [guid]::NewGuid().ToString())
try {
  Expand-Archive -Path $zip -DestinationPath $dir -Force
  $png = Get-ChildItem $dir -Filter *.png | Select-Object -First 1
  if (-not $png) { "FAIL no png in zip"; exit 1 }
  $dst = Join-Path $media ($Out + ".png")
  Copy-Item $png.FullName $dst -Force
  "OK $dst size=$((Get-Item $dst).Length)"
} finally {
  Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item $zip -Force -ErrorAction SilentlyContinue
}
