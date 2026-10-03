param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$workspacePath = Split-Path $PSScriptRoot -Parent
$enginePath = & (Join-Path $PSScriptRoot 'resolve_godot.ps1') -Editor
if ($CheckOnly) {
    Write-Output "EDITOR_ENGINE_OK $enginePath"
    exit 0
}
# This entry is explicitly invoked by the user to open the interactive editor.
Start-Process -FilePath $enginePath -WorkingDirectory $workspacePath -WindowStyle Normal -ArgumentList @('--editor', '--path', ('"' + $workspacePath + '"'))
