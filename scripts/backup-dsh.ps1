$ErrorActionPreference = 'Continue'
$root   = 'C:\Users\USER\AppData\Roaming\dsh-desktop\harness'
$stage  = 'C:\Users\USER\Desktop\_dsh-backup-stage'
$stamp  = Get-Date -Format 'yyyyMMdd-HHmm'
$zip    = 'C:\Users\USER\Desktop\dsh-backup-' + $stamp + '.zip'
$log    = 'C:\Users\USER\dsh-plugins\backup-dsh.log'

function L($m) {
  $line = (Get-Date -Format 'HH:mm:ss') + '  ' + $m
  Add-Content -LiteralPath $log -Value $line -Encoding UTF8
  Write-Output $line
}

L ('start -> ' + $zip)
if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

# 1) DSH home: everything except images and rebuildable caches.
#    media/attachments = pictures, bili-duty = video cache, cache = web cache.
$robHarness = @(
  $root, (Join-Path $stage 'harness'), '/E',
  '/XD', 'media', 'attachments', 'bili-duty', 'cache',
  '/XF', '*.png', '*.jpg', '*.jpeg', '*.webp', '*.gif', '*.mp4', '*.webm', '*.mp3', '*.wav', '*.silk',
  '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP'
)
& robocopy @robHarness | Out-Null
L ('harness copied, rc=' + $LASTEXITCODE)

# 2) plugins / scripts
& robocopy 'C:\Users\USER\dsh-plugins' (Join-Path $stage 'dsh-plugins') /E /XF '*.png' '*.jpg' '*.webp' /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
L ('dsh-plugins copied, rc=' + $LASTEXITCODE)

# 3) .dsh (meme packs are images -> memes dir skipped)
& robocopy 'C:\Users\USER\.dsh' (Join-Path $stage 'dot-dsh') /E /XD 'memes' /XF '*.png' '*.jpg' '*.webp' '*.gif' /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
L ('.dsh copied, rc=' + $LASTEXITCODE)

# 4) loose files worth keeping
# non-ASCII names are matched by extension so this script stays pure ASCII
$desktop = 'C:\Users\USER\Desktop'
$loose = @(
  @{ q = '*.xlsx'; d = 'desktop' },
  @{ q = '*V19*.json'; d = 'desktop' },
  @{ q = '*.json'; d = 'desktop' }
)
foreach ($f in $loose) {
  foreach ($src in @(Get-ChildItem -LiteralPath $desktop -Filter $f.q -File -ErrorAction SilentlyContinue)) {
    $dst = Join-Path (Join-Path $stage $f.d) $src.Name
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    if (-not (Test-Path -LiteralPath $dst)) {
      Copy-Item -LiteralPath $src.FullName -Destination $dst -Force
      L ('copied desktop file: ' + $src.Name)
    }
  }
}

# 5) workspace notes (skip if huge)
$ws = 'C:\Users\USER\Documents\deepseek-harness\default-workspace'
if (Test-Path $ws) {
  & robocopy $ws (Join-Path $stage 'workspace') /E /XD 'node_modules' '.git' /XF '*.png' '*.jpg' '*.webp' /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  L ('workspace copied, rc=' + $LASTEXITCODE)
}

$st = Get-ChildItem $stage -Recurse -File | Measure-Object Length -Sum
L ('stage: {0:N1} MB / {1} files' -f ($st.Sum / 1MB), $st.Count)

# 6) zip it
if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }
& tar.exe -a -c -f $zip -C $stage .
L ('tar rc=' + $LASTEXITCODE)
if (Test-Path $zip) {
  $z = Get-Item -LiteralPath $zip
  L ('zip ok: {0:N1} MB  {1}' -f ($z.Length / 1MB), $z.FullName)
} else {
  L 'zip MISSING'
}
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
L 'stage removed'
