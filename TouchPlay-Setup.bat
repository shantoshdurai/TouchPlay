@echo off
:: ============================================================================
::  TouchPlay Setup  —  Fully automatic first-time installer
::  Installs Python, pip packages, AND the ViGEm gamepad driver silently.
::  Run this once on a new PC; everything is handled automatically.
:: ============================================================================

:: ── Require admin (needed to install ViGEm driver + firewall rules) ──────────
net session >nul 2>&1
if errorlevel 1 (
    echo  [TouchPlay] Requesting administrator rights...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs -Wait"
    exit /b
)

:: ── Set UTF-8 console so box-drawing chars render correctly ──────────────────
chcp 65001 >nul 2>&1

:: ── Run the embedded PowerShell setup script ─────────────────────────────────
powershell -ExecutionPolicy Bypass -Command ^
  "& { $f = '%~f0'; $raw = [IO.File]::ReadAllText($f); $ps = $raw.Substring($raw.LastIndexOf('#<PS>')+5); Invoke-Expression $ps }"
exit /b

#<PS>
# =============================================================================
#  TouchPlay Setup — PowerShell payload
#  Everything below runs as Administrator.
# =============================================================================

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent ([Environment]::GetCommandLineArgs()[0]) }

# Fall back to the bat file's own directory
$ScriptDir = (Get-Item $MyInvocation.PSCommandPath -ErrorAction SilentlyContinue)?.Directory?.FullName
if (-not $ScriptDir) { $ScriptDir = $PSScriptRoot }
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

$ServerDir = Join-Path $ScriptDir "server"

# ── Console helpers ───────────────────────────────────────────────────────────
function Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ████████╗ ██████╗ ██╗   ██╗ ██████╗██╗  ██╗" -ForegroundColor Cyan
    Write-Host "     ██╔══╝██╔═══██╗██║   ██║██╔════╝██║  ██║" -ForegroundColor Cyan
    Write-Host "     ██║   ██║   ██║██║   ██║██║     ███████║" -ForegroundColor Cyan
    Write-Host "     ╚═╝   ╚██████╔╝╚██████╔╝╚██████╗██║  ██║" -ForegroundColor Cyan
    Write-Host "            ╚═════╝  ╚═════╝  ╚═════╝╚═╝  ╚═╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "     ██████╗ ██╗      █████╗ ██╗   ██╗" -ForegroundColor Cyan
    Write-Host "     ██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝" -ForegroundColor Cyan
    Write-Host "     ██████╔╝██║     ███████║ ╚████╔╝" -ForegroundColor Cyan
    Write-Host "     ██╔═══╝ ██║     ██╔══██║  ╚██╔╝" -ForegroundColor Cyan
    Write-Host "     ╚═╝     ███████╗██║  ██║   ██║" -ForegroundColor Cyan
    Write-Host "             ╚══════╝╚═╝  ╚═╝   ╚═╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "   First-Time Setup  ·  This runs once only" -ForegroundColor DarkGray
    Write-Host "  ─────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
}

function Step([string]$n, [string]$msg) {
    Write-Host "  [$n] $msg" -ForegroundColor White
}
function OK([string]$msg) {
    Write-Host "      ✓  $msg" -ForegroundColor Green
}
function Skip([string]$msg) {
    Write-Host "      –  $msg (already installed)" -ForegroundColor DarkGray
}
function Warn([string]$msg) {
    Write-Host "      ⚠  $msg" -ForegroundColor Yellow
}
function Fail([string]$msg) {
    Write-Host ""
    Write-Host "  ✗  ERROR: $msg" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Press Enter to close..." -ForegroundColor DarkGray
    [void][Console]::ReadLine()
    exit 1
}

# ── Step tracker ──────────────────────────────────────────────────────────────
$total = 5; $step = 0
function NextStep([string]$label) {
    $script:step++
    Write-Host ""
    Write-Host "  ┌─ Step $step/$total : $label" -ForegroundColor Cyan
}

Banner

# =============================================================================
# STEP 1 — Python
# =============================================================================
NextStep "Python 3.11+"

$py = $null
foreach ($cmd in @("python","python3","py")) {
    try {
        $v = & $cmd --version 2>&1
        if ($v -match "Python 3\.(\d+)" -and [int]$Matches[1] -ge 9) {
            $py = $cmd; break
        }
    } catch {}
}

