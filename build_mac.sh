#!/bin/bash
set -e

echo "Building Lumen Virtual Camera for macOS..."

rm -rf build_mac
mkdir -p build_mac
cd build_mac

# 1. Compile Extension Binary
echo "Compiling Extension..."
swiftc ../CameraExtension/main.swift \
       ../CameraExtension/ExtensionProviderSource.swift \
       ../CameraExtension/ExtensionDeviceSource.swift \
       ../CameraExtension/ExtensionStreamSource.swift \
       ../CameraExtension/H264StreamReceiver.swift \
       -o lumen_extension \
       -framework CoreMediaIO \
       -framework CoreMedia \
       -framework CoreVideo \
       -framework VideoToolbox \
       -framework Foundation

# 2. Compile Host App Binary
echo "Compiling Host App..."
swiftc ../MacApp/AppDelegate.swift \
       ../CameraExtension/H264StreamReceiver.swift \
       -o Lumen \
       -framework Cocoa \
       -framework CoreMedia \
       -framework CoreVideo \
       -framework VideoToolbox \
       -framework SystemExtensions

# 3. Create Extension Bundle
echo "Bundling Extension..."
mkdir -p com.example.lumen.extension.appex/Contents/MacOS
cp lumen_extension com.example.lumen.extension.appex/Contents/MacOS/com.example.lumen.extension

cat << 'EOF' > com.example.lumen.extension.appex/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>com.example.lumen.extension</string>
	<key>CFBundleIdentifier</key>
	<string>com.example.lumen.extension</string>
	<key>CFBundleName</key>
	<string>LumenCameraExtension</string>
	<key>CFBundlePackageType</key>
	<string>XPC!</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>12.3</string>
	<key>NSSystemExtensionUsageDescription</key>
	<string>Lumen provides a virtual camera for Mac apps.</string>
    <key>CMIOExtension</key>
    <dict>
        <key>CMIOExtensionMachServiceName</key>
        <string>com.example.lumen.extension</string>
    </dict>
</dict>
</plist>
EOF

# 4. Create Host App Bundle
echo "Bundling Host App..."
mkdir -p Lumen.app/Contents/MacOS
mkdir -p Lumen.app/Contents/Library/SystemExtensions
cp Lumen Lumen.app/Contents/MacOS/Lumen
mv com.example.lumen.extension.appex Lumen.app/Contents/Library/SystemExtensions/

cat << 'EOF' > Lumen.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>Lumen</string>
	<key>CFBundleIdentifier</key>
	<string>com.example.lumen</string>
	<key>CFBundleName</key>
	<string>Lumen</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>12.3</string>
</dict>
</plist>
EOF

# 5. Sign with ad-hoc signing
echo "Codesigning..."
codesign --force --sign - --entitlements ../CameraExtension/LumenCameraExtension.entitlements --timestamp=none Lumen.app/Contents/Library/SystemExtensions/com.example.lumen.extension.appex
codesign --force --sign - --entitlements ../MacApp/Lumen.entitlements --timestamp=none Lumen.app

echo "Done! The app bundle is at build_mac/Lumen.app"
