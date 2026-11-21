$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stage = Join-Path $env:TEMP ('lcs-full-' + $stamp)
$out   = Join-Path 'C:\Users\USER\Desktop' ('LCS-full-' + $stamp + '.zip')
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$skipExt = @('.png','.jpg','.jpeg','.webp','.gif','.bmp','.avif','.heic','.tiff','.psd','.ico','.mp4','.mov','.mkv','.webm','.avi','.flv','.wmv','.exe','.msi','.dmg','.iso','.7z','.rar','.tar','.gz','.zip')
$skipDirs = @('node_modules','.git','cache','.cache','Code Cache','GPUCache','CachedData','blob_storage')

function Test-SkipFile($f) {
  if ($skipExt -contains $f.Extension.ToLower()) { return $true }
  $parts = $f.FullName -split '\\'
  foreach ($p in $parts) { if ($skipDirs -contains $p) { return $true } }
  return $false
}

function CopyTree($src, $dstRel) {
  if (-not (Test-Path $src)) { Write-Output ('skip missing: ' + $src); return }
  $dst = Join-Path $stage $dstRel
  $files = Get-ChildItem $src -Recurse -File -Force -ErrorAction SilentlyContinue
  $n = 0
  foreach ($f in $files) {
    if (Test-SkipFile $f) { continue }
    $rel = $f.FullName.Substring($src.Length).TrimStart('\')
    $target = Join-Path $dst $rel
    $dir = Split-Path $target -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Copy-Item $f.FullName $target -Force -ErrorAction SilentlyContinue
    $n = $n + 1
  }
  Write-Output ('copied: ' + $dstRel + '  files=' + $n)
}

$H = 'C:\Users\USER\AppData\Roaming\dsh-desktop\harness'
$D = 'C:\Users\USER\.dsh'
$B = 'C:\Users\USER\qq-bridge-0.2.1-r1'

CopyTree 'C:\Users\USER\dsh-plugins' 'dsh-plugins'
CopyTree $D 'dsh-home'
CopyTree (Join-Path $H 'sessions') 'harness\sessions'
CopyTree (Join-Path $H 'sessions-deleted-backup') 'harness\sessions-deleted-backup'
CopyTree (Join-Path $H 'sessions-retired-quarantine') 'harness\sessions-retired-quarantine'
CopyTree (Join-Path $H 'memories') 'harness\memories'
CopyTree (Join-Path $H 'skills') 'harness\skills'
CopyTree (Join-Path $H 'plugins') 'harness\plugins'
CopyTree (Join-Path $H 'storages') 'harness\storages'
CopyTree (Join-Path $H 'attachments') 'harness\attachments'
CopyTree (Join-Path $H 'fish-memory') 'harness\fish-memory'
CopyTree (Join-Path $H 'fish-memory-backup') 'harness\fish-memory-backup'
CopyTree (Join-Path $H 'qqbot') 'harness\qqbot'
CopyTree (Join-Path $H 'dsh-image-gen') 'harness\dsh-image-gen'
CopyTree (Join-Path $H 'dsh-purge') 'harness\dsh-purge'
CopyTree (Join-Path $H 'redteam') 'harness\redteam'
CopyTree (Join-Path $H 'self-evolve') 'harness\self-evolve'
CopyTree (Join-Path $H '.agent-presets') 'harness\.agent-presets'
CopyTree (Join-Path $H 'logs') 'harness\logs'
CopyTree (Join-Path $H 'media') 'harness\media'
CopyTree (Join-Path $H 'profiles\web') 'harness\profiles\web'
# patched plugin code (node_modules excluded; these two copied explicitly)
$nmSrc = Join-Path $H 'profiles\web\node_modules'
foreach ($pair in @(@('dsh-onebot-qq\lib', 'harness\profiles\web\node_modules\dsh-onebot-qq\lib'), @('dsh-meme', 'harness\profiles\web\node_modules\dsh-meme'))) {
  $srcDir = Join-Path $nmSrc $pair[0]
  $dstDir = Join-Path $stage $pair[1]
  if (-not (Test-Path $srcDir)) { Write-Output ('skip missing: ' + $srcDir); continue }
  New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
  $cnt = 0
  $items = Get-ChildItem $srcDir -Recurse -File -Force -ErrorAction SilentlyContinue
  foreach ($it in $items) {
    if ($skipExt -contains $it.Extension.ToLower()) { continue }
    $rel = $it.FullName.Substring($srcDir.Length).TrimStart('\')
    $tgt = Join-Path $dstDir $rel
    $tgtDir = Split-Path $tgt -Parent
    if (-not (Test-Path $tgtDir)) { New-Item -ItemType Directory -Force -Path $tgtDir | Out-Null }
    Copy-Item $it.FullName $tgt -Force -ErrorAction SilentlyContinue
    $cnt = $cnt + 1
  }
  Write-Output ('copied plugin: ' + $pair[0] + ' files=' + $cnt)
}
CopyTree $B 'qq-bridge'

$hfiles = Get-ChildItem $H -File -Force
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'harness') | Out-Null
foreach ($f in $hfiles) { Copy-Item $f.FullName (Join-Path $stage ('harness\' + $f.Name)) -Force -ErrorAction SilentlyContinue }
Write-Output ('copied: harness root files = ' + $hfiles.Count)

$xl = Get-ChildItem 'C:\Users\USER\Desktop' -Filter '*.xlsx' -File
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'desktop') | Out-Null
foreach ($f in $xl) { Copy-Item $f.FullName (Join-Path $stage ('desktop\' + $f.Name)) -Force -ErrorAction SilentlyContinue }

Write-Output '--- zipping ---'
if (Test-Path $out) { Remove-Item $out -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $out, [System.IO.Compression.CompressionLevel]::Optimal, $false)
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
$info = Get-Item $out
Write-Output ('OUTPUT ' + $info.FullName)
Write-Output ('SIZE ' + [math]::Round($info.Length/1MB,1) + ' MB')