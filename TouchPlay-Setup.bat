@echo off
TITLE TouchPlay Setup
cd /d "%~dp0"

::----------------------------------------------------------
:: Self-elevate to Administrator (CMD window, not PowerShell)
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
echo    by Geek Moggers                             Setup v1.3
echo.

::----------------------------------------------------------
:: 1/4  Python
::----------------------------------------------------------
echo   [1/4] Checking Python...
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   [ERROR] Python not found.
    echo   Install Python 3.10+ from python.org
    echo   Tick "Add Python to PATH" during install.
    echo.
    pause
    exit /b 1
)
for /f "tokens=*" %%v in ('python --version 2^>^&1') do echo   [OK] %%v
echo.

::----------------------------------------------------------
:: 2/4  Python packages
::----------------------------------------------------------
echo   [2/4] Installing Python packages...
echo          vgamepad  websockets  rich  dxcam  opencv-python  pyvirtualcam
python -m pip install -r server\requirements.txt --quiet 2>nul
if %errorlevel% neq 0 (
    echo   [..] Retrying with --user...
    python -m pip install -r server\requirements.txt --user --quiet 2>nul
)
echo   [OK] Packages ready
echo.

::----------------------------------------------------------
:: 3/4  ViGEm driver
::----------------------------------------------------------
echo   [3/4] ViGEm gamepad driver...
sc query ViGEmBus >nul 2>&1
if %errorlevel% equ 0 (
    echo   [--] ViGEm already installed
    goto :vigem_done
)
echo          Downloading driver from GitHub...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$h=@{'User-Agent'='TouchPlay'}; $r=Invoke-RestMethod 'https://api.github.com/repos/nefarius/ViGEmBus/releases/latest' -Headers $h -UseBasicParsing; $u=($r.assets | Where-Object {$_.name -match '\.exe$'} | Select-Object -First 1).browser_download_url; Invoke-WebRequest $u -OutFile (Join-Path $env:TEMP 'ViGEmBus.exe') -UseBasicParsing"
if exist "%TEMP%\ViGEmBus.exe" (
    start /wait "" "%TEMP%\ViGEmBus.exe" /passive /norestart
    del "%TEMP%\ViGEmBus.exe" >nul 2>&1
    echo   [OK] ViGEm driver installed
) else (
    echo   [!!] Download failed. Get it manually from:
    echo        github.com/nefarius/ViGEmBus/releases
)
:vigem_done
echo.

::----------------------------------------------------------
:: 4/4  Firewall
::----------------------------------------------------------
echo   [4/4] Firewall rules...

powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $rules = @(@('TouchPlay TCP','TCP',8765,'controller'),@('TouchPlay UDP','UDP',8766,'discovery'),@('TouchPlay Stream','TCP',8767,'game stream'),@('TouchPlay Files','TCP',8768,'file transfer'),@('TouchPlay Cast','TCP',8769,'cam + projector')); foreach ($r in $rules) { if (!(Get-NetFirewallRule -DisplayName $r[0] -ErrorAction SilentlyContinue)) { New-NetFirewallRule -DisplayName $r[0] -Direction Inbound -Action Allow -Protocol $r[1] -LocalPort $r[2] | Out-Null; Write-Host ('  [OK] {0,-17} port {1}  ({2})' -f $r[0],$r[2],$r[3]) } else { Write-Host ('  [--] {0,-17} already exists' -f $r[0]) } } } catch { Write-Host '  [!!] Firewall config blocked by Windows.' }"

echo.

::----------------------------------------------------------
:: Start Menu shortcut (Windows search entry — one clean result)
:: Desktop shortcut is intentionally NOT created here to avoid
:: duplicate "TouchPlay Server" app entries in Windows search.
::----------------------------------------------------------
echo   Creating Start Menu entry...
:: Remove any existing Desktop shortcut from older setup runs
if exist "%USERPROFILE%\Desktop\TouchPlay Server.lnk" (
    del "%USERPROFILE%\Desktop\TouchPlay Server.lnk" >nul 2>&1
    echo   [--] Removed old Desktop shortcut (was causing duplicate in search)
)
:: Prefer the packaged exe when it's there; fall back to the bat for source installs.
set "_TARGET=%~dp0TouchPlay-Server.bat"
set "_DIR=%~dp0"
if exist "%~dp0dist\TouchPlay-Server.exe" (
    set "_TARGET=%~dp0dist\TouchPlay-Server.exe"
    set "_DIR=%~dp0dist"
)
set "_ICO=%~dp0app_icon.ico"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=New-Object -ComObject WScript.Shell; $dir=(Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Microsoft\Windows\Start Menu\Programs'); $l=$s.CreateShortcut((Join-Path $dir 'TouchPlay Server.lnk')); $l.TargetPath='%_TARGET%'; $l.WorkingDirectory='%_DIR%'; $l.Description='TouchPlay - phone gamepad, mirror, files and more'; if ('%_TARGET%' -like '*.exe') { $l.IconLocation='%_TARGET%,0' } elseif (Test-Path '%_ICO%') { $l.IconLocation='%_ICO%' }; $l.Save()"
echo   [OK] Start Menu entry created (Win key ^ "TouchPlay" to launch)
echo.

::----------------------------------------------------------
:: Done
::----------------------------------------------------------
echo   +----------------------------------------------------+
echo   ^|  Setup complete!                                   ^|
echo   ^|  Press the Windows key and type "TouchPlay"        ^|
echo   ^|  to find and launch the server.                    ^|
echo   +----------------------------------------------------+
echo.
set /p "GO=   Launch server now? (Y/N): "
if /i "%GO%"=="Y" start "" "%~dp0TouchPlay-Server.bat"
echo.
echo   Press any key to close...
pause >nul
