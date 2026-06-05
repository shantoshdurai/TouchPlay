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
    if errorlevel 1 pause
    exit /b
)

chcp 65001 >nul 2>&1

powershell -ExecutionPolicy Bypass -Command ^
  "try { $f = '%~f0'; $raw = [IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8); $ps = $raw.Substring($raw.LastIndexOf('#<PS>')+5); Invoke-Expression $ps } catch { Write-Host $_ -ForegroundColor Red; exit 1 }"
if errorlevel 1 pause
exit /b

#<PS>
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.PSCommandPath
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
$BatPath = Join-Path $ScriptDir "TouchPlay-Server.bat"
$MainPyPath = Join-Path $ScriptDir "server\main.py"

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

if (-not (Test-Path $BatPath)) {
    Fail "TouchPlay-Server.bat not found.`n  Make sure it's in the same folder as this setup file."
}
if (-not (Test-Path $MainPyPath)) {
    Fail "server\main.py not found.`n  Make sure the 'server' folder is present."
}

# ── Check Python ─────────────────────────────────────────────────────────────
Write-Host "  [1/4] Checking Python..." -ForegroundColor White
try {
    $pyVersion = & python --version 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Python not found" }
    OK "Python is installed: $pyVersion"
} catch {
    Fail "Python is not installed or not in PATH.`n  Please install Python 3.10+ from python.org and try again."
}

# ── ViGEm Bus Driver ──────────────────────────────────────────────────────────
Write-Host "`n  [2/4] ViGEm gamepad driver" -ForegroundColor White
$vigEmOk = $false
try {
    $svc = Get-Service -Name ViGEmBus -ErrorAction SilentlyContinue
    if ($svc) { $vigEmOk = $true }
} catch {}

if ($vigEmOk) {
    OK "ViGEm driver already installed"
} else {
    Write-Host "        Downloading driver..." -ForegroundColor DarkGray
    try {
        $api   = Invoke-RestMethod "https://api.github.com/repos/nefarius/ViGEmBus/releases/latest" `
                    -UseBasicParsing -Headers @{"User-Agent"="TouchPlay-Setup"}
        $asset = $api.assets | Where-Object { $_.name -match "\.exe$" } | Select-Object -First 1
        $tmp   = "$env:TEMP\ViGEmBus-setup.exe"
        $req = [System.Net.WebRequest]::Create($asset.browser_download_url)
        $req.UserAgent = "TouchPlay-Setup"
        $res = $req.GetResponse()
        $total = $res.ContentLength
        $stream = $res.GetResponseStream()
        $fs = New-Object System.IO.FileStream $tmp, Create
        $buffer = New-Object byte[] 8192
        $read = 0; $downloaded = 0; $pacState = 0
        
        Write-Host -NoNewline "        "
        do {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -gt 0) {
                $fs.Write($buffer, 0, $read)
                $downloaded += $read
                $pct = if ($total -gt 0) { [math]::Floor(($downloaded / $total) * 100) } else { 0 }
                $cols = 20
                $filled = [math]::Floor(($pct / 100) * $cols)
                $pac = if ($pacState % 2 -eq 0) { "C" } else { "c" }
                if ($pct -eq 100) { $pac = "☻" }
                $pacState++
                $bar = ""
                if ($filled -gt 0) { $bar += "-" * ($filled - 1) + $pac }
                $empty = $cols - $filled
                if ($empty -gt 0) { $bar += "·" * $empty }
                Write-Host -NoNewline "`r        [$bar] $pct%  "
            }
        } while ($read -gt 0)
        $fs.Close(); $stream.Close(); Write-Host ""
        
        $p = Start-Process $tmp -ArgumentList "/passive /norestart" -Wait -PassThru
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        if ($p.ExitCode -eq 3010) { Warn "Reboot required to finish driver install — reboot then relaunch the server" }
        else { OK "ViGEm driver installed" }
    } catch {
        Warn "Could not install driver automatically."
        Warn "Get it from: github.com/nefarius/ViGEmBus/releases/latest"
    }
}

# ── Python Dependencies ───────────────────────────────────────────────────────
Write-Host "`n  [3/4] Python Dependencies" -ForegroundColor White
try {
    Write-Host "        Installing packages (vgamepad, websockets, rich)..." -ForegroundColor DarkGray
    $pipProc = Start-Process python -ArgumentList "-m pip install -r `"$ScriptDir\server\requirements.txt`"" -Wait -NoNewWindow -PassThru
    if ($pipProc.ExitCode -eq 0) {
        OK "Dependencies installed successfully"
    } else {
        Warn "pip install returned an error. Check if requirements are met."
    }
} catch {
    Warn "Failed to run pip install: $_"
}

# ── Firewall rules ────────────────────────────────────────────────────────────
Write-Host "`n  [4/4] Firewall rules" -ForegroundColor White
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
Write-Host "`n  [*] Desktop shortcut" -ForegroundColor White
try {
    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut(
        "$([Environment]::GetFolderPath('Desktop'))\TouchPlay Server.lnk")
    $lnk.TargetPath = $BatPath
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
$ans = Read-Host "  Launch TouchPlay Server now? (Y/N)"
if ($ans -match '^[yY]') {
    Write-Host "  Starting server..." -ForegroundColor Cyan
    Start-Process $BatPath -WorkingDirectory $ScriptDir
}
