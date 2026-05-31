@echo off
title FH6 Controller Server

echo.
echo  ==========================================
echo   Universal Gamepad Controller - Server
echo  ==========================================
echo.

python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found. Install Python 3.9+ from https://python.org
    pause & exit /b 1
)

echo [OK] Python found
echo.
echo [*] Installing / updating dependencies...
pip install -r "%~dp0server\requirements.txt" -q
if errorlevel 1 (echo [ERROR] pip install failed. & pause & exit /b 1)
echo [OK] Dependencies ready
echo.

:: ADB forward — tunnels phone localhost:8765 to this PC's port 8765
:: This means the app auto-connects via USB with no QR or IP needed
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
if exist "%ADB%" (
    echo [*] Setting up USB tunnel ^(adb forward^)...
    "%ADB%" forward tcp:8765 tcp:8765 >nul 2>&1
    if errorlevel 1 (
        echo [!!] ADB forward failed - phone may not be connected. WiFi will still work.
    ) else (
        echo [OK] USB tunnel ready - app will auto-connect when opened!
    )
) else (
    echo [!!] ADB not found - skipping USB tunnel. WiFi/QR still works.
)

echo.
echo [*] Starting WebSocket server on port 8765...
echo     USB plugged in = auto connects instantly
echo     Press Ctrl+C to stop.
echo.

cd /d "%~dp0server"
python main.py

pause
