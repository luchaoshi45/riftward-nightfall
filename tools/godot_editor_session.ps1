# Read-only editor discovery. Dot-sourcing this file only defines functions.
$script:NightfallEngineVersionCache = @{}

function ConvertFrom-NightfallCommandLine {
    param([AllowEmptyString()][string]$CommandLine)
    $arguments = New-Object 'System.Collections.Generic.List[string]'
    $cursor = 0
    while ($cursor -lt $CommandLine.Length) {
        while ($cursor -lt $CommandLine.Length -and [char]::IsWhiteSpace($CommandLine[$cursor])) { $cursor++ }
        if ($cursor -ge $CommandLine.Length) { break }
        $argument = New-Object System.Text.StringBuilder
        $quoted = $false
        while ($cursor -lt $CommandLine.Length) {
            $character = $CommandLine[$cursor]
            if (-not $quoted -and [char]::IsWhiteSpace($character)) { break }
            if ($character -eq '\') {
                $slashes = 0
                while ($cursor -lt $CommandLine.Length -and $CommandLine[$cursor] -eq '\') { $slashes++; $cursor++ }
                if ($cursor -lt $CommandLine.Length -and $CommandLine[$cursor] -eq '"') {
                    [void]$argument.Append(('\' * [int][Math]::Floor($slashes / 2)))
                    if (($slashes % 2) -eq 1) {
                        [void]$argument.Append('"'); $cursor++
                    } else {
                        $quoted = -not $quoted; $cursor++
                    }
                } else {
                    [void]$argument.Append(('\' * $slashes))
                }
                continue
            }
            if ($character -eq '"') {
                if ($quoted -and $cursor + 1 -lt $CommandLine.Length -and $CommandLine[$cursor + 1] -eq '"') {
                    [void]$argument.Append('"'); $cursor += 2
                } else {
                    $quoted = -not $quoted; $cursor++
                }
                continue
            }
            [void]$argument.Append($character); $cursor++
        }
        $arguments.Add($argument.ToString())
    }
    return $arguments.ToArray()
}

function ConvertTo-NightfallAbsolutePath {
    param([AllowEmptyString()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    # Relative paths cannot be resolved from Win32_Process without its cwd.
    # A drive-relative path such as C:project is deliberately not absolute.
    if ($Path -notmatch '^(?:[A-Za-z]:[\\/]|[\\/]{2}[^\\/]+[\\/][^\\/]+)') { return $null }
    try {
        return [System.IO.Path]::GetFullPath($Path.Replace('/', '\')).TrimEnd('\')
    } catch { return $null }
}

function Get-NightfallCommandProject {
    param([string[]]$Arguments)
    $editor = $false
    $explicitPath = $null
    $hasExplicitPath = $false
    $projectFile = $null
    for ($index = 1; $index -lt $Arguments.Count; $index++) {
        $argument = $Arguments[$index]
        if ($argument -ceq '--editor' -or $argument -ceq '-e') { $editor = $true; continue }
        if ($argument -ceq '--path') {
            $hasExplicitPath = $true
            if ($index + 1 -lt $Arguments.Count) {
                $index++
                $explicitPath = ConvertTo-NightfallAbsolutePath $Arguments[$index]
            }
            continue
        }
        if ($argument -cmatch '^--path=(.*)$') {
            $hasExplicitPath = $true
            $explicitPath = ConvertTo-NightfallAbsolutePath $Matches[1]
            continue
        }
        $absoluteArgument = ConvertTo-NightfallAbsolutePath $argument
        if ($absoluteArgument -and [System.IO.Path]::GetFileName($absoluteArgument) -ieq 'project.godot') {
            $projectFile = [System.IO.Path]::GetDirectoryName($absoluteArgument)
        }
    }
    if (-not $editor) { return $null }
    if ($hasExplicitPath) { return $explicitPath }
    return $projectFile
}

function Get-NightfallEngineFileVersion {
    param([AllowEmptyString()][string]$ExecutablePath)
    $absolutePath = ConvertTo-NightfallAbsolutePath $ExecutablePath
    if (-not $absolutePath -or -not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
        return [pscustomobject]@{ Version = 'unknown'; IsGodot = $false; ExecutablePath = $ExecutablePath }
    }
    try {
        $file = Get-Item -LiteralPath $absolutePath -ErrorAction Stop
        $cacheKey = $absolutePath.ToLowerInvariant() + '|' + $file.Length + '|' + $file.LastWriteTimeUtc.Ticks
        if ($script:NightfallEngineVersionCache.ContainsKey($cacheKey)) { return $script:NightfallEngineVersionCache[$cacheKey] }
        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($absolutePath)
        $version = $versionInfo.ProductVersion
        if ([string]::IsNullOrWhiteSpace($version)) { $version = $versionInfo.FileVersion }
        if ([string]::IsNullOrWhiteSpace($version)) { $version = 'unknown' }
        $result = [pscustomobject]@{
            Version = $version.Trim()
            IsGodot = ($versionInfo.ProductName -like '*Godot*' -or $versionInfo.FileDescription -like '*Godot*')
            ExecutablePath = $absolutePath
        }
        $script:NightfallEngineVersionCache[$cacheKey] = $result
        return $result
    } catch {
        return [pscustomobject]@{ Version = 'unknown'; IsGodot = $false; ExecutablePath = $absolutePath }
    }
}

function Get-NightfallEditorSessions {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspacePath,
        [object[]]$Processes,
        [scriptblock]$VersionLookup
    )
    $workspace = ConvertTo-NightfallAbsolutePath $WorkspacePath
    if (-not $workspace) { throw 'Editor discovery requires an absolute workspace path.' }
    if (-not $PSBoundParameters.ContainsKey('Processes')) {
        # Reading CIM does not activate, stop or communicate with any window.
        $Processes = @(Get-CimInstance -ClassName Win32_Process -ErrorAction Stop)
    }
    foreach ($process in $Processes) {
        if ([string]::IsNullOrWhiteSpace([string]$process.CommandLine)) { continue }
        $arguments = @(ConvertFrom-NightfallCommandLine ([string]$process.CommandLine))
        if ($arguments.Count -eq 0) { continue }
        $project = Get-NightfallCommandProject $arguments
        if (-not $project -or -not [string]::Equals($workspace, $project, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $executable = [string]$process.ExecutablePath
        if ([string]::IsNullOrWhiteSpace($executable)) { $executable = $arguments[0] }
        if ($VersionLookup) { $info = & $VersionLookup $executable }
        else { $info = Get-NightfallEngineFileVersion $executable }
        # Renamed Godot binaries are identified by their actual version resource.
        # An unreadable binary with a Godot name remains a fail-closed conflict.
        $godotNamed = [System.IO.Path]::GetFileName($executable) -imatch '^godot.*\.exe$'
        if (-not $info.IsGodot -and -not $godotNamed) { continue }
        [pscustomobject]@{
            ProcessId = [int]$process.ProcessId
            WorkspacePath = $project
            Version = [string]$info.Version
            ExecutablePath = $executable
        }
    }
}

function Get-NightfallEditorEntryState {
    param([object[]]$Sessions, [string]$RequiredVersion = '4.7.2')
    $versionPattern = '^' + [regex]::Escape($RequiredVersion) + '\.stable(?:\.|$)'
    $conflicts = @($Sessions | Where-Object { $_.Version -notmatch $versionPattern })
    if ($conflicts.Count -gt 0) {
        $details = @($conflicts | ForEach-Object { 'PID ' + $_.ProcessId + ', version ' + $_.Version + ', ' + $_.ExecutablePath }) -join '; '
        throw ('This project is already open in an incompatible editor: ' + $details + '. Save your unsaved work and close that editor yourself before reopening with Godot ' + $RequiredVersion + ' stable. Starting another editor can overwrite project/import settings. No editor was stopped and no files were changed.')
    }
    if (@($Sessions).Count -gt 0) { return 'already_running' }
    return 'ready'
}
