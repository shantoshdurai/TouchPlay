@echo off
TITLE TouchPlay Server
cd /d "%~dp0"

:: Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python is not installed or not in PATH.
    echo Please install Python 3.10+ from python.org and try again.
    pause
    exit /b
)

echo Starting TouchPlay Server...
python server\main.py

:: If the server crashes or closes, pause so the user can see the error
pause
