@echo off
REM Script to setup Android app icon and name for ONO

echo Setting up Android app icon and name...

REM Check if logo exists
if not exist "assets\ONO APP LOGO.png" (
    echo Error: Logo not found at assets\ONO APP LOGO.png
    pause
    exit /b 1
)

echo.
echo Installing flutter_launcher_icons package...
flutter pub add dev:flutter_launcher_icons

echo.
echo Generating app icons...
flutter pub run flutter_launcher_icons:main

echo.
echo App name has been set to 'ONO' in AndroidManifest.xml
echo.
echo Setup complete!
echo.
echo You can now build and run the app:
echo   flutter run
echo.

pause
