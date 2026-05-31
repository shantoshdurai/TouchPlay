@echo off
set SDK=%LOCALAPPDATA%\Android\Sdk
set SDKMANAGER=%SDK%\cmdline-tools\latest\bin\sdkmanager.bat
(echo y & echo y & echo y & echo y & echo y & echo y & echo y & echo y & echo y & echo y) | "%SDKMANAGER%" --licenses --sdk_root="%SDK%"
