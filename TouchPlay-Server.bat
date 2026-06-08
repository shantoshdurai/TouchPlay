@echo off
TITLE TouchPlay Server
cd /d "%~dp0"

::----------------------------------------------------------
:: Self-elevate to Administrator (required for input injection)
::----------------------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c \"%~f0\"' -Verb RunAs"
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

::----------------------------------------------------------
:: USB auto-launch (best-effort) — if a phone is plugged in
:: over USB with debugging on, forward the ports through the
:: cable and open the app automatically. Skips silently if
:: adb isn't installed or no device is connected.
::----------------------------------------------------------
set "ADB="
where adb >nul 2>&1 && set "ADB=adb"
if not defined ADB if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
if not defined ADB if exist "%~dp0platform-tools\adb.exe" set "ADB=%~dp0platform-tools\adb.exe"

if defined ADB (
    for /f "skip=1 tokens=2" %%s in ('"%ADB%" devices 2^>nul') do (
        if "%%s"=="device" (
            echo   [USB] Phone detected — forwarding ports + launching app...
            "%ADB%" reverse tcp:8765 tcp:8765 >nul 2>&1
            "%ADB%" reverse tcp:8767 tcp:8767 >nul 2>&1
            "%ADB%" shell monkey -p com.touchplay.app -c android.intent.category.LAUNCHER 1 >nul 2>&1
            goto :usb_done
        )
    )
)
:usb_done
echo.
echo   Press Ctrl+C to stop the server.
echo   ....................................................
echo.
python server\main.py

pause
