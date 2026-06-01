@echo off
title FH6 Controller Server

python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found. Install Python 3.9+ from https://python.org
    pause & exit /b 1
)

:: Install requirements silently and disable the pip update warning
pip install -r "%~dp0server\requirements.txt" -q --disable-pip-version-check
if errorlevel 1 (echo [ERROR] pip install failed. & pause & exit /b 1)

:: Clear the screen for a clean, minimalistic terminal
cls

echo.
echo  ==========================================
echo   Universal Gamepad Controller - Server
echo  ==========================================
echo.

:: ADB forward — tunnels phone localhost:8765 to this PC's port 8765
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
if exist "%ADB%" (
    "%ADB%" forward tcp:8765 tcp:8765 >nul 2>&1
)

cd /d "%~dp0server"
python main.py

pause
