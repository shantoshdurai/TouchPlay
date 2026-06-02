@echo off
title TouchPlay Controller - Server

python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found. Install Python 3.9+ from https://python.org
    pause & exit /b 1
)

:: Install requirements only if missing (keeps later launches fast)
python -c "import vgamepad, websockets" >nul 2>&1
if errorlevel 1 (
    echo  First run: installing dependencies, please wait...
    pip install -r "%~dp0server\requirements.txt" -q --disable-pip-version-check
)

:: Set UTF-8 so box-drawing characters render correctly
chcp 65001 >nul 2>&1

:: Clear the screen for a clean terminal
cls

echo.
echo  ==========================================
echo   TouchPlay Controller  ^|  Server
echo  ==========================================
echo.

:: ADB: port-forward so phone's localhost:8765 tunnels to this PC
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
if exist "%ADB%" (
    "%ADB%" forward tcp:8765 tcp:8765 >nul 2>&1
    "%ADB%" shell am start -n com.fh6controller.fh6_controller/.MainActivity >nul 2>&1
)

cd /d "%~dp0server"
python main.py

pause
