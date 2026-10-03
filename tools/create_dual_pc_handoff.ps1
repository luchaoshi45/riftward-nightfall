param([string]$Destination)
$ErrorActionPreference = 'Stop'
$workspacePath = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
if (-not $Destination) {
    $Destination = Join-Path $workspacePath 'handoff/余烬守望-双机协作源码.zip'
}
$bundlePath = [IO.Path]::GetFullPath($Destination)
$bundleFolder = Split-Path $bundlePath -Parent
New-Item -ItemType Directory -Path $bundleFolder -Force | Out-Null
if (Test-Path -LiteralPath $bundlePath) { throw 'Choose a new bundle filename instead of overwriting an existing handoff' }

$selectedFiles = [Collections.Generic.List[IO.FileInfo]]::new()
foreach ($folderName in @('art_source','assets','scenes','scripts','tests','tools','coordination')) {
    Get-ChildItem -LiteralPath (Join-Path $workspacePath $folderName) -File -Recurse | ForEach-Object {
        $relative = $_.FullName.Substring($workspacePath.Length + 1).Replace('\','/')
        $excluded = $_.Name -like '*.blend1' -or $relative -match '(^|/)__pycache__/' -or
            $relative -match '^scripts/(day_contracts|tower_specializations)\.gd(\.uid)?$' -or
            $relative -match '^tests/(day_contracts|tower_specializations)_'
        if (-not $excluded) { $selectedFiles.Add($_) }
    }
}
foreach ($filename in @('.gitignore','AGENTS.md','ASSETS.md','DESIGN.md','README.md','STORY.md','project.godot','export_presets.cfg','optimization-progress.json','启动游戏.cmd',
    'build/watch-beacon-v2-staged.glb','build/dead-tree-v2-staged.glb','build/masonry-game-timing.json','build/masonry-game-timing-profile.json','build/masonry-game-metrics.json')) {
    $filePath = Join-Path $workspacePath $filename
    if (Test-Path -LiteralPath $filePath -PathType Leaf) { $selectedFiles.Add((Get-Item -LiteralPath $filePath)) }
}
$progress = Get-Content -LiteralPath (Join-Path $workspacePath 'optimization-progress.json') -Raw | ConvertFrom-Json
$manifest = [ordered]@{
    stable_version = $progress.latest_version
    completed = $progress.completed
    purpose = 'Second computer visual work baseline; pending graphics do not count as verified release'
    includes = 'Source, original assets, Blender sources, selected staged GLBs and material timing evidence'
    excludes = 'Git metadata, Godot cache, installed tools, Windows executables, development recordings and unfinished parallel gameplay modules'
    files = @()
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($bundlePath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $selectedFiles) {
        $relative = $file.FullName.Substring($workspacePath.Length + 1).Replace('\','/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$relative,[IO.Compression.CompressionLevel]::Fastest) | Out-Null
        $manifest.files += [ordered]@{ path=$relative; size=$file.Length; sha256=$hash }
    }
    $entry = $archive.CreateEntry('handoff-manifest.json')
    $writer = [IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false))
    try { $writer.Write(($manifest | ConvertTo-Json -Depth 6)) } finally { $writer.Dispose() }
} finally { $archive.Dispose() }

# Read back every archived entry rather than trusting a successful ZIP write.
$verifyArchive = [IO.Compression.ZipFile]::OpenRead($bundlePath)
try {
    foreach ($record in $manifest.files) {
        $entry = $verifyArchive.GetEntry($record.path)
        if (-not $entry -or $entry.Length -ne $record.size) { throw "Missing or incomplete entry: $($record.path)" }
        $stream = $entry.Open()
        $digest = [Security.Cryptography.SHA256]::Create()
        try { $actualHash = [Convert]::ToHexString($digest.ComputeHash($stream)) }
        finally { $stream.Dispose(); $digest.Dispose() }
        if ($actualHash -ne $record.sha256) { throw "Archive hash mismatch: $($record.path)" }
    }
} finally { $verifyArchive.Dispose() }
$bytes = (Get-Item -LiteralPath $bundlePath).Length
Write-Output "DUAL_PC_HANDOFF_OK files=$($manifest.files.Count) stable=$($manifest.stable_version) completed=$($manifest.completed) MB=$([math]::Round($bytes/1MB,1))"
Write-Output $bundlePath
