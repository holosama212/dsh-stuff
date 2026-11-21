param(
  [ValidateSet('status','on','off','toggle','all','all-off')]
  [string]$Mode = 'status',
  [int]$Percent = -1,
  [switch]$Quiet
)

# mute-mode.ps1 -- system wide mute switch for this PC.
#
# Why not the modern WASAPI path: on this machine the MMDeviceEnumerator COM
# class ({BCDE0395-E52F-467C-8E3D-C4579291807E}) is NOT registered
# (REGDB_E_CLASSNOTREG), so IAudioEndpointVolume / ISimpleAudioVolume cannot be
# created at all. The classic winmm waveform mixer still works and drives the
# same master volume of every output endpoint, so this script uses it.
#
#   status    list every waveform output device with its volume
#   on        mute all output devices (original volumes saved to mute-state.json)
#   off       restore exactly the saved volumes (35% if no save file)
#   toggle    mute if audible, restore if muted
#   all       alias of on
#   all-off   alias of off
#   -Percent N (0..100)  set a volume instead of muting; -Percent 0 = mute
#   -Quiet    no per-device listing
#
# Original per-device volumes are remembered in a JSON file, so unmuting gives
# back the levels you had before, not a guessed value.
# This never touches the hardware mute flag of the tray icon; it only moves the
# waveform master volume, which is what silences QQ, video, TTS, everything.

$StateFile = 'C:\Users\USER\dsh-plugins\mute-state.json'

$src = @'
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct PsWaveOutCaps
{
    public ushort wMid;
    public ushort wPid;
    public uint vDriverVersion;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string szPname;
    public uint dwFormats;
    public ushort wChannels;
    public ushort wReserved1;
    public uint dwSupport;
}

public static class PsWave
{
    [DllImport("winmm.dll")]
    public static extern uint waveOutGetNumDevs();

    [DllImport("winmm.dll")]
    public static extern uint waveOutGetVolume(uint devId, out uint volume);

    [DllImport("winmm.dll")]
    public static extern uint waveOutSetVolume(uint devId, uint volume);

    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    public static extern uint waveOutGetDevCaps(uint devId, ref PsWaveOutCaps caps, uint capsSize);

    public const uint AllDevices = 0xFFFFFFFF;

    public static uint MakeWord(uint vol)
    {
        if (vol > 0xFFFF) vol = 0xFFFF;
        return vol | (vol << 16);
    }

    public static int PercentOf(uint vol)
    {
        uint lo = vol & 0xFFFF;
        uint hi = (vol >> 16) & 0xFFFF;
        double avg = ((double)lo + (double)hi) / 2.0;
        return (int)Math.Round(avg / 65535.0 * 100.0);
    }

    public static uint VolumeFromPercent(int percent)
    {
        if (percent < 0) percent = 0;
        if (percent > 100) percent = 100;
        return (uint)Math.Round((double)percent / 100.0 * 65535.0);
    }

    public static string DeviceName(uint id)
    {
        try
        {
            PsWaveOutCaps caps = new PsWaveOutCaps();
            uint size = (uint)Marshal.SizeOf(typeof(PsWaveOutCaps));
            if (waveOutGetDevCaps(id, ref caps, size) == 0 && caps.szPname != null && caps.szPname.Length > 0)
                return caps.szPname.TrimEnd('\0');
        }
        catch { }
        return "device " + id;
    }
}
'@

Add-Type -TypeDefinition $src -ErrorAction Stop

function Get-Devs {
  $n = [PsWave]::waveOutGetNumDevs()
  $list = @()
  for ($i = 0; $i -lt $n; $i++) {
    $v = [uint32]0
    $hr = [PsWave]::waveOutGetVolume($i, [ref]$v)
    if ($hr -ne 0) { $v = 'unavailable' }
    $o = [pscustomobject]@{
      id      = $i
      name    = [PsWave]::DeviceName($i)
      volume  = $(if ($v -is [uint32]) { [int64]$v } else { -1 })
      percent = $(if ($v -is [uint32]) { [PsWave]::PercentOf($v) } else { -1 })
    }
    $list += $o
  }
  return $list
}

