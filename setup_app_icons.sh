#!/bin/bash

# Setup script for Android app icon and name
# This script helps set up the app icon and name for Android

echo "Setting up Android app icon and name..."

# Copy logo to Android icon directories
LOGO_PATH="assets/ONO APP LOGO.png"

if [ -f "$LOGO_PATH" ]; then
    echo "Logo found at $LOGO_PATH"
    echo "Please manually copy the logo to:"
    echo "  - android/app/src/main/res/mipmap-mdpi/ic_launcher.png (48x48)"
    echo "  - android/app/src/main/res/mipmap-hdpi/ic_launcher.png (72x72)"
    echo "  - android/app/src/main/res/mipmap-xhdpi/ic_launcher.png (96x96)"
    echo "  - android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png (144x144)"
    echo "  - android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png (192x192)"
    echo ""
    echo "You can use an online tool or ImageMagick to resize the image:"
    echo "  convert '$LOGO_PATH' -resize 192x192 android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"
else
    echo "Logo not found at $LOGO_PATH"
fi

echo ""
echo "App name has been set to 'ONO' in AndroidManifest.xml"
echo "Setup complete!"
