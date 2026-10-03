param(
    [string]$Executable = $env:GODOT_EXECUTABLE,
    [switch]$Editor
)
$ErrorActionPreference = 'Stop'
$requiredVersion = '4.7.2'
$workspacePath = Split-Path $PSScriptRoot -Parent
$consoleName = "Godot_v$requiredVersion-stable_win64_console.exe"
$candidates = @()
if ($Executable) {
    $candidates = @($Executable)
} else {
    $candidates += Join-Path $env:ProgramFiles "Godot/$consoleName"
    $candidates += Join-Path $env:LOCALAPPDATA "Godot/$consoleName"
    $candidates += Join-Path $workspacePath ".tools/godot/$consoleName"
    foreach ($commandName in @($consoleName, 'godot_console', 'godot')) {
        $command = Get-Command $commandName -CommandType Application -ErrorAction SilentlyContinue
        if ($command) { $candidates += $command.Source }
    }
}
foreach ($candidate in $candidates | Select-Object -Unique) {
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
    $engineVersion = (& $candidate --version | Out-String).Trim()
    if (-not $engineVersion -or
        $engineVersion.Trim() -notlike "$requiredVersion.stable.*") { continue }
    $resolvedPath = (Resolve-Path -LiteralPath $candidate).Path
    if ($Editor -and $resolvedPath.EndsWith('_console.exe')) {
        $guiPath = $resolvedPath.Substring(0, $resolvedPath.Length - '_console.exe'.Length) + '.exe'
        if (Test-Path -LiteralPath $guiPath -PathType Leaf) { $resolvedPath = $guiPath }
    }
    return $resolvedPath
}
throw "Godot $requiredVersion stable was not found. Install it from https://godotengine.org/download/windows/ or set GODOT_EXECUTABLE to its console executable."