function Save-State($devs) {
  $payload = [pscustomobject]@{
    savedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    devices = @($devs | ForEach-Object { [pscustomobject]@{ id = $_.id; name = $_.name; volume = $_.volume } })
  }
  $json = $payload | ConvertTo-Json -Depth 4
  [IO.File]::WriteAllText($StateFile, $json, (New-Object Text.UTF8Encoding($false)))
}

function Get-SavedVolume([int]$id, $saved) {
  if ($null -eq $saved) { return -1 }
  foreach ($d in $saved.devices) {
    if ([int]$d.id -eq $id) { return [int64]$d.volume }
  }
  return -1
}

function Report($devs, [string]$head) {
  if ($Quiet) { Write-Output $head; return }
  Write-Output $head
  foreach ($d in $devs) {
    $tag = 'audible'
    if ($d.percent -le 0) { $tag = 'SILENT' }
    Write-Output ('  #' + $d.id + ' ' + $d.name + '  volume=' + $d.percent + '%  ' + $tag)
  }
}

$devs = Get-Devs
if ($devs.Count -eq 0) {
  Write-Output 'no waveform output device found (audio stack looks dead)'
  exit 1
}

$saved = $null
if (Test-Path -LiteralPath $StateFile) {
  try { $saved = (Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8) | ConvertFrom-Json } catch { $saved = $null }
}

$allSilent = $true
foreach ($d in $devs) { if ($d.percent -gt 0) { $allSilent = $false } }
$savedState = 'none'
if ($null -ne $saved) { $savedState = $saved.savedAt }

switch ($Mode) {
  'status' {
    Report $devs ('status: ' + $(if ($allSilent) { 'MUTED' } else { 'audible' }) + '   saved-original-volumes=' + $savedState)
  }
  { $_ -in 'on','all' } {
    if ($Percent -ge 0) {
      [void][PsWave]::waveOutSetVolume([PsWave]::AllDevices, [PsWave]::MakeWord([PsWave]::VolumeFromPercent($Percent)))
      if ($Percent -gt 0 -and (Test-Path -LiteralPath $StateFile)) { Remove-Item -LiteralPath $StateFile -Force }
    } else {
      Save-State $devs
      [void][PsWave]::waveOutSetVolume([PsWave]::AllDevices, 0)
    }
    Report (Get-Devs) 'muted (all output devices):'
  }
  { $_ -in 'off','all-off' } {
    $n = 0
    foreach ($d in (Get-Devs)) {
      $v = Get-SavedVolume $d.id $saved
      if ($v -lt 0) { $v = [int64][PsWave]::MakeWord([PsWave]::VolumeFromPercent(35)) }
      if ($v -lt ([int64][PsWave]::MakeWord([PsWave]::VolumeFromPercent(2)))) { $v = [int64][PsWave]::MakeWord([PsWave]::VolumeFromPercent(35)) }
      [void][PsWave]::waveOutSetVolume($d.id, [uint32]$v)
      $n = $n + 1
    }
    if (Test-Path -LiteralPath $StateFile) { Remove-Item -LiteralPath $StateFile -Force }
    Report (Get-Devs) ('unmuted, restored saved volumes on ' + $n + ' device(s):')
  }
  'toggle' {
    if ($allSilent) {
      foreach ($d in $devs) {
        $v = Get-SavedVolume $d.id $saved
        if ($v -lt ([int64][PsWave]::MakeWord([PsWave]::VolumeFromPercent(2)))) { $v = [int64][PsWave]::MakeWord([PsWave]::VolumeFromPercent(35)) }
        [void][PsWave]::waveOutSetVolume($d.id, [uint32]$v)
      }
      if (Test-Path -LiteralPath $StateFile) { Remove-Item -LiteralPath $StateFile -Force }
      Report (Get-Devs) 'toggle: was muted -> audible again:'
    } else {
      Save-State $devs
      [void][PsWave]::waveOutSetVolume([PsWave]::AllDevices, 0)
      Report (Get-Devs) 'toggle: was audible -> muted (originals saved):'
    }
  }
}
exit 0
