@echo off
TITLE TouchPlay Server
cd /d "%~dp0"

::----------------------------------------------------------
:: Self-elevate to Administrator (required for input injection)
::----------------------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/k \"%~f0\"' -Verb RunAs"
    exit /b
)

cls

echo.
echo    _______                __   ______  __           
echo   ^|_     _^|.-----.--.--.----^|  ^|--^|   __ \^|  ^|---.-.--.--.
echo     ^|   ^|  ^|  _  ^|  ^|  ^|  __^|     ^|    __/^|  ^|  _  ^|  ^|  ^|
echo     ^|___^|  ^|_____^|_____^|____^|__^|__^|___^|   ^|__^|___._^|___  ^|
echo                                                    ^|_____^|
echo.
echo    by Geek Moggers                            Server v1.0
echo.

:: Check Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo   [ERROR] Python is not installed or not in PATH.
    echo   Run TouchPlay-Setup.bat first.
    echo.
    pause
    exit /b
)

:: Auto-install missing packages silently
python -c "import websockets, vgamepad, rich, mss, PIL" >nul 2>&1
if %errorlevel% neq 0 (
    echo   [..] Installing required packages, please wait...
    python -m pip install -r "%~dp0server\requirements.txt" --quiet
    echo   [OK] Packages ready
    echo.
)

echo   [OK] Starting server...
echo   [OK] Your phone app will find this PC automatically.
echo.
echo   Press Ctrl+C to stop the server.
echo   ....................................................
echo.
python server\main.py

pause
