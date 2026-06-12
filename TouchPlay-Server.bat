@echo off
TITLE TouchPlay Server
cd /d "%~dp0"

::----------------------------------------------------------
:: Thin launcher: elevates, makes sure deps exist, then opens
:: the TouchPlay Server WINDOW (gui.py) and closes itself.
:: All the old console-era work (USB port forwarding, status)
:: now lives inside the server app - nothing to watch here.
::
:: End users with the packaged build just run
:: TouchPlay-Server.exe instead - same window, no Python.
::----------------------------------------------------------

:: Self-elevate to Administrator (firewall rules + input into elevated games)
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

:: Python present?
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo   [ERROR] Python is not installed or not in PATH.
    echo   Run TouchPlay-Setup.bat first.
    echo.
    pause
    exit /b
)

:: Auto-install missing packages silently (first run only)
python -c "import websockets, vgamepad, rich, cv2, numpy, dxcam" >nul 2>&1
if %errorlevel% neq 0 (
    echo   [..] First run - installing required packages, please wait...
    python -m pip install -r "%~dp0server\requirements.txt" --quiet
)

:: Launch the server window detached (pythonw = no console) and exit.
start "" pythonw "%~dp0server\main.py"
exit /b
