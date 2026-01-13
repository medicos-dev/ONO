# PowerShell script to setup Android app icons
# This script copies the app logo to Android icon directories

$logoPath = "assets/ONO APP LOGO.png"

if (Test-Path $logoPath) {
    Write-Host "Found logo at $logoPath"
    Write-Host "Please use flutter_launcher_icons package or manually copy the logo to:"
    Write-Host "  - android/app/src/main/res/mipmap-mdpi/ic_launcher.png"
    Write-Host "  - android/app/src/main/res/mipmap-hdpi/ic_launcher.png"
    Write-Host "  - android/app/src/main/res/mipmap-xhdpi/ic_launcher.png"
    Write-Host "  - android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png"
    Write-Host "  - android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"
    Write-Host ""
    Write-Host "You can use flutter_launcher_icons package:"
    Write-Host "  1. Add flutter_launcher_icons to dev_dependencies in pubspec.yaml"
    Write-Host "  2. Configure flutter_launcher_icons in pubspec.yaml"
    Write-Host "  3. Run: flutter pub run flutter_launcher_icons:main"
} else {
    Write-Host "Logo not found at $logoPath"
}

Write-Host ""
Write-Host "App name has been set to 'ONO' in AndroidManifest.xml"
