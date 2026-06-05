@echo off
:: ============================================================================
::  TouchPlay Setup  —  Run this once on a new PC
::  Installs the ViGEm gamepad driver and creates a Desktop shortcut.
::  No Python required — the server is a standalone .exe.
:: ============================================================================

net session >nul 2>&1
if errorlevel 1 (
    echo  [TouchPlay] Requesting administrator rights...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs -Wait"
    exit /b
)

chcp 65001 >nul 2>&1

powershell -ExecutionPolicy Bypass -Command ^
  "& { $f = '%~f0'; $raw = [IO.File]::ReadAllText($f); $ps = $raw.Substring($raw.LastIndexOf('#<PS>')+5); Invoke-Expression $ps }"
exit /b

#<PS>
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.PSCommandPath
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
$ExePath = Join-Path $ScriptDir "TouchPlay-Server.exe"

function Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ████████╗ ██████╗ ██╗   ██╗ ██████╗██╗  ██╗" -ForegroundColor Cyan
    Write-Host "     ██╔══╝██╔═══██╗██║   ██║██╔════╝██║  ██║" -ForegroundColor Cyan
    Write-Host "     ██║   ██║   ██║██║   ██║██║     ███████║" -ForegroundColor Cyan
    Write-Host "     ╚═╝   ╚██████╔╝╚██████╔╝╚██████╗██║  ██║" -ForegroundColor Cyan
    Write-Host "            ╚═════╝  ╚═════╝  ╚═════╝╚═╝  ╚═╝" -ForegroundColor Cyan
    Write-Host "     ██████╗ ██╗      █████╗ ██╗   ██╗"        -ForegroundColor Cyan
    Write-Host "     ██╔══██╗██║     ██╔══██╗╚██╗ ██╔╝"        -ForegroundColor Cyan
    Write-Host "     ██████╔╝██║     ███████║ ╚████╔╝ "        -ForegroundColor Cyan
    Write-Host "     ╚═╝     ███████╗██║  ██║   ██║  "         -ForegroundColor Cyan
    Write-Host "             ╚══════╝╚═╝  ╚═╝   ╚═╝  "         -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "   First-Time Setup  ·  This runs once only" -ForegroundColor DarkGray
    Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
}

function OK($m)   { Write-Host "  ✓  $m" -ForegroundColor Green }
function Skip($m) { Write-Host "  –  $m" -ForegroundColor DarkGray }
function Warn($m) { Write-Host "  ⚠  $m" -ForegroundColor Yellow }
function Fail($m) {
    Write-Host "`n  ✗  $m" -ForegroundColor Red
    Write-Host "`n  Press Enter to close..."; [void][Console]::ReadLine(); exit 1
}

Banner

# Check exe exists
if (-not (Test-Path $ExePath)) {
    Fail "TouchPlay-Server.exe not found.`n  Make sure it's in the same folder as this setup file."
}

# ── Strip SmartScreen block (Mark of the Web) ─────────────────────────────────
# Windows tags files downloaded from the internet with a Zone.Identifier stream.
# When that tag is present, SmartScreen shows the "Windows protected your PC"
# blue-screen warning. We unblock the exe here (admin context, before first run)
# so the user never sees it. Same as right-click → Properties → Unblock.
Write-Host "  [0/3] Removing SmartScreen block..." -ForegroundColor White
try {
    Unblock-File -Path $ExePath -ErrorAction Stop
    # Also unblock this bat and any other files in the folder
    Get-ChildItem $ScriptDir -File | ForEach-Object {
        Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
    }
    OK "SmartScreen block removed — exe will launch without warning"
} catch {
    Warn "Could not remove SmartScreen block: $_"
    Warn "If Windows blocks the exe, right-click it → Properties → Unblock"
}

# ── ViGEm Bus Driver ──────────────────────────────────────────────────────────
Write-Host "  [1/3] ViGEm gamepad driver" -ForegroundColor White
$vigEmOk = $false
try {
    $svc = Get-Service -Name ViGEmBus -ErrorAction SilentlyContinue
    if ($svc) { $vigEmOk = $true }
} catch {}

if ($vigEmOk) {
    Skip "ViGEm driver already installed"
} else {
    Write-Host "        Downloading driver..." -ForegroundColor DarkGray
    try {
        $api   = Invoke-RestMethod "https://api.github.com/repos/nefarius/ViGEmBus/releases/latest" `
                    -UseBasicParsing -Headers @{"User-Agent"="TouchPlay-Setup"}
        $asset = $api.assets | Where-Object { $_.name -match "\.exe$" } | Select-Object -First 1
        $tmp   = "$env:TEMP\ViGEmBus-setup.exe"
        Invoke-WebRequest $asset.browser_download_url -OutFile $tmp -UseBasicParsing
        $p = Start-Process $tmp -ArgumentList "/passive /norestart" -Wait -PassThru
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        if ($p.ExitCode -eq 3010) { Warn "Reboot required to finish driver install — reboot then relaunch the server" }
        else { OK "ViGEm driver installed" }
    } catch {
        Warn "Could not install driver automatically."
        Warn "Get it from: github.com/nefarius/ViGEmBus/releases/latest"
    }
}

# ── Firewall rules ────────────────────────────────────────────────────────────
Write-Host "`n  [2/3] Firewall rules" -ForegroundColor White
foreach ($r in @(
    @{n="TouchPlay TCP"; p="TCP"; port=8765},
    @{n="TouchPlay UDP"; p="UDP"; port=8766}
)) {
    $chk = netsh advfirewall firewall show rule "name=$($r.n)" 2>&1
    if ($chk -notmatch "No rules match") { Skip $r.n }
    else {
        netsh advfirewall firewall add rule "name=$($r.n)" dir=in action=allow "protocol=$($r.p)" "localport=$($r.port)" | Out-Null
        OK "Firewall: $($r.n)"
    }
}

# ── Desktop shortcut ──────────────────────────────────────────────────────────
Write-Host "`n  [3/3] Desktop shortcut" -ForegroundColor White
try {
    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut(
        "$([Environment]::GetFolderPath('Desktop'))\TouchPlay Server.lnk")
    $lnk.TargetPath = $ExePath
    $lnk.WorkingDirectory = $ScriptDir
    $lnk.Description = "TouchPlay — Start Controller Server"
    $lnk.Save()
    OK "Shortcut created on Desktop"
} catch { Warn "Could not create shortcut: $_" }

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ─────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "   Done!  Double-click [TouchPlay Server] on your Desktop to start." -ForegroundColor Green
Write-Host "  ─────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Press Enter to close..."; [void][Console]::ReadLine()
