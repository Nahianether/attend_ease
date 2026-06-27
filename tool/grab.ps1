param([Parameter(Mandatory=$true)][string]$Out)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string n);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
}
"@
[Win]::SetProcessDPIAware() | Out-Null

# Wait for the app window handle (up to ~20s).
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 40; $i++) {
  $proc = Get-Process attend_ease -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($proc) { $h = $proc.MainWindowHandle; break }
  Start-Sleep -Milliseconds 500
}
if ($h -eq [IntPtr]::Zero) { Write-Output 'NOWINDOW'; exit 1 }

[Win]::ShowWindow($h, 9) | Out-Null   # SW_RESTORE
[Win]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 1000

$r = New-Object Win+RECT
[Win]::GetClientRect($h, [ref]$r) | Out-Null
$tl = New-Object Win+POINT
$tl.x = 0; $tl.y = 0
[Win]::ClientToScreen($h, [ref]$tl) | Out-Null

$w = $r.right - $r.left
$ht = $r.bottom - $r.top
if ($w -le 0 -or $ht -le 0) { Write-Output 'BADRECT'; exit 1 }

# Park the cursor off-window so no hover tooltip is captured.
[Win]::SetCursorPos($tl.x + [int]($w / 2), $tl.y + $ht + 60) | Out-Null
Start-Sleep -Milliseconds 700

$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($tl.x, $tl.y, 0, 0, (New-Object System.Drawing.Size($w, $ht)))
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "SAVED $Out ${w}x${ht}"
