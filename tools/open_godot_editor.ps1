param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$workspacePath = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'godot_editor_session.ps1')
$sessions = @(Get-NightfallEditorSessions -WorkspacePath $workspacePath)
$entryState = Get-NightfallEditorEntryState -Sessions $sessions
$enginePath = & (Join-Path $PSScriptRoot 'resolve_godot.ps1') -Editor
$engineInfo = Get-NightfallEngineFileVersion $enginePath
if (-not $engineInfo.IsGodot -or $engineInfo.Version -notmatch '^4\.7\.2\.stable(?:\.|$)') {
    throw "The selected GUI executable is not Godot 4.7.2 stable: $enginePath ($($engineInfo.Version)). No editor was started."
}
if ($entryState -eq 'already_running') {
    Write-Output ('EDITOR_ALREADY_RUNNING ' + (@($sessions.ProcessId) -join ',') + ' ' + $workspacePath)
    return
}
if ($CheckOnly) {
    Write-Output "EDITOR_ENGINE_OK $enginePath"
    return
}
# Discovery is repeated after engine resolution, immediately before launch.
# An editor opened during those checks must also be reused or rejected.
$sessions = @(Get-NightfallEditorSessions -WorkspacePath $workspacePath)
if ((Get-NightfallEditorEntryState -Sessions $sessions) -eq 'already_running') {
    Write-Output ('EDITOR_ALREADY_RUNNING ' + (@($sessions.ProcessId) -join ',') + ' ' + $workspacePath)
    return
}
# This entry is explicitly invoked by the user to open the interactive editor.
Start-Process -FilePath $enginePath -WorkingDirectory $workspacePath -WindowStyle Normal -ArgumentList @('--editor', '--path', ('"' + $workspacePath + '"'))
