param([Parameter(Mandatory=$true)][string]$Test, [switch]$Render, [string]$Pack)
$ErrorActionPreference='Stop'
$taskWorkspace=Split-Path $PSScriptRoot -Parent
if ($Test -notmatch '^[a-z0-9_]+$') { throw 'Invalid test name' }
$taskEngine=& "$PSScriptRoot/resolve_godot.ps1"
$taskLabel=if($Render){'render'}else{'headless'}
$taskOut=Join-Path $taskWorkspace "build/$Test-$taskLabel.out.log"
$taskErr=Join-Path $taskWorkspace "build/$Test-$taskLabel.err.log"
$taskArgs=@('--audio-driver','Dummy')
if ($Render) {$taskArgs+=@('--position','10000,10000')} else {$taskArgs+='--headless'}
if ($Pack) {$taskArgs+=@('--main-pack',('"'+$Pack+'"'))} else {$taskArgs+=@('--path','"'+$taskWorkspace+'"')}
$taskArgs+=@('--script',('"'+(Join-Path $taskWorkspace "tests/$Test.gd")+'"'))
$taskProcess=Start-Process $taskEngine -WorkingDirectory $taskWorkspace -WindowStyle Hidden -ArgumentList $taskArgs -RedirectStandardOutput $taskOut -RedirectStandardError $taskErr -PassThru
$taskHandle=$taskProcess.Handle
try {
    if (-not $taskProcess.WaitForExit(90000)) {throw 'Test timed out'}
    $taskProcess.Refresh()
    Get-Content -LiteralPath $taskOut,$taskErr
    if($taskProcess.ExitCode -ne 0 -or (Select-String -LiteralPath $taskOut,$taskErr -Pattern 'SCRIPT ERROR|ERROR:|WARNING:.*(leaked|still in use)')) {throw 'Game check failed'}
    if(-not(Select-String -LiteralPath $taskOut -Pattern '_OK')) {throw 'Missing completion marker'}
} finally {
    if(-not $taskProcess.HasExited){Stop-Process -Id $taskProcess.Id}
}
