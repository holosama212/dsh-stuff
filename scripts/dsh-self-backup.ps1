#requires -Version 5.1
# DSH self backup: copy "myself" (no images) to Desktop AND to the USB stick, run daily 08:00.
# USB part: auto-detects the removable drive (letter may change), keeps the newest N copies
# and a hard total-size cap. If the stick is unplugged the run still succeeds locally.
$ErrorActionPreference = 'Stop'

$Desktop = 'C:\Users\USER\Desktop'
$H       = 'C:\Users\USER\AppData\Roaming\dsh-desktop\harness'
$W       = 'C:\Users\USER\Documents\deepseek-harness\default-workspace'
$Q       = 'C:\Users\USER\qq-bridge-0.2.1-r1'
$P       = 'C:\Users\USER\dsh-plugins'
$LogFile = Join-Path $P 'self-backup.log'
$Pattern = 'DSH-selfbackup-*.zip'
$Keep    = 2

# --- USB destination -------------------------------------------------------
$UsbFolderName = 'LittleCodeSauce-Backup'
$UsbKeep       = 14          # newest N copies kept on the stick
$UsbCapMB      = 0            # 0 = no size cap (old 3072 was for the old 8GB stick; new stick is 114GB)
$UsbMinFreeMB  = 512         # refuse to copy if the stick has less than this left

$now   = Get-Date
$stamp = $now.ToString('yyyy-MM-dd')
$Dest  = Join-Path $Desktop ("DSH-selfbackup-$stamp.zip")
$Stage = Join-Path $env:TEMP ("dsh-selfbackup-$stamp")

