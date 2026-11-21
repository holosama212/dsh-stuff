#requires -Version 5.1
# Weekly FULL mirror of everything "me" onto the USB stick (2026-11-02, owner asked for it).
# Unlike dsh-self-backup.ps1 (daily zip, small, no images), this copies the real trees:
#   harness (with media), workspace, dsh-plugins, Desktop (no *.zip), .bsk, .local\bin
# Layout on the stick: <root>\LittleCodeSauce-Backup\weekly\<yyyy-MM-dd>\
# Keeps the newest N date folders. Skips quietly if the stick is not plugged in.

$ErrorActionPreference = 'Stop'

$H = 'C:\Users\USER\AppData\Roaming\dsh-desktop\harness'
$W = 'C:\Users\USER\Documents\deepseek-harness\default-workspace'
$P = 'C:\Users\USER\dsh-plugins'
$D = 'C:\Users\USER\Desktop'
$B = Join-Path $env:USERPROFILE '.bsk'
$L = Join-Path $env:USERPROFILE '.local\bin'

$FolderName = 'LittleCodeSauce-Backup'
$SubDir     = 'weekly'
$Keep       = 8
$MinFreeMB  = 2048
$LogFile    = Join-Path $P 'full-backup.log'

function Say([string]$m) {
  $line = ('[' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '] ' + $m)
  Write-Output $line
  Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Find-UsbRoot {
  $rem = @(Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 2 -and $_.Size -gt 10GB })
  if ($rem.Count -eq 0) { return $null }
  foreach ($d in $rem) {
    if (Test-Path (Join-Path ($d.DeviceID + '\') $FolderName)) { return ($d.DeviceID + '\') }
  }
  $best = $rem | Sort-Object Size -Descending | Select-Object -First 1
  return ($best.DeviceID + '\')
}

$rc = @('/E','/MT:8','/R:2','/W:2','/XJ','/NFL','/NDL','/NJH','/NJS','/NP')

function Mirror([string]$src, [string]$dst, [string[]]$xd, [string[]]$xf) {
  if (-not (Test-Path -LiteralPath $src)) { Say ('skip missing: ' + $src); return }
  New-Item -ItemType Directory -Force -Path $dst | Out-Null
  $a = @($src, $dst) + $rc
  if ($xd -and $xd.Count -gt 0) { $a += '/XD'; $a += $xd }
  if ($xf -and $xf.Count -gt 0) { $a += '/XF'; $a += $xf }
  # no /LOG here on purpose: Say() keeps this log open, robocopy would trip on the lock.
  $out = & robocopy @a 2>&1
  $code = $LASTEXITCODE
  if ($code -ge 16) {
    foreach ($l in @($out | Select-Object -Last 15)) { Say ('  rc| ' + [string]$l) }
    throw ('robocopy fatal ' + $code + ' for ' + $src)
  }
  if ($code -ge 8) {
    # 8 = a few files could not be copied (live session logs, long FAT32 names). Not fatal:
    # log the offending lines and let the next weekly run pick the stragglers up.
    $bad = @($out | Where-Object { [string]$_ -match '^ERROR ' -or [string]$_ -match 'Access is denied' })
    Say ('WARN robocopy ' + $code + ' (partial) for ' + $src + ' ; bad=' + $bad.Count)
    foreach ($l in @($bad | Select-Object -First 8)) { Say ('  ' + [string]$l) }
  }
}

try {
  Say '=== weekly full backup start ==='
  $root = Find-UsbRoot
  if (-not $root) { Say 'usb: no removable disk found, skipped'; exit 0 }

  $base = Join-Path $root $FolderName
  $week = Join-Path $base $SubDir
  if (-not (Test-Path $week)) { New-Item -ItemType Directory -Force -Path $week | Out-Null }

  $disk = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $root.TrimEnd('\') }
  $freeMB = [math]::Round($disk.FreeSpace / 1MB, 0)
  if ($freeMB -lt $MinFreeMB) { Say ('usb: only ' + $freeMB + 'MB free, skipped'); exit 0 }

  $stamp = (Get-Date).ToString('yyyy-MM-dd')
  $dst = Join-Path $week $stamp
  Write-Output ('target: ' + $dst)

  Mirror $H (Join-Path $dst 'harness') @('cache') @('*.tmp')
  Mirror $W (Join-Path $dst 'workspace') @() @()
  Mirror $P (Join-Path $dst 'dsh-plugins') @('_pylibs','_bak') @()
  Mirror $D (Join-Path $dst 'Desktop') @() @('*.zip')
  Mirror $B (Join-Path $dst 'dot-bsk') @() @()
  Mirror $L (Join-Path $dst 'dot-local-bin') @() @()

  Say ('done: ' + $dst)

  # prune: keep newest N date folders
  $dirs = @(Get-ChildItem $week -Directory | Sort-Object Name -Descending)
  foreach ($d in @($dirs | Select-Object -Skip $Keep)) {
    Say ('prune: ' + $d.Name)
    cmd /c rmdir /s /q "$($d.FullName)"
  }
  Say '=== weekly full backup end ==='
}
catch {
  Say ('FAILED: ' + $_.Exception.Message)
  exit 1
}
