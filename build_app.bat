@echo off
title FH6 Controller - Build Phone App

echo.
echo  ==========================================
echo   FH6 Controller - Build ^& Install App
echo  ==========================================
echo.

:: Check Flutter
flutter --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Flutter not found.
    echo.
    echo  Install Flutter from: https://docs.flutter.dev/get-started/install/windows
    echo  Then re-run this file.
    pause
    exit /b 1
)

echo [OK] Flutter found
echo.

cd /d "%~dp0client"

echo [*] Getting packages...
flutter pub get
if errorlevel 1 (
    echo [ERROR] flutter pub get failed.
    pause
    exit /b 1
)

echo.
echo [*] Building APK...
flutter build apk --release
if errorlevel 1 (
    echo [ERROR] Build failed.
    pause
    exit /b 1
)

echo.
echo  ==========================================
echo   APK built successfully!
echo  ==========================================
echo.
echo  APK location:
echo  %~dp0client\build\app\outputs\flutter-apk\app-release.apk
echo.
echo  OPTIONS to install on phone:
echo.
echo  Option A - USB install (phone must be plugged in + USB Debugging ON):
echo    flutter install
echo.
echo  Option B - Copy the APK file to your phone manually and open it.
echo.

set /p choice="Install via USB now? (y/n): "
if /i "%choice%"=="y" (
    echo.
    echo [*] Installing on phone via USB...
    flutter install
)

echo.
echo Done! Open the app on your phone and scan the QR code shown in the server window.
pause
