param(
    [Parameter(Mandatory=$true)][string]$Version,
    [string[]]$Tests = @('nightfall_loop'),
    [string]$GodotExecutable = $env:GODOT_EXECUTABLE,
    [string]$OutputFile,
    [string]$ProjectPath
)
$ErrorActionPreference = 'Stop'
$workspacePath = Split-Path $PSScriptRoot -Parent
if (-not $ProjectPath) { $ProjectPath = $workspacePath }
if (-not (Test-Path -LiteralPath (Join-Path $ProjectPath 'project.godot'))) { throw 'Godot project not found' }
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Expected a numeric game version' }
$godotExecutable = & (Join-Path $PSScriptRoot 'resolve_godot.ps1') -Executable $GodotExecutable
$releaseFile = if ($OutputFile) {
    if ([System.IO.Path]::IsPathRooted($OutputFile)) { $OutputFile }
    else { Join-Path $workspacePath $OutputFile }
} else { Join-Path $workspacePath "build/Riftward_Nightfall_v$Version.exe" }
$buildLabel = [System.IO.Path]::GetFileNameWithoutExtension($releaseFile)
New-Item -ItemType Directory -Force -Path (Split-Path $releaseFile -Parent) | Out-Null
$exportLog = Join-Path $workspacePath "build/export-$buildLabel.log"
Push-Location -LiteralPath $workspacePath
try {
    & $godotExecutable --headless --audio-driver Dummy --path $ProjectPath --export-release 'Windows Desktop' $releaseFile *> $exportLog
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $exportLog -Pattern 'SCRIPT ERROR|ERROR:')) {
        Get-Content -LiteralPath $exportLog -Tail 25
        throw 'Windows export failed'
    }
    if ((Get-Item -LiteralPath $releaseFile).VersionInfo.FileVersion -ne "$Version.0") {
        throw 'Exported executable version does not match the requested version'
    }
    foreach ($testName in $Tests) {
        if ($testName -notmatch '^[a-z0-9_]+$') { throw 'Unexpected test filename' }
        $testPath = Join-Path $workspacePath "tests/$testName.gd"
        $testLog = Join-Path $workspacePath "build/$testName-packaged-$buildLabel.log"
        & $godotExecutable --headless --audio-driver Dummy --main-pack $releaseFile --script $testPath *> $testLog
        $testExit = $LASTEXITCODE
        Get-Content -LiteralPath $testLog -Tail 6
        if ($testExit -ne 0 -or (Select-String -LiteralPath $testLog -Pattern 'SCRIPT ERROR|ERROR:')) {
            throw "Packaged test failed: $testName"
        }
        if (-not (Select-String -LiteralPath $testLog -Pattern '_OK')) {
            throw "Packaged test did not reach its success marker: $testName"
        }
    }
    & (Join-Path $PSScriptRoot 'verify_windows_shutdown.ps1') -Version $Version -ExecutablePath $releaseFile
    Write-Output "VERIFIED_WINDOWS_BUILD $Version $releaseFile"
} finally {
    Pop-Location
}
