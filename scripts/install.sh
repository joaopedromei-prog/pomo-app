#!/usr/bin/env bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_NAME="Pomo"
APP_BUNDLE="$APP_NAME.app"
BUNDLE_ID="com.pomo.app"
INSTALL_DIR="/Applications"

echo "==> Building $APP_NAME..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

EXECUTABLE="$BUILD_DIR/$APP_NAME"
if [ ! -f "$EXECUTABLE" ]; then
    echo "ERROR: Build output not found at $EXECUTABLE"
    exit 1
fi

echo "==> Generating app icon..."
swift "$PROJECT_DIR/scripts/generate_icon.swift" "$PROJECT_DIR/scripts"

echo "==> Creating .app bundle..."
BUNDLE_DIR="/tmp/$APP_BUNDLE"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp "$EXECUTABLE" "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$BUNDLE_DIR/Contents/MacOS/$APP_NAME"

if [ -f "$PROJECT_DIR/scripts/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/scripts/AppIcon.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
    ICON_LINE="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
    ICON_LINE=""
fi

cat > "$BUNDLE_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
    <key>NSUserNotificationsUsageDescription</key>
    <string>Pomo notifica você quando suas sessões de foco e descanso terminam.</string>
    $ICON_LINE
</dict>
</plist>
EOF

echo "==> Installing to $INSTALL_DIR..."
rm -rf "$INSTALL_DIR/$APP_BUNDLE"
cp -R "$BUNDLE_DIR" "$INSTALL_DIR/"

echo ""
echo "✓ Pomo.app instalado em $INSTALL_DIR"
echo ""
echo "Primeira abertura:"
echo "  → Clique direito em Pomo.app → 'Abrir' → 'Abrir mesmo assim'"
echo "     (necessário pois o app não está assinado)"
echo ""
echo "Ou via Terminal:"
echo "  xattr -rd com.apple.quarantine \"$INSTALL_DIR/$APP_BUNDLE\" && open \"$INSTALL_DIR/$APP_BUNDLE\""
