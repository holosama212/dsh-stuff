param(
  [Parameter(Mandatory = $true)][string]$Text,
  [string]$Voice = 'zh-CN-XiaoyiNeural',
  [string]$Name = 'voice'
)

# Synthesize one short line into an MP3 inside the QQ media dir, via the
# dsh-plugin-tts host route (Edge TTS). Output can be handed straight to
# qq_send_voice.
#
# Keep $Text short (one sentence is best): the route switches to progressive
# chunked playback above ~12s of speech, which returns a different payload.
# ASCII only on purpose - Windows PowerShell 5.1 mis-parses UTF-8 without BOM.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$base = 'http://127.0.0.1:43129'
$mediaDir = 'C:\Users\USER\AppData\Roaming\dsh-desktop\harness\media\onebot'
if (-not (Test-Path $mediaDir)) { New-Item -ItemType Directory -Force -Path $mediaDir | Out-Null }

$body = @{ text = $Text; voice = $Voice; provider = 'edge-tts' } | ConvertTo-Json -Compress

# Edge TTS websocket drops out now and then (closed code=1006): retry a few times.
$resp = $null
for ($try = 1; $try -le 3; $try++) {
  try {
    $resp = Invoke-RestMethod -Uri ($base + '/dsh-tts-api/speak') -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 120
    if ($resp.url) { break }
  }
  catch {
    if ($try -eq 3) { throw }
    Start-Sleep -Seconds 4
  }
}

if (-not $resp.url) {
  Write-Output ('NO_URL ' + ($resp | ConvertTo-Json -Compress))
  exit 1
}

$url = [string]$resp.url
if ($url -notmatch '^https?://') { $url = $base + $url }

$stamp = Get-Date -Format 'HHmmss'
$out = Join-Path $mediaDir ('voice-' + $Name + '-' + $stamp + '.mp3')
Invoke-WebRequest -Uri $url -OutFile $out -TimeoutSec 120 | Out-Null
$size = (Get-Item $out).Length
Write-Output ('OK ' + $out + ' ' + $size + ' bytes')
