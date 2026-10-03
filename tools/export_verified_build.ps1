param(
    [Parameter(Mandatory=$true)][string]$Version,
    [string[]]$Tests = @('nightfall_loop')
)
$ErrorActionPreference = 'Stop'
$workspacePath = Split-Path $PSScriptRoot -Parent
$godotExecutable = 'C:/Program Files/Godot/Godot_v4.6.2-stable_win64_console.exe'
$releaseFile = Join-Path $workspacePath "build/Riftward_Nightfall_v$Version.exe"
$versionDigits = $Version.Replace('.','')
$exportLog = Join-Path $workspacePath "build/export-v$versionDigits.log"
Push-Location -LiteralPath $workspacePath
try {
    & $godotExecutable --headless --audio-driver Dummy --path . --export-release 'Windows Desktop' $releaseFile *> $exportLog
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
        $testLog = Join-Path $workspacePath "build/$testName-packaged-v$versionDigits.log"
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
    & (Join-Path $PSScriptRoot 'verify_windows_shutdown.ps1') -Version $Version
    Write-Output "VERIFIED_WINDOWS_RELEASE $Version"
} finally {
    Pop-Location
}
