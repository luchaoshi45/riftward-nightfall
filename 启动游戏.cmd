@echo off
cd /d "%~dp0"
if exist "build\Riftward_Nightfall_v0.8.21.exe" (
    start "" "build\Riftward_Nightfall_v0.8.21.exe"
) else (
    echo Build not found. Run the editor launcher with Godot 4.7.2 and press F5.
    pause
)
