$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Step($m)  { Write-Host "" ; Write-Host "[>>] $m" -ForegroundColor Cyan }
function OK($m)    { Write-Host "[OK] $m" -ForegroundColor Green }
function Warn($m)  { Write-Host "[!!] $m" -ForegroundColor Yellow }
function Fail($m)  { Write-Host "" ; Write-Host "[ERROR] $m" -ForegroundColor Red ; Read-Host "Press Enter to exit" ; exit 1 }

Write-Host ""
Write-Host "  =====================================================" -ForegroundColor Magenta
Write-Host "   Universal Gamepad Controller -- Automated Setup" -ForegroundColor White
Write-Host "  =====================================================" -ForegroundColor Magenta
Write-Host ""

# ── STEP 1: Check / Install Flutter ──────────────────────────────────────────
Step "Checking Flutter..."

$hasFlutter = $false
try { $null = flutter --version 2>&1 ; $hasFlutter = $true } catch {}

if ($hasFlutter) {
    OK "Flutter already installed"
} else {
    Step "Flutter not found. Installing via winget..."

    $hasWinget = $false
    try { $null = winget --version 2>&1 ; $hasWinget = $true } catch {}

    if ($hasWinget) {
        winget install Google.Flutter --accept-package-agreements --accept-source-agreements --silent
        $machinePath = [Environment]::GetEnvironmentVariable('PATH','Machine')
        $userPath    = [Environment]::GetEnvironmentVariable('PATH','User')
        $env:PATH    = "$machinePath;$userPath"
        try { $null = flutter --version 2>&1 ; $hasFlutter = $true ; OK "Flutter installed via winget" } catch {}
    }

    if (-not $hasFlutter) {
        Step "Downloading Flutter SDK directly (~180 MB)..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $json    = Invoke-RestMethod 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json' -UseBasicParsing
            $hash    = $json.current_release.stable
            $release = $json.releases | Where-Object { $_.hash -eq $hash } | Select-Object -First 1
            $zipUrl  = "https://storage.googleapis.com/flutter_infra_release/releases/$($release.archive)"
            $zip     = "$env:TEMP\flutter_stable.zip"

            Write-Host "    Version : $($release.version)" -ForegroundColor Gray
            Write-Host "    Downloading (please wait)..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing

            Write-Host "    Extracting to C:\flutter..." -ForegroundColor Yellow
            if (Test-Path 'C:\flutter') { Remove-Item 'C:\flutter' -Recurse -Force }
            Expand-Archive -Path $zip -DestinationPath 'C:\' -Force
            Remove-Item $zip -Force

            $uPath = [Environment]::GetEnvironmentVariable('PATH','User')
            if ($uPath -notlike '*C:\flutter\bin*') {
                [Environment]::SetEnvironmentVariable('PATH', "$uPath;C:\flutter\bin", 'User')
            }
            $env:PATH += ';C:\flutter\bin'
            OK "Flutter installed at C:\flutter"
        } catch {
            Fail "Could not install Flutter. Please go to flutter.dev and install it manually, then re-run this script."
        }
    }
}

# ── STEP 2: Check / Install Android SDK ──────────────────────────────────────
Step "Checking Android SDK..."

$sdkPaths = @(
    "$env:LOCALAPPDATA\Android\Sdk",
    "$env:USERPROFILE\AppData\Local\Android\Sdk",
    "C:\Android\Sdk"
)
$sdkFound = $false
foreach ($p in $sdkPaths) {
    if (Test-Path $p) { OK "Android SDK found at $p" ; $sdkFound = $true ; break }
}

