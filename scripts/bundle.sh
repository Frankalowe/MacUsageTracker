#!/bin/bash
set -e

CONFIG=${1:-release}
APP_NAME="MacUsageTracker"
APP_BUNDLE="MacUsageTracker.app"

echo "🔨 Building ${APP_NAME} (${CONFIG})..."
swift build -c "${CONFIG}"

echo "📦 Creating macOS App Bundle..."
rm -rf "${APP_BUNDLE}" PomodoroTimetable.app
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

BIN_PATH=$(swift build -c "${CONFIG}" --show-bin-path)/${APP_NAME}
cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

cat << 'EOF' > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MacUsageTracker</string>
    <key>CFBundleIdentifier</key>
    <string>com.antigravity.MacUsageTracker</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Mac Usage Tracker</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Mac Usage Tracker uses Apple Events to detect the active website domain in your browser for screen time analytics.</string>
</dict>
</plist>
EOF

echo "✅ App bundle created at ${APP_BUNDLE}"
