$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }

# Self-elevate if not admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) {
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Set-Location $ScriptDir

function OK($m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function SKIP($m) { Write-Host "  [--] $m" -ForegroundColor DarkGray }
function WARN($m) { Write-Host "  [!!] $m" -ForegroundColor Yellow }
function FAIL($m) { Write-Host "`n  [ERROR] $m" -ForegroundColor Red; Write-Host "`n  Press Enter to close..."; Read-Host | Out-Null; exit 1 }

Clear-Host
Write-Host ""
Write-Host "  =================================" -ForegroundColor Cyan
Write-Host "   TouchPlay Setup" -ForegroundColor Cyan
Write-Host "  =================================" -ForegroundColor Cyan
Write-Host ""

# 1. Python
Write-Host "  [1/4] Checking Python..." -ForegroundColor White
$pyVer = & python --version 2>&1
if ($LASTEXITCODE -ne 0) { FAIL "Python not found. Install Python 3.10+ from python.org and tick Add to PATH." }
OK "$pyVer"

# 2. Packages
Write-Host "`n  [2/4] Installing Python packages..." -ForegroundColor White
Write-Host "        vgamepad, websockets, rich, mss, Pillow" -ForegroundColor DarkGray
$req = Join-Path $ScriptDir "server\requirements.txt"
if (-not (Test-Path $req)) { FAIL "server\requirements.txt not found." }
& python -m pip install -r $req --quiet
if ($LASTEXITCODE -ne 0) {
    WARN "pip had errors, retrying with --user..."
    & python -m pip install -r $req --user --quiet
}
OK "Packages ready"

# 3. ViGEm
Write-Host "`n  [3/4] ViGEm gamepad driver..." -ForegroundColor White
$svc = Get-Service -Name ViGEmBus -ErrorAction SilentlyContinue
if ($svc) {
    OK "ViGEm already installed"
} else {
    Write-Host "        Downloading driver..." -ForegroundColor DarkGray
    try {
        $api = Invoke-RestMethod "https://api.github.com/repos/nefarius/ViGEmBus/releases/latest" -UseBasicParsing -Headers @{"User-Agent"="TouchPlay"}
        $asset = $api.assets | Where-Object { $_.name -match "\.exe$" } | Select-Object -First 1
        $tmp = "$env:TEMP\ViGEmBus.exe"
        Invoke-WebRequest $asset.browser_download_url -OutFile $tmp -UseBasicParsing
        $p = Start-Process $tmp -ArgumentList "/passive /norestart" -Wait -PassThru
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        if ($p.ExitCode -eq 3010) { WARN "Reboot required to finish ViGEm install" }
        else { OK "ViGEm driver installed" }
    } catch {
        WARN "Could not auto-install ViGEm. Download from: github.com/nefarius/ViGEmBus/releases"
    }
}

# 4. Firewall
Write-Host "`n  [4/4] Firewall rules..." -ForegroundColor White
$fwRules = @(
    @{n="TouchPlay TCP";    p="TCP"; port=8765; d="controller"},
    @{n="TouchPlay UDP";    p="UDP"; port=8766; d="discovery"},
    @{n="TouchPlay Stream"; p="TCP"; port=8767; d="game stream"}
)
foreach ($r in $fwRules) {
    $chk = netsh advfirewall firewall show rule "name=$($r.n)" 2>&1
    if ($chk -notmatch "No rules match") {
        SKIP "$($r.n) already exists"
    } else {
        netsh advfirewall firewall add rule "name=$($r.n)" dir=in action=allow "protocol=$($r.p)" "localport=$($r.port)" | Out-Null
        OK "$($r.n) - port $($r.port) ($($r.d))"
    }
}

# Shortcut
Write-Host "`n  Creating Desktop shortcut..." -ForegroundColor DarkGray
try {
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut([Environment]::GetFolderPath("Desktop") + "\TouchPlay Server.lnk")
    $lnk.TargetPath = Join-Path $ScriptDir "TouchPlay-Server.bat"
    $lnk.WorkingDirectory = $ScriptDir
    $lnk.Description = "TouchPlay - Start Controller Server"
    $lnk.Save()
    OK "Shortcut on Desktop"
} catch { WARN "Could not create shortcut: $_" }

# Done
Write-Host ""
Write-Host "  =================================" -ForegroundColor Green
Write-Host "   Setup complete!" -ForegroundColor Green
Write-Host "   Use TouchPlay Server on Desktop" -ForegroundColor Green
Write-Host "  =================================" -ForegroundColor Green
Write-Host ""

$ans = Read-Host "  Launch server now? (Y/N)"
if ($ans -match "^[yY]") {
    Start-Process (Join-Path $ScriptDir "TouchPlay-Server.bat") -WorkingDirectory $ScriptDir
}

Write-Host "`n  Press Enter to close..."
Read-Host | Out-Null
