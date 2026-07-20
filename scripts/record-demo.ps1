# Records a short fleet-workflow demo GIF: launches paramux, stages a
# 3-pane agent scene over IPC, captures PrintWindow frames, and
# assembles docs/media/demo.gif via Python/PIL.
#
#   powershell -File scripts/record-demo.ps1
#
# Headless-safe: PrintWindow captures without a visible desktop (the
# disconnected-RDP recipe). Best colors on real hardware GL.
param(
    [string]$Binary = "zig-out/bin/paramux.exe",
    [string]$Com = "zig-out/bin/paramux.com",
    [string]$OutGif = "docs/media/demo.gif",
    [int]$Frames = 14,
    [int]$FrameMs = 700
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Binary)) { Write-Error "Build first: zig build -Demit-exe=true" }

Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class DemoShot {
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    struct RECT { public int L, T, R, B; }
    public static void Save(IntPtr hwnd, string path) {
        RECT r; GetWindowRect(hwnd, out r);
        int w = Math.Max(1, r.R - r.L), h = Math.Max(1, r.B - r.T);
        using (var bmp = new Bitmap(w, h)) {
            using (var g = Graphics.FromImage(bmp)) {
                IntPtr dc = g.GetHdc();
                PrintWindow(hwnd, dc, 2);
                g.ReleaseHdc(dc);
            }
            bmp.Save(path, ImageFormat.Png);
        }
    }
}
"@ -ReferencedAssemblies System.Drawing

$frameDir = Join-Path $env:TEMP "paramux-demo-frames"
if (Test-Path $frameDir) { Remove-Item -Recurse -Force $frameDir }
New-Item -ItemType Directory -Force $frameDir | Out-Null

$proc = Start-Process -FilePath $Binary -PassThru
Start-Sleep -Seconds 4
try {
    $hwnd = $proc.MainWindowHandle
    if ($hwnd -eq [IntPtr]::Zero) { $proc.Refresh(); $hwnd = $proc.MainWindowHandle }
    if ($hwnd -eq [IntPtr]::Zero) { throw "paramux window not found" }

    # Stage the scene between captures: three agent panes, states, a find.
    $script = @(
        { & $Com perform-action new_split:right | Out-Null },
        { & $Com notify --state=working "claude: refactoring auth" | Out-Null },
        { & $Com perform-action new_split:down | Out-Null },
        { & $Com notify --state=waiting "codex: approve migration?" | Out-Null },
        { & $Com send "echo paramux fleet demo" | Out-Null },
        { & $Com notify --state=done "gemini: tests green" | Out-Null },
        { & $Com perform-action attention_inbox | Out-Null; Start-Sleep -Milliseconds 400; & $Com send-key escape | Out-Null }
    )
    $step = 0
    for ($i = 0; $i -lt $Frames; $i++) {
        if ($i % 2 -eq 0 -and $step -lt $script.Count) { & $script[$step]; $step++ }
        Start-Sleep -Milliseconds $FrameMs
        [DemoShot]::Save($hwnd, (Join-Path $frameDir ("f{0:d3}.png" -f $i)))
    }
} finally {
    if (-not $proc.HasExited) { $proc.CloseMainWindow() | Out-Null; Start-Sleep -Seconds 1 }
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
}

$outDir = Split-Path $OutGif -Parent
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }
$py = @'
import glob, sys
from PIL import Image
frames = [Image.open(p).convert("P", palette=Image.ADAPTIVE) for p in sorted(glob.glob(sys.argv[1] + "/f*.png"))]
if not frames:
    raise SystemExit("no frames captured")
frames[0].save(sys.argv[2], save_all=True, append_images=frames[1:], duration=int(sys.argv[3]), loop=0, optimize=True)
print("wrote", sys.argv[2], len(frames), "frames")
'@
$pyPath = Join-Path $env:TEMP "paramux-demo-gif.py"
[System.IO.File]::WriteAllText($pyPath, $py)
python $pyPath $frameDir $OutGif $FrameMs
