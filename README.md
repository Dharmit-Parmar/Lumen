# 📸 Lumen

> **Use your Android phone as a low-latency webcam on macOS.**
> Built for privacy and speed. Video travels over USB with no cloud service or Lumen user account.

---

## ⚡️ Overview

Lumen transforms your Android device into a native macOS webcam. It combines Android's Camera2 API with a macOS CoreMediaIO System Extension. The latency goal is 100–200 ms; under 100 ms is a stretch goal.

Whether you're presenting on Zoom, recording in QuickTime, or taking calls on WhatsApp, your Mac treats your phone just like a built-in camera.

### ✨ Key Features
- **USB connection:** `adb forward` carries the stream over USB without Wi-Fi.
- **Low Latency:** Optimized H.264 hardware encoding on Android and VideoToolbox decoding on macOS.
- **Privacy First:** The stream stays on your local hardware. No cloud servers, no tracking, no Lumen account.
- **Native Integration:** Designed to appear as a standard camera across macOS applications.

## 🏗️ Architecture

```text
📱 Android Phone                 💻 Mac
[ Camera2 API ]                  [ Host App / Installer ]
       ↓                                 ↓
[ H.264 Encoder ]                [ CoreMediaIO Extension ]
       ↓                                 ↑
[ TCP Server (5000) ] ===(USB)=== [ TCP Client ]
```

*For the MVP, transport logic is embedded in Swift and Kotlin. Future versions will abstract the network layer into a shared Rust engine for secure, encrypted Wi-Fi pairing.*

## 🚀 Getting Started

*(Note: Lumen is currently in active development. Installing the camera extension requires a valid Apple signing setup.)*

### Prerequisites
- macOS 12.3 or later
- Xcode and command-line tools
- Android phone with USB debugging enabled
- Homebrew (for installing Android platform tools)

### 1. Setup Environment
```bash
# Install Android platform tools for adb
brew install android-platform-tools
```

### 2. Connect Your Phone
1. Enable **Developer Options** and **USB Debugging** on your Android device.
2. Connect your phone to your Mac via USB.
3. Accept the RSA fingerprint prompt on your phone.
4. Verify the connection:
   ```bash
   adb devices
   ```

### 3. Build & Run
1. Open `Lumen.xcodeproj` in Xcode.
2. Select your Apple Development team for code signing.
3. Build and run the `LumenApp` target. Click **Install Camera Extension** and approve it in `System Settings → Privacy & Security`.
4. Build the Android camera preview with `./gradlew :android:assembleDebug`, then install `android/build/outputs/apk/debug/android-debug.apk` on the phone.

The Android app enumerates available lenses, shows a Camera2 preview, and can serve 720p30 H.264 over the USB-forwarded loopback socket. Tap **Start USB stream** on the phone after setting up `adb forward tcp:5000 tcp:5000`.

---

## 🗺️ Roadmap (Milestone 1: MVP)

- [ ] **Phase 0:** Set up development tools and verify a connected Android phone.
- [ ] **Phase 0.5:** Verify Camera Extension signing and deployment with the selected Apple team.
- [ ] **Phase 1:** Host app and placeholder extension compile with the installed SDK; installation and Photo Booth/QuickTime verification are pending.
- [ ] **Phase 2:** Android Camera2 lens selection and preview implemented; verified on a OnePlus CPH2569.
- [ ] **Phase 3:** Android 720p30 H.264 encoding and loopback TCP server implemented; live protocol inspection and reconnect verification pending. Swift CLI inspector: `tools/inspect_stream.swift`.
- [ ] **Phase 4:** Mac Extension receiving and decoding stream.
- [ ] **Phase 5:** Polish, latency tuning, and format adjustments.
- [ ] **Phase 6:** Robustness (disconnect handling, lifecycle states).
- [ ] **Phase 7:** Final measurements and polish.

## 🤝 Contributing

Contributions are welcome! If you're interested in helping build the Android side or tuning the macOS extension, feel free to open an issue or submit a pull request.
