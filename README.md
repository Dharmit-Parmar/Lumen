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
[ TCP Server (5000) ] ===(USB)=== [ TCP Client + VideoToolbox ]
```

*For the MVP, capture, encoding, transport, decoding, and camera output use native Kotlin and Swift APIs.*

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
5. Forward the Mac's local port to the phone's loopback server:
   ```bash
   adb forward tcp:5000 tcp:5000
   ```

### 3. Build & Run
1. Open `Lumen.xcodeproj` in Xcode.
2. Select your Apple Development team for code signing.
3. Build and run the `LumenApp` target. Click **Install Camera Extension** and approve it in `System Settings → Privacy & Security`.
4. Build the Android camera preview with `./gradlew :android:assembleDebug`, then install `android/build/outputs/apk/debug/android-debug.apk` on the phone.

The Android app enumerates logical cameras and exposed physical lenses, shows a Camera2 preview, and labels lenses with focal length when Android exposes it. It serves 720p30 Baseline/CBR H.264 over the USB-forwarded loopback socket. After creating the port forward above, tap **Start USB stream** on the phone, then select **Lumen Camera** in the Mac app. A camera foreground service keeps the server available when the app is backgrounded; video sending uses a two-frame queue and waits for an IDR after backpressure.

---

## 🗺️ Roadmap (Milestone 1: MVP)

- [ ] **Phase 0:** Android Studio and adb are set up; Xcode is not installed. The OnePlus CPH2569 is connected for device checks.
- [ ] **Phase 0.5:** Verify Camera Extension signing and deployment with the selected Apple team.
- [ ] **Phase 1:** Host app and camera extension compile with the installed SDK; installation and Photo Booth/QuickTime verification are pending Xcode and signing setup.
- [x] **Phase 2:** Android Camera2 lens selection, tappable controls, and preview verified on the connected OnePlus CPH2569.
- [x] **Phase 3:** Android 720p30 H.264 encoding, camera foreground service, loopback TCP server, and bounded safe-drop sender verified with `tools/inspect_stream.swift`: valid config, sustained key/delta frames, and client reconnect.
- [ ] **Phase 4:** Mac extension receiver, VideoToolbox decode, orientation/mirror handling, and NV12 output are implemented and type-checked; runtime delivery awaits Xcode and device validation.
- [ ] **Phase 5:** Orientation, low-latency settings, and sampled timing logs are implemented; end-to-end latency measurement and compatibility checks remain.
- [ ] **Phase 6:** Android foreground service stayed active after Home, capture continued, client reconnect worked, and Stop ended the service on-device. Process-death recovery and Mac reconnect backoff runtime still need validation.
- [ ] **Phase 7:** Stage timing logs are in place; the plan's stopwatch-based end-to-end latency measurement and final polish remain.

## 🤝 Contributing

Contributions are welcome! If you're interested in helping build the Android side or tuning the macOS extension, feel free to open an issue or submit a pull request.