if ($py) {
    Skip "Python found: $(& $py --version 2>&1)"
} else {
    Step "1a" "Installing Python via winget..."
    $wingetOk = $false
    try {
        winget install Python.Python.3.11 `
            --accept-package-agreements --accept-source-agreements `
            --silent --scope machine
        # Refresh PATH
        $env:PATH = [Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                    [Environment]::GetEnvironmentVariable("PATH","User")
        $py = "python"
        $wingetOk = $true
        OK "Python installed via winget"
    } catch {
        Warn "winget failed — trying direct download..."
    }

    if (-not $wingetOk) {
        Step "1b" "Downloading Python 3.11 installer (~25 MB)..."
        try {
            $pyUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
            $pyTmp = "$env:TEMP\python-installer.exe"
            Invoke-WebRequest $pyUrl -OutFile $pyTmp -UseBasicParsing
            Start-Process $pyTmp -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" -Wait
            Remove-Item $pyTmp -Force -ErrorAction SilentlyContinue
            $env:PATH = [Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                        [Environment]::GetEnvironmentVariable("PATH","User")
            $py = "python"
            OK "Python 3.11 installed"
        } catch {
            Fail "Could not install Python. Visit python.org and install 3.11+, then re-run this setup."
        }
    }
}

# =============================================================================
# STEP 2 — pip packages
# =============================================================================
NextStep "Python packages"

$req = Join-Path $ServerDir "requirements.txt"
if (-not (Test-Path $req)) {
    Fail "requirements.txt not found at: $req`nMake sure the 'server' folder is next to this bat file."
}

Step "2" "Installing packages from requirements.txt..."
try {
    & $py -m pip install -r $req -q --disable-pip-version-check 2>&1 | Out-Null
    OK "All packages installed"
} catch {
    Fail "pip install failed. Check your internet connection and try again."
}

# =============================================================================
# STEP 3 — ViGEm Bus Driver (the gamepad emulation driver)
# =============================================================================
NextStep "ViGEm Bus Driver  (Xbox gamepad emulation)"

# Quick check: try to create a virtual gamepad — if it works, driver is present.
$vigEmOk = $false
try {
    $check = & $py -c "import vgamepad; g=vgamepad.VX360Gamepad(); del g; print('ok')" 2>&1
    if ($check -match "ok") { $vigEmOk = $true }
} catch {}

if ($vigEmOk) {
    Skip "ViGEm driver already installed and working"
} else {
    Step "3" "Downloading ViGEm Bus Driver..."
    try {
        # Fetch latest release info from GitHub API
        $apiUrl = "https://api.github.com/repos/nefarius/ViGEmBus/releases/latest"
        $rel    = Invoke-RestMethod $apiUrl -UseBasicParsing -Headers @{
            "User-Agent" = "TouchPlay-Setup/1.0"
        }
        $asset  = $rel.assets | Where-Object { $_.name -match "\.exe$" } | Select-Object -First 1
        if (-not $asset) { throw "No exe asset found in latest release" }

        $vigEmTmp = "$env:TEMP\ViGEmBus-installer.exe"
        Write-Host "      Downloading $($asset.name)..." -ForegroundColor DarkGray
        Invoke-WebRequest $asset.browser_download_url -OutFile $vigEmTmp -UseBasicParsing

        Write-Host "      Installing driver (silent)..." -ForegroundColor DarkGray
        $proc = Start-Process $vigEmTmp -ArgumentList "/passive /norestart" -Wait -PassThru
        Remove-Item $vigEmTmp -Force -ErrorAction SilentlyContinue

        if ($proc.ExitCode -notin @(0, 3010)) {
            throw "Installer exited with code $($proc.ExitCode)"
        }
        OK "ViGEm Bus Driver installed"

        # Final verification
        $check2 = & $py -c "import vgamepad; g=vgamepad.VX360Gamepad(); del g; print('ok')" 2>&1
        if ($check2 -notmatch "ok") {
            if ($proc.ExitCode -eq 3010) {
                Warn "A REBOOT IS REQUIRED to complete the driver install. Reboot then re-run setup."
            } else {
                Warn "Driver installed but gamepad test failed. Try rebooting."
            }
        } else {
            OK "Gamepad emulation verified"
        }
    } catch {
        Warn "Could not auto-install ViGEm: $_"
        Warn "Please install it manually from: https://github.com/nefarius/ViGEmBus/releases/latest"
        Warn "Then re-run this setup."
    }
}

# =============================================================================
# STEP 4 — Windows Firewall rules
# =============================================================================
NextStep "Windows Firewall rules"

foreach ($r in @(
    @{name="TouchPlay Server TCP"; proto="TCP"; port=8765},
    @{name="TouchPlay Server UDP"; proto="UDP"; port=8766}
)) {
    $chk = netsh advfirewall firewall show rule "name=$($r.name)" 2>&1
    if ($chk -notmatch "No rules match") {
        Skip "$($r.name)"
    } else {
        netsh advfirewall firewall add rule `
            "name=$($r.name)" dir=in action=allow `
            "protocol=$($r.proto)" "localport=$($r.port)" | Out-Null
        OK "Added firewall rule: $($r.name)"
    }
}

# =============================================================================
# STEP 5 — Desktop shortcut
# =============================================================================
NextStep "Desktop shortcut"

$serverBat = Join-Path $ScriptDir "run_server.bat"
$desktop   = [Environment]::GetFolderPath("Desktop")
$lnkPath   = Join-Path $desktop "TouchPlay Server.lnk"

try {
    $wsh = New-Object -ComObject WScript.Shell
    $lnk = $wsh.CreateShortcut($lnkPath)
    $lnk.TargetPath       = $serverBat
    $lnk.WorkingDirectory = $ScriptDir
    $lnk.Description      = "TouchPlay — Start Controller Server"
    # Use cmd.exe icon (closest built-in; replace with your own .ico if desired)
    $lnk.IconLocation     = "cmd.exe,0"
    $lnk.WindowStyle      = 1
    $lnk.Save()
    OK "Shortcut created on Desktop: 'TouchPlay Server'"
} catch {
    Warn "Could not create shortcut: $_"
}

# =============================================================================
# DONE
# =============================================================================
Write-Host ""
Write-Host "  ─────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "   Setup complete!  Everything is ready." -ForegroundColor Green
Write-Host "  ─────────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  HOW TO PLAY:" -ForegroundColor White
Write-Host "   1. Double-click [TouchPlay Server] on your Desktop" -ForegroundColor DarkGray
Write-Host "   2. Open the TouchPlay app on your phone" -ForegroundColor DarkGray
Write-Host "   3. The app auto-connects — start gaming!" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  CO-OP:  Up to 4 phones at once (each gets its own controller)" -ForegroundColor DarkGray
Write-Host ""

Write-Host "  Press Enter to close..." -ForegroundColor DarkGray
[void][Console]::ReadLine()
