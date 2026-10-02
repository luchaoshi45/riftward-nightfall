@echo off
cd /d "%~dp0"
if exist "build\Riftward_Nightfall_v0.8.17.exe" (
    start "" "build\Riftward_Nightfall_v0.8.17.exe"
) else (
    echo Build not found. Open project.godot with Godot 4.6 and press F5.
    pause
)










