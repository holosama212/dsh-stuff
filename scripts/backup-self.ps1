$ErrorActionPreference = 'Stop'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stage = Join-Path $env:TEMP ("lcs-backup-" + $stamp)
$out   = Join-Path 'C:\Users\USER\Desktop' ("LCS-backup-" + $stamp + ".zip")
New-Item -ItemType Directory -Force -Path $stage | Out-Null

function CopyTo($src, $dstRel) {
  if (-not (Test-Path $src)) { Write-Output ("skip (missing): " + $src); return }
  $dst = Join-Path $stage $dstRel
  New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
  Copy-Item $src $dst -Recurse -Force
  Write-Output ("copied: " + $dstRel)
}

# 1) my own code / scripts
CopyTo 'C:\Users\USER\dsh-plugins' 'dsh-plugins'
# 2) meme pack library
CopyTo 'C:\Users\USER\.dsh\meme-packs' 'dsh-home\meme-packs'
foreach ($f in @('dsh-expression.json','dsh-meme-catalog-cache.json','desktop-preferences.json','.credentials.yaml')) {
  CopyTo (Join-Path 'C:\Users\USER\.dsh' $f) (Join-Path 'dsh-home' $f)
}
# 3) harness config (no node_modules, no sessions, no media, no logs)
$hroot = 'C:\Users\USER\AppData\Roaming\dsh-desktop\harness'
$hkeep = @('skills','memories','qqbot','plugins','fish-memory','dsh-image-gen','redteam','self-evolve','.agent-presets','settings.yaml')
foreach ($d in $hkeep) { CopyTo (Join-Path $hroot $d) (Join-Path 'harness' $d) }
Get-ChildItem $hroot -File -Force | Where-Object { $_.Name -match '\.(json|yml|yaml|md)$' } | ForEach-Object {
  CopyTo $_.FullName (Join-Path 'harness' $_.Name)
}
# 4) profile config only (cordis.patch.yml / package.json / lock)
$wroot = Join-Path $hroot 'profiles\web'
$wdst  = Join-Path $stage 'harness\profiles\web'
New-Item -ItemType Directory -Force -Path $wdst | Out-Null
Get-ChildItem $wroot -File -Force | Where-Object { $_.Name -notmatch '\.bak-|\.tmp\.' } | ForEach-Object {
  Copy-Item $_.FullName (Join-Path $wdst $_.Name) -Force
}
Write-Output 'copied: harness/profiles/web (config only)'
# 5) plugin lib dirs (the patched bridge.js etc.) without node_modules full tree
$nm = @(
  'dsh-onebot-qq\lib',
  'dsh-meme'
)
foreach ($n in $nm) {
  $srcPath = Join-Path $wroot ('node_modules\' + $n)
  if (Test-Path $srcPath) {
    $dstPath = Join-Path $stage ('harness\profiles\web\node_modules\' + $n)
    New-Item -ItemType Directory -Force -Path (Split-Path $dstPath -Parent) | Out-Null
    if ((Get-Item $srcPath).PSIsContainer) {
      Copy-Item $srcPath $dstPath -Recurse -Force
    } else {
      Copy-Item $srcPath $dstPath -Force
    }
    Write-Output ('copied: node_modules\' + $n)
  }
}
# 6) qq bridge
CopyTo 'C:\Users\USER\qq-bridge-0.2.1-r1' 'qq-bridge'
# 7) tag book
Get-ChildItem 'C:\Users\USER\Desktop' -Filter '*.xlsx' -File | ForEach-Object {
  CopyTo $_.FullName (Join-Path 'desktop' $_.Name)
}

Write-Output '--- zipping ---'
if (Test-Path $out) { Remove-Item $out -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $out, [System.IO.Compression.CompressionLevel]::Optimal, $false)
Remove-Item $stage -Recurse -Force
$info = Get-Item $out
Write-Output ('OUTPUT ' + $info.FullName)
Write-Output ('SIZE ' + [math]::Round($info.Length/1MB,1) + ' MB')