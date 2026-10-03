# Read-only fixtures: Start-Process is mocked whenever the entry is exercised.
$ErrorActionPreference = 'Stop'
$workspacePath = Split-Path $PSScriptRoot -Parent
$toolsPath = Join-Path $workspacePath 'tools'
$entryPath = Join-Path $toolsPath 'open_godot_editor.ps1'
. (Join-Path $toolsPath 'godot_editor_session.ps1')
$script:entryAssertions = 0

function Assert-Entry {
    param([bool]$Condition, [string]$Message)
    $script:entryAssertions++
    if (-not $Condition) { throw $Message }
}

function New-EntryFixture {
    param([int]$Identifier, [string]$CommandLine, [string]$Executable = 'C:\Godot\Godot.exe')
    return [pscustomobject]@{ ProcessId = $Identifier; CommandLine = $CommandLine; ExecutablePath = $Executable }
}

$quotedWorkspace = '"' + $workspacePath + '"'
$fakeExe = '"C:\Godot\Godot.exe"'
$fixtures = @(
    (New-EntryFixture 11 ($fakeExe + ' --editor --path ' + $quotedWorkspace)),
    (New-EntryFixture 12 ($fakeExe + ' --path "' + $workspacePath.Replace('\', '/').ToUpperInvariant() + '/" -e')),
    (New-EntryFixture 13 ($fakeExe + ' "' + (Join-Path $workspacePath 'project.godot') + '" --editor')),
    (New-EntryFixture 14 ($fakeExe + ' -e --path="' + $workspacePath + '"')),
    (New-EntryFixture 15 ($fakeExe + ' --editor --path "' + $workspacePath + '-other"')),
    (New-EntryFixture 16 ($fakeExe + ' --editor --path "C:\Other project"')),
    (New-EntryFixture 17 ($fakeExe + ' --path ' + $quotedWorkspace)),
    (New-EntryFixture 18 ($fakeExe + ' --editor-pid 6224 --path ' + $quotedWorkspace)),
    (New-EntryFixture 19 ($fakeExe + ' --path ' + $quotedWorkspace + ' --editor-pid=6224')),
    (New-EntryFixture 20 ($fakeExe + ' --editor --path "."')),
    (New-EntryFixture 21 ($fakeExe + ' --editor --path "C:relative"')),
    (New-EntryFixture 22 ($fakeExe + ' --editor --path ' + $quotedWorkspace) 'C:\Godot\renamed_engine.exe'),
    (New-EntryFixture 23 ('"C:\Other\not_godot.exe" --editor --path ' + $quotedWorkspace) 'C:\Other\not_godot.exe'),
    (New-EntryFixture 24 ($fakeExe + ' --editor --path "C:\Other project" "' + (Join-Path $workspacePath 'project.godot') + '"')),
    (New-EntryFixture 25 ($fakeExe + ' --EDITOR --path ' + $quotedWorkspace)),
    (New-EntryFixture 26 '')
)
$versionLookup = {
    param($ExecutablePath)
    return [pscustomobject]@{ Version = '4.7.2.stable.official'; IsGodot = ($ExecutablePath -notlike '*not_godot.exe') }
}
$sessions = @(Get-NightfallEditorSessions -WorkspacePath $workspacePath -Processes $fixtures -VersionLookup $versionLookup)
Assert-Entry (($sessions.ProcessId -join ',') -eq '11,12,13,14,22') 'Exact editor and absolute-project matching produced an unexpected process.'
Assert-Entry ((Get-NightfallEditorEntryState -Sessions $sessions) -eq 'already_running') 'Supported active editors must be reused.'
Assert-Entry ((Get-NightfallEditorEntryState -Sessions @()) -eq 'ready') 'No editor should permit a new launch.'
Assert-Entry ($sessions[0].WorkspacePath -eq (ConvertTo-NightfallAbsolutePath $workspacePath)) 'Discovery must return the actual canonical workspace.'
Assert-Entry ($sessions[4].ExecutablePath -eq 'C:\Godot\renamed_engine.exe') 'Actual version metadata must recognize renamed Godot binaries.'

$splitArguments = @(ConvertFrom-NightfallCommandLine ('"C:\Program Files\Godot\Godot.exe" --path ' + $quotedWorkspace + ' --editor'))
Assert-Entry ($splitArguments.Count -eq 4 -and $splitArguments[2] -eq $workspacePath) 'Quoted Windows argument splitting must preserve spaces.'
$escapedArguments = @(ConvertFrom-NightfallCommandLine 'engine.exe "C:\Example\\" "has\"quote" ""')
Assert-Entry ($escapedArguments.Count -eq 4 -and $escapedArguments[1] -eq 'C:\Example\' -and $escapedArguments[2] -eq 'has"quote' -and $escapedArguments[3] -eq '') 'Windows escaped quotes, trailing slashes and empty arguments must parse correctly.'
Assert-Entry ((ConvertTo-NightfallAbsolutePath 'C:relative') -eq $null) 'Drive-relative paths are not absolute.'
Assert-Entry ((ConvertTo-NightfallAbsolutePath '\\server\share\game\') -eq '\\server\share\game') 'UNC project paths must remain supported.'

foreach ($badVersion in @('4.6.2.stable.official', '4.8.0.stable.official', '4.7.2.beta1', 'unknown')) {
    $badSession = [pscustomobject]@{ ProcessId = 999; Version = $badVersion; ExecutablePath = 'C:\Godot\old.exe' }
    $message = ''
    try { Get-NightfallEditorEntryState -Sessions @($badSession) | Out-Null } catch { $message = $_.Exception.Message }
    Assert-Entry ($message.Contains('PID 999') -and $message.Contains($badVersion) -and $message.Contains('Save your unsaved work') -and $message.Contains('No editor was stopped')) 'Version conflict must explain its process, reason and preserved work.'
}
$mixed = @($sessions[0], [pscustomobject]@{ ProcessId = 777; Version = '4.6.2.stable.official'; ExecutablePath = 'C:\Godot\old.exe' })
$mixedRejected = $false
try { Get-NightfallEditorEntryState -Sessions $mixed | Out-Null } catch { $mixedRejected = $_.Exception.Message.Contains('PID 777') }
Assert-Entry $mixedRejected 'A valid editor must not conceal another incompatible editor.'

# Check production metadata directly, without launching any executable.
$realEngine = Join-Path $env:ProgramFiles 'Godot/Godot_v4.7.2-stable_win64.exe'
if (Test-Path -LiteralPath $realEngine) {
    $firstInfo = Get-NightfallEngineFileVersion $realEngine
    $cacheCount = $script:NightfallEngineVersionCache.Count
    $secondInfo = Get-NightfallEngineFileVersion $realEngine
    Assert-Entry ($firstInfo.IsGodot -and $firstInfo.Version -match '^4\.7\.2\.stable') 'Installed GUI metadata must confirm the required stable version.'
    Assert-Entry ($script:NightfallEngineVersionCache.Count -eq $cacheCount -and [object]::ReferenceEquals($firstInfo, $secondInfo)) 'Version metadata should be cached without rerunning the engine.'
}

function Invoke-EntryFixture {
    param([object[]]$ProcessFixtures, [switch]$CheckOnly, [object[]]$LaterProcessFixtures)
    $entryFixtures = $ProcessFixtures
    $laterFixtures = $LaterProcessFixtures
    $hasLaterFixtures = $PSBoundParameters.ContainsKey('LaterProcessFixtures')
    $probe = @{ Starts = 0; Queries = 0 }
    function Get-CimInstance {
        param([string]$ClassName, [string]$ErrorAction)
        if ($ClassName -ne 'Win32_Process') { throw 'Unexpected CIM query in fixture.' }
        $probe.Queries++
        if ($hasLaterFixtures -and $probe.Queries -gt 1) { return $laterFixtures }
        return $entryFixtures
    }
    function Start-Process {
        param($FilePath, $WorkingDirectory, $WindowStyle, $ArgumentList)
        $probe.Starts++
        Assert-Entry ($WindowStyle -eq 'Normal' -and $ArgumentList[0] -eq '--editor') 'Explicit editor entry must retain its intended launch arguments.'
    }
    $output = @(); $errorMessage = ''
    try { $output = @(& $entryPath -CheckOnly:$CheckOnly) } catch { $errorMessage = $_.Exception.Message }
    return [pscustomobject]@{ Output = ($output -join "`n"); Error = $errorMessage; Starts = $probe.Starts }
}

$checkReady = Invoke-EntryFixture -ProcessFixtures @() -CheckOnly
Assert-Entry ($checkReady.Starts -eq 0 -and $checkReady.Error -eq '' -and $checkReady.Output.StartsWith('EDITOR_ENGINE_OK')) 'CheckOnly with no editor must only inspect.'
$mockRunning = New-EntryFixture 555 ('"' + $realEngine + '" --editor --path ' + $quotedWorkspace) $realEngine
$checkRunning = Invoke-EntryFixture -ProcessFixtures @($mockRunning) -CheckOnly
Assert-Entry ($checkRunning.Starts -eq 0 -and $checkRunning.Error -eq '' -and $checkRunning.Output.StartsWith('EDITOR_ALREADY_RUNNING 555')) 'CheckOnly must detect an existing supported editor without starting another.'
$reuseRunning = Invoke-EntryFixture -ProcessFixtures @($mockRunning)
Assert-Entry ($reuseRunning.Starts -eq 0 -and $reuseRunning.Output.StartsWith('EDITOR_ALREADY_RUNNING 555')) 'Normal entry must reuse a supported editor without a second window.'
$oldEngine = Join-Path $env:ProgramFiles 'Godot/Godot_v4.6.2-stable_win64.exe'
if (Test-Path -LiteralPath $oldEngine) {
    $mockOld = New-EntryFixture 556 ('"' + $oldEngine + '" --editor --path ' + $quotedWorkspace) $oldEngine
    foreach ($inspectOnly in @($true, $false)) {
        $blocked = Invoke-EntryFixture -ProcessFixtures @($mockOld) -CheckOnly:$inspectOnly
        Assert-Entry ($blocked.Starts -eq 0 -and $blocked.Error.Contains('PID 556') -and $blocked.Error.Contains('Save your unsaved work')) 'Both entry modes must block an incompatible editor without operating its window.'
    }
    $lateOld = Invoke-EntryFixture -ProcessFixtures @() -LaterProcessFixtures @($mockOld)
    Assert-Entry ($lateOld.Starts -eq 0 -and $lateOld.Error.Contains('PID 556')) 'A conflicting editor appearing during resolution must block the launch.'
}
$lateSupported = Invoke-EntryFixture -ProcessFixtures @() -LaterProcessFixtures @($mockRunning)
Assert-Entry ($lateSupported.Starts -eq 0 -and $lateSupported.Output.StartsWith('EDITOR_ALREADY_RUNNING 555')) 'A supported editor appearing during resolution must also be reused.'
$mockStart = Invoke-EntryFixture -ProcessFixtures @()
Assert-Entry ($mockStart.Starts -eq 1 -and $mockStart.Error -eq '') 'A conflict-free normal entry must issue exactly one mocked launch.'

# Read actual process metadata once. No process is started, stopped or activated.
$actualSessions = @(Get-NightfallEditorSessions -WorkspacePath $workspacePath)
foreach ($actualSession in $actualSessions) {
    Assert-Entry ($actualSession.ProcessId -gt 0 -and $actualSession.ExecutablePath -ne '' -and $actualSession.WorkspacePath -eq (ConvertTo-NightfallAbsolutePath $workspacePath)) 'Actual discovered sessions must carry usable handoff fields.'
    Write-Output ('READ_ONLY_EDITOR_SESSION ' + $actualSession.ProcessId + ' ' + $actualSession.Version)
}
Write-Output ('GODOT_EDITOR_ENTRY_OK ' + $script:entryAssertions)