function Say([string]$m) {
  $line = ('[' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '] ' + $m)
  Write-Output $line
  Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Find-UsbRoot {
  # Prefer the stick that already holds our folder; otherwise the biggest removable disk.
  $rem = @(Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 -and $_.Size -gt 10GB })
  if ($rem.Count -eq 0) { return $null }
  foreach ($d in $rem) {
    $p = Join-Path ($d.DeviceID + '\') $UsbFolderName
    if (Test-Path $p) { return ($d.DeviceID + '\') }
  }
  $best = $rem | Sort-Object Size -Descending | Select-Object -First 1
  return ($best.DeviceID + '\')
}

function Sync-ToUsb([string]$zipPath) {
  $root = Find-UsbRoot
  if (-not $root) { Say 'usb: no removable disk found, skipped'; return }
  $base  = Join-Path $root $UsbFolderName
  $daily = Join-Path $base 'daily'
  if (-not (Test-Path $daily)) { New-Item -ItemType Directory -Force -Path $daily | Out-Null }

  $disk = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $root.TrimEnd('\') }
  $freeMB = [math]::Round($disk.FreeSpace / 1MB, 0)
  $needMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 0)
  if ($freeMB -lt ($needMB + $UsbMinFreeMB)) {
    Say ("usb: not enough space (free=" + $freeMB + "MB need=" + $needMB + "MB), skipped")
    return
  }

  $target = Join-Path $daily (Split-Path $zipPath -Leaf)
  Copy-Item $zipPath $target -Force
  Say ("usb: copied -> " + $target + " (" + $needMB + "MB)")

  # prune: keep newest N
  $all = @(Get-ChildItem $daily -File -Filter '*.zip' | Sort-Object LastWriteTime -Descending)
  foreach ($f in @($all | Select-Object -Skip $UsbKeep)) {
    Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
    Say ("usb: pruned (count) " + $f.Name)
  }

  # prune: enforce the total-size cap, oldest first (skipped when UsbCapMB <= 0)
  if ($UsbCapMB -gt 0) {
    $all = @(Get-ChildItem $daily -File -Filter '*.zip' | Sort-Object LastWriteTime -Descending)
    $totalMB = [math]::Round((($all | Measure-Object Length -Sum).Sum / 1MB), 0)
    $idx = 0
    foreach ($f in $all) {
      $idx++
      if ($idx -eq 1) { continue }   # never drop the newest
      if ($totalMB -le $UsbCapMB) { break }
      $totalMB = $totalMB - [math]::Round($f.Length / 1MB, 0)
      Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
      Say ("usb: pruned (size) " + $f.Name)
    }
  }

  $left = @(Get-ChildItem $daily -File -Filter '*.zip')
  $sumMB = [math]::Round((($left | Measure-Object Length -Sum).Sum / 1MB), 0)
  Say ("usb: now " + $left.Count + " copy/copies, " + $sumMB + "MB total (cap " + $UsbCapMB + "MB)")
}

$imgExt = @('*.png','*.jpg','*.jpeg','*.webp','*.gif','*.bmp','*.ico','*.mp4','*.webm','*.mov')
$rcArgs = @('/E','/R:1','/W:1','/NFL','/NDL','/NJH','/NJS','/NP')

function Copy-Tree([string]$src,[string]$dst,[string[]]$xd) {
  if (-not (Test-Path $src)) { return }
  New-Item -ItemType Directory -Force -Path $dst | Out-Null
  $a = @($src, $dst) + $rcArgs
  if ($xd -and $xd.Count -gt 0) { $a = $a + @('/XD') + $xd }
  $a = $a + @('/XF') + $imgExt
  & robocopy @a | Out-Null
  if ($LASTEXITCODE -ge 8) { throw ("robocopy failed ($LASTEXITCODE): " + $src) }
}

try {
  Say '=== self backup start ==='
  if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }

  # 1) harness: config, memories, sessions, plugins, skills, storages, logs
  $keepDirs = @('.agent-presets','desktop-workbenches','dsh-image-gen','dsh-market','dsh-purge',
                'fish-memory','fish-memory-backup','logs','memories','mobile-access','plugins',
                'qqbot','recovery','redteam','self-evolve','sessions','skills','storages','workbuddy-vault')
  foreach ($d in $keepDirs) { Copy-Tree (Join-Path $H $d) (Join-Path $Stage ('harness\' + $d)) @() }
  Get-ChildItem $H -File -Force | Where-Object { $imgExt -notcontains ('*' + $_.Extension) } |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $Stage 'harness') -Force -ErrorAction SilentlyContinue }

  # 2) workspace
  Copy-Tree $W (Join-Path $Stage 'workspace') @('generated-images','stickers','memes')

  # 3) QQ bridge
  Copy-Tree $Q (Join-Path $Stage 'qq-bridge') @('node_modules','dist','.git')

  # 4) dsh-plugins
  Copy-Tree $P (Join-Path $Stage 'dsh-plugins') @()

  $files = (Get-ChildItem $Stage -Recurse -File -Force -ErrorAction SilentlyContinue)
  Say ("staged: " + $files.Count + " files, " + [math]::Round((($files | Measure-Object Length -Sum).Sum / 1MB), 1) + " MB")

  # 5) rotate locally BEFORE zipping, then zip
  function Rotate {
    $all = @(Get-ChildItem $Desktop -File -Filter $Pattern | Sort-Object LastWriteTime -Descending)
    $drop = @($all | Select-Object -Skip $Keep)
    foreach ($f in $drop) {
      if ($f.FullName -notlike ($Desktop + '\DSH-selfbackup-*.zip')) { continue }
      Remove-Item $f.FullName -Force
      Say ("pruned: " + $f.Name)
    }
    return @(Get-ChildItem $Desktop -File -Filter $Pattern | Sort-Object LastWriteTime -Descending)
  }
  Rotate | Out-Null
  if (Test-Path $Dest) { Remove-Item $Dest -Force }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::CreateFromDirectory($Stage, $Dest, [System.IO.Compression.CompressionLevel]::Optimal, $true)
  $zip = Get-Item $Dest
  Say ("zip ok: " + $zip.FullName + " (" + [math]::Round($zip.Length / 1MB, 1) + " MB)")

  # 6) rotate again after creating today's zip
  $left = Rotate
  Say ("kept " + $left.Count + " backup(s): " + (($left | ForEach-Object { $_.Name + ' ' + [math]::Round($_.Length/1MB,1) + 'MB' }) -join ' | '))

  # 7) mirror to the USB stick (never fatal)
  try { Sync-ToUsb $Dest } catch { Say ("usb: FAILED but local backup is fine - " + $_.Exception.Message) }

  Say '=== self backup done ==='
}
catch {
  Say ("FAILED: " + $_.Exception.Message)
  exit 1
}
finally {
  if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue }
}
