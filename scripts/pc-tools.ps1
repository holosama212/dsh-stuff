param(
  [Parameter(Mandatory=$true)][string]$Cmd,
  [string]$Text = '',
  [string]$Out = '',
  [string]$Title = 'Little Code Sauce'
)
# pc-tools.ps1 - local PC capability pack (clipboard / notify / screenshot).
# ASCII only. Run via: powershell.exe -NoProfile -ExecutionPolicy Bypass -File <this> -Cmd <name>

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null

switch ($Cmd.ToLower()) {

  'clip-get' {
    $t = Get-Clipboard -Raw -ErrorAction SilentlyContinue
    if ($null -eq $t) { $t = '' }
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    Write-Output $t
  }

  'clip-set' {
    if ($Text -eq '' -and $Out -ne '') {
      $Text = [IO.File]::ReadAllText($Out, [Text.UTF8Encoding]::new($false))
    }
    Set-Clipboard -Value $Text
    Write-Output ('clip-set ok, chars=' + $Text.Length)
  }

  'notify' {
    $ni = New-Object System.Windows.Forms.NotifyIcon
    $ni.Icon = [System.Drawing.SystemIcons]::Information
    $ni.BalloonTipTitle = $Title
    $ni.BalloonTipText = $Text
    $ni.Visible = $true
    $ni.ShowBalloonTip(6000)
    Start-Sleep -Seconds 7
    $ni.Dispose()
    Write-Output 'notify ok'
  }

  'shot' {
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
    if ($Out -eq '') {
      $dir = 'C:\Users\USER\AppData\Roaming\dsh-desktop\harness\media\onebot'
      $Out = Join-Path $dir ('shot-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.png')
    }
    $bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Output ('shot ok -> ' + $Out + '  ' + $b.Width + 'x' + $b.Height)
  }

  'res' {
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    Write-Output ($b.Width.ToString() + 'x' + $b.Height.ToString() + ' @ ' + $b.Left + ',' + $b.Top)
  }

  'active' {
    $sig = @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  public static string Info() {
    IntPtr h = GetForegroundWindow();
    StringBuilder sb = new StringBuilder(512);
    GetWindowText(h, sb, 512);
    int pid; GetWindowThreadProcessId(h, out pid);
    return sb.ToString() + "|" + pid;
  }
}
'@
    if (-not ('W' -as [type])) { Add-Type -TypeDefinition $sig | Out-Null }
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    Write-Output ([W]::Info())
  }

  default {
    Write-Output 'unknown cmd. use: clip-get | clip-set | notify | shot | res | active'
    exit 2
  }
}
