@echo off
TITLE TouchPlay EXE Builder
cd /d "%~dp0"

:: ----------------------------------------------------------
:: Packages the PC server into a single TouchPlay-Server.exe
:: so end users never need Python or a terminal — double-click
:: and play. Run this on a dev machine; ship the exe from
:: dist\ in the GitHub release.
:: ----------------------------------------------------------

echo.
echo   TouchPlay - Building standalone server EXE
echo.

python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo   [ERROR] Python not found. Install Python 3.10+ first.
    pause
    exit /b 1
)

echo   [1/3] Installing build dependencies...
python -m pip install --quiet pyinstaller -r server\requirements.txt

echo   [2/3] Building (this takes a few minutes)...
:: --windowed: the server now opens its own dashboard window (gui.py), so no
:: console should flash up behind it. Run with --console from a terminal if
:: the old text dashboard is ever needed (it falls back automatically too).
python -m PyInstaller --noconfirm --onefile --windowed ^
    --name TouchPlay-Server ^
    --icon app_icon.ico ^
    --uac-admin ^
    --add-data "app_icon.png;." ^
    --collect-all vgamepad ^
    --collect-all dxcam ^
    --collect-all pyvirtualcam ^
    --hidden-import uiautomation ^
    --hidden-import pystray._win32 ^
    server\main.py
if %errorlevel% neq 0 (
    echo   [ERROR] Build failed - see output above.
    pause
    exit /b 1
)

echo   [3/3] Done.
echo.
echo   EXE is at: dist\TouchPlay-Server.exe
echo   Note: users still need the ViGEm driver (the exe will
echo   prompt-install firewall rules itself when run as admin).
echo.
pause
