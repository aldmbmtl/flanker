@echo off
setlocal EnableDelayedExpansion

set "GODOT_GUI=C:\Users\nived\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe"
set "GODOT_CONSOLE=C:\Users\nived\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe"
set "PROJECT=C:\Users\nived\flanker"

if "%1"=="" (
    echo Running headless import...
    start /b "" "%GODOT_CONSOLE%" --headless --import --path "%PROJECT%"
    echo Starting Flankers...
    start "" "%GODOT_GUI%" --path "%PROJECT%"
    echo Game started.
    exit /b
)

if "%1"=="run" (
    echo Running headless import...
    start /b "" "%GODOT_CONSOLE%" --headless --import --path "%PROJECT%"
    echo Starting Flankers...
    start "" "%GODOT_GUI%" --path "%PROJECT%"
    echo Game started.
    exit /b
)

if "%1"=="stop" (
    echo Stopping Flankers...
    taskkill /IM Godot_v4.6.2-stable_win64.exe /F 2>nul
    echo Stopped.
    exit /b
)

if "%1"=="logs" (
    echo Log file location: %TEMP%\flankers.log
    if exist "%TEMP%\flankers.log" (
        type "%TEMP%\flankers.log"
    ) else (
        echo No log file found.
    )
    exit /b
)

echo Usage: flanker.bat [run^|stop^|logs]
echo   (no arg) - start game
echo   run     - start game
echo   stop    - kill running game
echo   logs    - show log location
exit /b