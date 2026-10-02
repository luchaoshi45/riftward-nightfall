param([string[]]$Clips = @('01_menu','02_map','03_movement','04_skills','05_battle','06_shop','07_recall','08_victory','09_models'))
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$captureRoot = Join-Path $projectRoot 'tmp/devlog_project'
$godotBin = 'C:/Program Files/Godot/Godot_v4.6.2-stable_win64_console.exe'
$ffmpegBin = (Get-Command ffmpeg).Source
New-Item -ItemType Directory -Force $captureRoot,(Join-Path $captureRoot 'tools') | Out-Null
foreach ($folder in @('scripts','scenes','assets')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $folder) -Destination $captureRoot -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'devlog_capture.gd') -Destination (Join-Path $captureRoot 'tools') -Force
$config = [IO.File]::ReadAllText((Join-Path $projectRoot 'project.godot'))
$config = $config.Replace('viewport_width=1440','viewport_width=1920').Replace('viewport_height=900','viewport_height=1080').Replace('window_width_override=1440','window_width_override=1920').Replace('window_height_override=900','window_height_override=1080')
[IO.File]::WriteAllText((Join-Path $captureRoot 'project.godot'),$config)
& $godotBin --headless --path $captureRoot --editor --import *> (Join-Path $projectRoot 'tmp/devlog/import.log')
if ($LASTEXITCODE -ne 0) { throw 'Capture project import failed' }
foreach ($clipId in $Clips) {
    $movie = Join-Path $projectRoot "tmp/devlog/$clipId.avi"
    $recordLog = Join-Path $projectRoot "tmp/devlog/$clipId.log"
    $screenDir = Join-Path $projectRoot 'devlog/v0.1/screenshots'
    & $godotBin --path $captureRoot --resolution 1920x1080 --write-movie $movie --fixed-fps 30 --disable-vsync --quit-after 750 --script res://tools/devlog_capture.gd -- "--clip=$clipId" "--out=$screenDir" *> $recordLog
    if (!(Select-String -LiteralPath $recordLog -Pattern "RECORDING_DONE: $clipId" -Quiet)) { throw "Incomplete capture: $clipId" }
    $mp4 = Join-Path $projectRoot "devlog/v0.1/video/$clipId.mp4"
    & $ffmpegBin -y -hide_banner -loglevel error -i $movie -c:v libx264 -preset medium -crf 17 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart $mp4
    if ($LASTEXITCODE -ne 0) { throw "Encoding failed: $clipId" }
    Write-Output "DONE $clipId"
}
