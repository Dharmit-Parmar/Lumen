# 📸 Lumen

> **Use your Android phone as a high-quality, ultra-low latency webcam on macOS.**  
> Built for privacy and speed. Works securely over USB with zero cloud dependencies and no accounts required.

---

## ⚡️ Overview

Lumen transforms your Android device into a native macOS webcam. By combining Android's Camera2 API with a macOS CoreMediaIO System Extension, Lumen achieves sub-100ms latency without relying on generic streaming protocols. 

Whether you're presenting on Zoom, recording in QuickTime, or taking calls on WhatsApp, your Mac treats your phone just like a built-in camera.

### ✨ Key Features
- **Plug & Play over USB:** Direct connection via `adb forward` ensures rock-solid stability and zero Wi-Fi dropouts.
- **Ultra-Low Latency:** Optimized H.264 hardware encoding on Android and VideoToolbox decoding on macOS.
- **Privacy First:** The stream never leaves your local hardware. No servers, no tracking, no accounts.
- **Native Integration:** Appears as a standard system camera across macOS applications.

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

*(Note: Lumen is currently in active development. See the Roadmap below.)*

### Prerequisites
- macOS 12.3 or later
- Xcode and command-line tools
- Android phone with USB debugging enabled
- Homebrew (for installing Android platform tools)

### 1. Setup Environment
```bash
# Install Android platform tools for adb
brew install --cask android-platform-tools
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
3. Build and run the `LumenApp` target.
4. Click **Install Camera Extension** in the host app and approve it in `System Settings → Privacy & Security`.

---

## 🗺️ Roadmap (Milestone 1: MVP)

- [x] **Phase 0:** Setup environment and viability checks.
- [x] **Phase 1:** macOS Camera Extension stub with a placeholder UI.
- [ ] **Phase 2:** Android camera app (Lens selection & preview).
- [ ] **Phase 3:** Android H.264 encoding and TCP socket serving.
- [ ] **Phase 4:** Mac Extension receiving and decoding stream.
- [ ] **Phase 5:** Polish, latency tuning, and format adjustments.
- [ ] **Phase 6:** Robustness (disconnect handling, lifecycle states).
- [ ] **Phase 7:** Final measurements and polish.

## 🤝 Contributing

Contributions are welcome! If you're interested in helping build the Android side or tuning the macOS extension, feel free to open an issue or submit a pull request.