if (-not $sdkFound) {
    Warn "Android SDK not found."

    $hasWinget = $false
    try { $null = winget --version 2>&1 ; $hasWinget = $true } catch {}

    if ($hasWinget) {
        Write-Host ""
        Write-Host "    Installing Android Studio (~1 GB, takes several minutes)..." -ForegroundColor Yellow
        winget install Google.AndroidStudio --accept-package-agreements --accept-source-agreements
        Write-Host ""
        Write-Host "  IMPORTANT: Android Studio just installed." -ForegroundColor Yellow
        Write-Host "  You must now:" -ForegroundColor Yellow
        Write-Host "    1. Open Android Studio from the Start Menu" -ForegroundColor White
        Write-Host "    2. Click through the Setup Wizard (Next > Next > Finish)" -ForegroundColor White
        Write-Host "    3. Wait for SDK components to download" -ForegroundColor White
        Write-Host "    4. Close Android Studio" -ForegroundColor White
        Write-Host "    5. Come back here and press Enter" -ForegroundColor White
        Read-Host "`n  Press Enter once Android Studio setup is done"
    } else {
        Write-Host ""
        Write-Host "  winget not available. Please install Android Studio manually:" -ForegroundColor Yellow
        Write-Host "    1. Go to  https://developer.android.com/studio" -ForegroundColor White
        Write-Host "    2. Download and install it" -ForegroundColor White
        Write-Host "    3. Run the setup wizard fully" -ForegroundColor White
        Write-Host "    4. Close Android Studio" -ForegroundColor White
        Write-Host "    5. Re-run this script" -ForegroundColor White
        Read-Host "`n  Press Enter to exit"
        exit 1
    }
}

# ── STEP 3: Accept Android licenses ──────────────────────────────────────────
Step "Accepting Android SDK licenses..."
try {
    $yesInput = ("y`n" * 15)
    $yesFile  = "$env:TEMP\flutter_yes.txt"
    $yesInput | Out-File $yesFile -Encoding ascii
    Get-Content $yesFile | flutter doctor --android-licenses 2>&1 | Out-Null
    Remove-Item $yesFile -Force
    OK "Licenses accepted"
} catch {
    Warn "Could not auto-accept licenses -- you may need to run 'flutter doctor --android-licenses' manually"
}

# ── STEP 4: flutter doctor ────────────────────────────────────────────────────
Step "Running flutter doctor (status check)..."
flutter doctor

# ── STEP 5: Build APK ────────────────────────────────────────────────────────
Step "Getting Flutter packages..."
Set-Location (Join-Path $scriptDir "client")

flutter pub get
if ($LASTEXITCODE -ne 0) { Fail "flutter pub get failed. Check the errors above." }

Step "Building APK (2-5 minutes first time -- please wait)..."
flutter build apk --release
if ($LASTEXITCODE -ne 0) { Fail "Build failed. Run 'flutter doctor' for details." }

$apk = Join-Path $scriptDir "client\build\app\outputs\flutter-apk\app-release.apk"

Write-Host ""
Write-Host "  =====================================================" -ForegroundColor Green
Write-Host "   APK built successfully!" -ForegroundColor White
Write-Host "  =====================================================" -ForegroundColor Green
Write-Host "  File: $apk" -ForegroundColor Gray
Write-Host ""

# ── STEP 6: Install on phone ──────────────────────────────────────────────────
Write-Host "  Before installing, do this on your OPPO:" -ForegroundColor Yellow
Write-Host "    1. Settings > About Phone > tap Build Number 7 times" -ForegroundColor White
Write-Host "    2. Settings > Developer Options > USB Debugging = ON" -ForegroundColor White
Write-Host "    3. Plug phone into PC via USB and tap 'Allow' on the phone" -ForegroundColor White
Write-Host ""

$ans = Read-Host "  Install app on phone now? (y/n)"
if ($ans -ieq 'y') {
    Step "Installing on phone via USB..."
    flutter install
    if ($LASTEXITCODE -eq 0) {
        OK "App installed on your phone!"
    } else {
        Warn "USB install failed. Copy this file to your phone and open it:"
        Write-Host "  $apk" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "  =====================================================" -ForegroundColor Green
Write-Host "   ALL DONE!" -ForegroundColor White
Write-Host "  =====================================================" -ForegroundColor Green
Write-Host "  1. Run  run_server.bat  on your PC" -ForegroundColor White
Write-Host "  2. Open the Controller app on your phone" -ForegroundColor White
Write-Host "  3. Tap the top bar > Scan QR code" -ForegroundColor White
Write-Host "  4. Green dot = connected, play any game!" -ForegroundColor White
Write-Host ""

Read-Host "Press Enter to exit"
