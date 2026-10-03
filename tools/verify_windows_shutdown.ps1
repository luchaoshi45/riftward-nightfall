param([string]$Version = '0.8.17')
$ErrorActionPreference = 'Stop'
$workspacePath = Split-Path $PSScriptRoot -Parent
$executablePath = Join-Path $workspacePath "build/Riftward_Nightfall_v$Version.exe"
$versionDigits = $Version.Replace('.','')
$outputPath = Join-Path $workspacePath "build/startup-v$versionDigits.out.log"
$errorPath = Join-Path $workspacePath "build/startup-v$versionDigits.err.log"
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NightfallOwnWindow {
    private delegate bool WindowCallback(IntPtr handle, IntPtr state);
    [DllImport("user32.dll")] private static extern bool EnumWindows(WindowCallback callback, IntPtr state);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
    [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr handle, uint message, IntPtr wparam, IntPtr lparam);
    public static IntPtr Find(int processId) {
        IntPtr result = IntPtr.Zero;
        EnumWindows((handle, state) => {
            uint owner;
            GetWindowThreadProcessId(handle, out owner);
            if (owner != processId) return true;
            result = handle;
            return false;
        }, IntPtr.Zero);
        return result;
    }
    public static bool Close(IntPtr handle) {
        return PostMessage(handle, 0x0010, IntPtr.Zero, IntPtr.Zero);
    }
}
'@
$gameProcess = Start-Process -FilePath $executablePath -WorkingDirectory $workspacePath -ArgumentList @('--position','10000,10000','--audio-driver','Dummy') -WindowStyle Hidden -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath -PassThru
try {
    $gameWindow = [IntPtr]::Zero
    for ($attempt = 0; $attempt -lt 150; $attempt++) {
        if ($gameProcess.HasExited) { throw 'Game exited before its startup check' }
        $gameWindow = [NightfallOwnWindow]::Find($gameProcess.Id)
        if ($gameWindow -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 100
    }
    if ($gameWindow -eq [IntPtr]::Zero) { throw 'No window belonging to the test process was found' }
    Start-Sleep -Seconds 4
    if (-not [NightfallOwnWindow]::Close($gameWindow)) { throw 'The own-process close request failed' }
    if (-not $gameProcess.WaitForExit(15000)) { throw 'Game failed to close after the Windows close request' }
    $gameProcess.Refresh()
    Write-Output "Windows startup and close exit: $($gameProcess.ExitCode)"
    Get-Content -LiteralPath $outputPath
    Get-Content -LiteralPath $errorPath
    if ($gameProcess.ExitCode -ne 0) { throw 'The game returned a failure exit code' }
    if (Select-String -LiteralPath $outputPath,$errorPath -Pattern 'SCRIPT ERROR|ERROR:') { throw 'Engine errors appeared in startup or shutdown' }
} finally {
    if (-not $gameProcess.HasExited) { Stop-Process -Id $gameProcess.Id }
}
