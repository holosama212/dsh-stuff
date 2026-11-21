param(
  [Parameter(Mandatory = $true)][string]$Pose,
  [string]$Name = 'whale',
  [int]$Count = 1,
  [string]$Size = '512x512',
  [switch]$Nsfw,
  [string]$NsfwTags = ''
)

# Generates an on-model whale-girl-maid sticker via the NAI relay and writes it
# straight into the QQ media dir (the only dir sendable in every chat).
# Pose must be ENGLISH danbooru-style tags, e.g. "sleepy pose yawning".
# Chinese prose prompts are ignored by the model and produce unrelated images.
# -Nsfw appends the explicit tag set (tags taken from nsfw-tags.md); -NsfwTags
# adds extra English tags on top, e.g. -NsfwTags "spread pussy, cum".

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Template = 'chibi anime sticker, whale girl maid, navy blue gradient long wavy hair with cyan tips, shining blue eyes, white lace frilled maid headband, navy blue maid dress, white frilled apron printed with a small blue whale, whale tail fin, blue wave splash accents, thick white die-cut sticker border, sparkles, plain white background, no text, {POSE}, full body'

$mediaDir = 'C:\Users\USER\AppData\Roaming\dsh-desktop\harness\media\onebot'
if (-not (Test-Path $mediaDir)) { New-Item -ItemType Directory -Force -Path $mediaDir | Out-Null }

# multi-key rotation helper (NAI_API_KEY, NAI_API_KEY_2, ...)
. (Join-Path $PSScriptRoot 'nai-keys.ps1')

$prompt = $Template.Replace('{POSE}', $Pose)
if ($Nsfw) {
  # Explicit set: all tags below come from nsfw-tags.md ("NSFW Tags" sheet).
  $nsfwBase = 'nsfw, nude, nipples, areolae, pussy, navel, wide hips, uncensored, completely nude'
  $prompt = $prompt.Replace('navy blue maid dress, white frilled apron printed with a small blue whale, ', '')
  $extra = $NsfwTags.Trim().Trim(',').Trim()
  $prompt = $prompt + ', ' + $nsfwBase
  if ($extra) { $prompt = $prompt + ', ' + $extra }
}
$resp = Invoke-NaiImage -Prompt $prompt -N $Count -Size $Size

$stamp = Get-Date -Format 'HHmmss'
$i = 0
foreach ($item in $resp.data) {
  $i++
  if (-not $item.b64_json) { Write-Output ('NO_B64 item ' + $i); continue }
  $bytes = [Convert]::FromBase64String($item.b64_json)
  $file = Join-Path $mediaDir ('sticker-' + $Name + '-' + $stamp + '-' + $i + '.png')
  [IO.File]::WriteAllBytes($file, $bytes)
  Write-Output ('OK ' + $file + ' ' + $bytes.Length + ' bytes')
  Write-Output ('PROMPT ' + $prompt)
}
