param(
    [Parameter(Mandatory=$true)][string]$Version,
    [string[]]$Tests = @('nightfall_loop'),
    [string]$GodotExecutable = $env:GODOT_EXECUTABLE,
    [string]$OutputFile,
    [string]$ProjectPath
)
$ErrorActionPreference = 'Stop'

function Get-PhysicalPath {
    param([string]$Path, [switch]$RequireFile, [switch]$RequireDirectory)
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Expected a filesystem path' }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $currentPath = $fullPath
    while ($currentPath) {
        if (Test-Path -LiteralPath $currentPath -ErrorAction Stop) {
            $item = Get-Item -LiteralPath $currentPath -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Symbolic links and junctions are not allowed: $currentPath"
            }
        }
        $parentPath = [System.IO.Path]::GetDirectoryName($currentPath)
        if ($parentPath -eq $currentPath) { throw 'Cannot establish a physical path' }
        $currentPath = $parentPath
    }
    if ($RequireFile -and -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Required file not found: $fullPath"
    }
    if ($RequireDirectory -and -not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        throw "Required directory not found: $fullPath"
    }
    return $fullPath
}

function Assert-BuildFile {
    param([string]$Path, [switch]$RequireFile)
    $physicalPath = Get-PhysicalPath -Path $Path -RequireFile:$RequireFile
    if (-not [string]::Equals([System.IO.Path]::GetDirectoryName($physicalPath), $buildPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Build outputs and logs must remain directly in the physical workspace build directory'
    }
    if (Test-Path -LiteralPath $physicalPath -PathType Container) { throw 'Expected a build file, not a directory' }
    return $physicalPath
}

function Assert-CleanLog {
    param([string]$Path, [int]$ExitCode, [string]$Stage)
    $physicalLog = Assert-BuildFile -Path $Path -RequireFile
    if ($ExitCode -ne 0 -or (Select-String -LiteralPath $physicalLog -Pattern 'SCRIPT ERROR|ERROR:|WARNING:|(?i)\bleaked\b|\bstill in use\b')) {
        Get-Content -LiteralPath $physicalLog -Tail 25
        throw "$Stage failed or emitted engine diagnostics (exit $ExitCode)"
    }
}

if ($Version -cnotmatch '\A[0-9]+\.[0-9]+\.[0-9]+\z') { throw 'Expected a numeric game version' }
if (-not $Tests -or $Tests.Count -eq 0) { throw 'At least one packaged test is required' }
$seenTests = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($testName in $Tests) {
    if ($testName -cnotmatch '\A[a-z0-9_]+\z' -or -not $seenTests.Add($testName)) {
        throw 'Unexpected or duplicate test filename'
    }
}
$workspacePath = Get-PhysicalPath -Path (Split-Path $PSScriptRoot -Parent) -RequireDirectory
$toolsPath = Get-PhysicalPath -Path $PSScriptRoot -RequireDirectory
$buildPath = Get-PhysicalPath -Path (Join-Path $workspacePath 'build')
if (-not (Test-Path -LiteralPath $buildPath)) { New-Item -ItemType Directory -Path $buildPath | Out-Null }
$buildPath = Get-PhysicalPath -Path $buildPath -RequireDirectory
if (-not $ProjectPath) { $ProjectPath = $workspacePath }
$ProjectPath = Get-PhysicalPath -Path $ProjectPath -RequireDirectory
$null = Get-PhysicalPath -Path (Join-Path $ProjectPath 'project.godot') -RequireFile
$resolvePath = Get-PhysicalPath -Path (Join-Path $toolsPath 'resolve_godot.ps1') -RequireFile
$preparePath = Get-PhysicalPath -Path (Join-Path $toolsPath 'prepare_packaged_tests.gd') -RequireFile
$bootstrapPath = Get-PhysicalPath -Path (Join-Path $toolsPath 'run_packaged_test.gd') -RequireFile
$shutdownPath = Get-PhysicalPath -Path (Join-Path $toolsPath 'verify_windows_shutdown.ps1') -RequireFile
$godotExecutable = & $resolvePath -Executable $GodotExecutable
$godotExecutable = Get-PhysicalPath -Path $godotExecutable -RequireFile
$releaseFile = if ($OutputFile) {
    if ([System.IO.Path]::IsPathRooted($OutputFile)) { $OutputFile }
    else { Join-Path $workspacePath $OutputFile }
} else { Join-Path $buildPath "Riftward_Nightfall_v$Version.exe" }
$releaseFile = Assert-BuildFile -Path $releaseFile
$releaseName = [System.IO.Path]::GetFileName($releaseFile)
$buildLabel = [System.IO.Path]::GetFileNameWithoutExtension($releaseFile)
if ([System.IO.Path]::GetExtension($releaseFile) -ine '.exe' -or [string]::IsNullOrWhiteSpace($buildLabel) -or
    $releaseName.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $releaseName.TrimEnd([char[]]@(' ', '.')) -ne $releaseName) {
    throw 'Expected a valid executable filename in the build directory'
}
$exportLog = Assert-BuildFile -Path (Join-Path $buildPath "export-$buildLabel.log")
$bundlePath = Assert-BuildFile -Path (Join-Path $buildPath "packaged-tests-Riftward_Nightfall_v$Version.pck")
$manifestPath = Assert-BuildFile -Path "$bundlePath.manifest.json"
$prepareLog = Assert-BuildFile -Path (Join-Path $buildPath "prepare-packaged-tests-$buildLabel.log")
$startupLog = Assert-BuildFile -Path (Join-Path $buildPath "startup-$buildLabel.out.log")
$startupErrorLog = Assert-BuildFile -Path (Join-Path $buildPath "startup-$buildLabel.err.log")

Push-Location -LiteralPath $workspacePath
try {
    & $godotExecutable --headless --audio-driver Dummy --path $ProjectPath --export-release 'Windows Desktop' $releaseFile *> $exportLog
    $exportExit = $LASTEXITCODE
    Assert-CleanLog -Path $exportLog -ExitCode $exportExit -Stage 'Windows export'
    $releaseFile = Assert-BuildFile -Path $releaseFile -RequireFile
    if ((Get-Item -LiteralPath $releaseFile).VersionInfo.FileVersion -ne "$Version.0") {
        throw 'Exported executable version does not match the requested version'
    }
    $releaseHash = (Get-FileHash -LiteralPath $releaseFile -Algorithm SHA256).Hash

    $bundlePath = Assert-BuildFile -Path $bundlePath
    $manifestPath = Assert-BuildFile -Path $manifestPath
    $prepareLog = Assert-BuildFile -Path $prepareLog
    & $godotExecutable --headless --audio-driver Dummy --path $workspacePath --script $preparePath -- --workspace $workspacePath --bundle $bundlePath --tests ($Tests -join ',') *> $prepareLog
    $prepareExit = $LASTEXITCODE
    Assert-CleanLog -Path $prepareLog -ExitCode $prepareExit -Stage 'Packaged-test preparation'
    $bundlePath = Assert-BuildFile -Path $bundlePath -RequireFile
    $manifestPath = Assert-BuildFile -Path $manifestPath -RequireFile
    $bundleReadyPattern = '\APACKAGED_TEST_BUNDLE_READY ' + [regex]::Escape([System.IO.Path]::GetFileName($bundlePath)) + ' closure=.+\z'
    if (@(Select-String -LiteralPath $prepareLog -CaseSensitive -Pattern $bundleReadyPattern).Count -ne 1) {
        throw 'Packaged-test preparation did not reach its unique readiness marker'
    }

    foreach ($testName in $Tests) {
        $testLog = Assert-BuildFile -Path (Join-Path $buildPath "$testName-packaged-$buildLabel.log")
        $releaseFile = Assert-BuildFile -Path $releaseFile -RequireFile
        $bundlePath = Assert-BuildFile -Path $bundlePath -RequireFile
        $manifestPath = Assert-BuildFile -Path $manifestPath -RequireFile
        $bootstrapPath = Get-PhysicalPath -Path $bootstrapPath -RequireFile
        if ((Get-FileHash -LiteralPath $releaseFile -Algorithm SHA256).Hash -ne $releaseHash) {
            throw 'The game executable changed before packaged acceptance'
        }
        # Every suite starts in a newly created physical empty working directory.
        # Previous acceptance directories are retained, never reused or removed.
        $isolatedPath = Get-PhysicalPath -Path (Join-Path $buildPath ('packaged-tests-run-' + [guid]::NewGuid().ToString('N')))
        if (Test-Path -LiteralPath $isolatedPath) { throw 'The new packaged-test working directory already exists' }
        New-Item -ItemType Directory -Path $isolatedPath | Out-Null
        $isolatedPath = Get-PhysicalPath -Path $isolatedPath -RequireDirectory
        if (@(Get-ChildItem -LiteralPath $isolatedPath -Force).Count -ne 0) { throw 'Packaged-test working directory must be empty' }
        Push-Location -LiteralPath $isolatedPath
        try {
            & $godotExecutable --headless --audio-driver Dummy --main-pack $releaseFile --script $bootstrapPath -- --workspace $workspacePath --bundle $bundlePath --test $testName *> $testLog
            $testExit = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        Get-Content -LiteralPath $testLog -Tail 6
        Assert-CleanLog -Path $testLog -ExitCode $testExit -Stage "Packaged test $testName"
        $readyPattern = '\APACKAGED_TEST_READY name=' + [regex]::Escape($testName) + ' entry=res://tests/' + [regex]::Escape($testName) + '\.gd closure=.+\z'
        if (@(Select-String -LiteralPath $testLog -CaseSensitive -Pattern $readyPattern).Count -ne 1) {
            throw "Packaged test did not reach its unique mounted-entry marker: $testName"
        }
        $successToken = $testName.ToUpperInvariant() + '_OK'
        $successPattern = '\A' + [regex]::Escape($successToken) + '(?:[ \t]+.*)?\z'
        $invalidSuffixPattern = '(?<![A-Za-z0-9_])' + [regex]::Escape($successToken) + '[A-Za-z0-9_]+'
        if (@(Select-String -LiteralPath $testLog -CaseSensitive -Pattern $successPattern).Count -ne 1 -or
            (Select-String -LiteralPath $testLog -CaseSensitive -Pattern $invalidSuffixPattern,'_OK_FALSE')) {
            throw "Packaged test did not reach exactly one own success marker: $testName"
        }
    }
    $releaseFile = Assert-BuildFile -Path $releaseFile -RequireFile
    if ((Get-FileHash -LiteralPath $releaseFile -Algorithm SHA256).Hash -ne $releaseHash) {
        throw 'The game executable changed during packaged acceptance'
    }
    $null = Assert-BuildFile -Path $startupLog
    $null = Assert-BuildFile -Path $startupErrorLog
    & $shutdownPath -Version $Version -ExecutablePath $releaseFile
    Assert-CleanLog -Path $startupLog -ExitCode 0 -Stage 'Windows startup and shutdown'
    Assert-CleanLog -Path $startupErrorLog -ExitCode 0 -Stage 'Windows startup and shutdown'
    if ((Get-FileHash -LiteralPath $releaseFile -Algorithm SHA256).Hash -ne $releaseHash) {
        throw 'The game executable changed during native startup acceptance'
    }
    Write-Output "VERIFIED_WINDOWS_BUILD $Version $releaseFile"
} finally {
    Pop-Location
}
