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
echo    by Geek Moggers                             Setup v1.0
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
echo          vgamepad  websockets  rich  mss  Pillow
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

powershell -NoProfile -ExecutionPolicy Bypass -Command "try { if (!(Get-NetFirewallRule -DisplayName 'TouchPlay TCP' -ErrorAction SilentlyContinue)) { New-NetFirewallRule -DisplayName 'TouchPlay TCP' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8765 | Out-Null; Write-Host '  [OK] TouchPlay TCP     port 8765  (controller)' } else { Write-Host '  [--] TouchPlay TCP     already exists' }; if (!(Get-NetFirewallRule -DisplayName 'TouchPlay UDP' -ErrorAction SilentlyContinue)) { New-NetFirewallRule -DisplayName 'TouchPlay UDP' -Direction Inbound -Action Allow -Protocol UDP -LocalPort 8766 | Out-Null; Write-Host '  [OK] TouchPlay UDP     port 8766  (discovery)' } else { Write-Host '  [--] TouchPlay UDP     already exists' }; if (!(Get-NetFirewallRule -DisplayName 'TouchPlay Stream' -ErrorAction SilentlyContinue)) { New-NetFirewallRule -DisplayName 'TouchPlay Stream' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8767 | Out-Null; Write-Host '  [OK] TouchPlay Stream  port 8767  (game stream)' } else { Write-Host '  [--] TouchPlay Stream  already exists' } } catch { Write-Host '  [!!] Firewall config blocked by Windows.' }"

echo.

::----------------------------------------------------------
:: Desktop shortcut
::----------------------------------------------------------
echo   Creating Desktop shortcut...
set "_BAT=%~dp0TouchPlay-Server.bat"
set "_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=New-Object -ComObject WScript.Shell; $l=$s.CreateShortcut([Environment]::GetFolderPath('Desktop')+'\TouchPlay Server.lnk'); $l.TargetPath='%_BAT%'; $l.WorkingDirectory='%_DIR%'; $l.Description='TouchPlay - Start Controller Server'; $l.Save()"
echo   [OK] Shortcut on Desktop
echo.

::----------------------------------------------------------
:: Done
::----------------------------------------------------------
echo   +----------------------------------------------------+
echo   ^|  Setup complete!                                   ^|
echo   ^|  Use "TouchPlay Server" shortcut on your Desktop. ^|
echo   +----------------------------------------------------+
echo.
set /p "GO=   Launch server now? (Y/N): "
if /i "%GO%"=="Y" start "" "%~dp0TouchPlay-Server.bat"
echo.
echo   Press any key to close...
pause >nul
