param([Parameter(Mandatory)][int]$ProcessId, [Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class VictoryCaptureWindow {
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
}
'@
$process = Get-Process -Id $ProcessId
if ($process.ProcessName -ne 'victory' -or $process.MainWindowHandle -eq [IntPtr]::Zero) { throw 'No Victory window.' }
$rectangle = New-Object VictoryCaptureWindow+Rect
if (-not [VictoryCaptureWindow]::GetWindowRect($process.MainWindowHandle, [ref]$rectangle)) { throw 'Cannot read window rectangle.' }
$bitmap = New-Object Drawing.Bitmap(($rectangle.Right-$rectangle.Left), ($rectangle.Bottom-$rectangle.Top))
$graphics = [Drawing.Graphics]::FromImage($bitmap)
try {
 $graphics.CopyFromScreen($rectangle.Left,$rectangle.Top,0,0,$bitmap.Size)
 $bitmap.Save($OutputPath, [Drawing.Imaging.ImageFormat]::Png)
} finally { $graphics.Dispose(); $bitmap.Dispose() }
@{timestampUtc=[DateTimeOffset]::UtcNow.ToString('o');processId=$ProcessId;title=$process.MainWindowTitle;method='screen pixels in Victory window rectangle; occlusion possible'} | ConvertTo-Json | Set-Content -LiteralPath ($OutputPath + '.json')
Write-Output $OutputPath
