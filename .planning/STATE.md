# Project State

## Accumulated Context
### Roadmap Evolution
- Project initialized from Improved MVP Plan markdown file.

### Phase 1 Progress
- The host app provides an explicit extension installation button and reports approval, success, and failure states.
- The host app carries the system-extension installation entitlement and shares an App Group with the sandboxed camera extension. The extension includes its required installation usage description and localhost client entitlement.
- The camera extension outputs a “No phone connected” placeholder frame while streaming.
- The installer reports when macOS requires a restart to finish activating the extension.
- SDK type-checking against the installed macOS 12.3 SDK caught and fixed invalid CoreMediaIO source initialization, missing stream formats, and invalid device properties.
- Both the host app and camera extension previously compiled and linked with the installed SDK using `swiftc`; the current complete extension source set type-checks with the new receiver.
- Deployment in Photo Booth and QuickTime is not yet verified. macOS is 27.0.1; Android Studio and adb are installed; a OnePlus CPH2569 is attached over USB. The Xcode command-line shim is present, but Xcode itself is absent and `xcode-select` points to Command Line Tools. Apple signing eligibility remains unverified.
- Phase 0.5 checks found zero valid local code-signing identities. `systemextensionsctl developer` cannot report developer mode while SIP is enabled; no security settings were changed.

### Phase 2 Progress
- Added a minimal native Kotlin Android app using Camera2, with a live preview and picker for exposed front, rear, and external camera IDs.
- Fixed a real-device Camera2 disconnect crash and adjusted controls for Android 15 safe areas using dp sizing. Verified the live rear-camera preview and permission on a OnePlus CPH2569.
- The debug APK builds successfully with the repository Gradle wrapper.

### Phase 3 Progress
- Added a 720p30 AVC MediaCodec encoder with low-latency/no-B-frame settings and a loopback TCP server on port 5000. It emits protocol-v1 config and Annex-B key/delta messages and requests a keyframe after config.
- The Swift inspector received config and sustained key/delta frames from the attached phone at 1280×720, 30 fps. The earlier EOF was caused by a lost ADB forward; restoring `adb forward tcp:5000 tcp:5000` resolved it.

### Phase 4 Progress
- Added a Swift H.264 receiver using VideoToolbox and connected decoded BGRA frames to the CoreMediaIO stream output. The placeholder remains visible until phone frames arrive.
- The complete camera-extension source set type-checks against the installed macOS SDK. Building with `xcodebuild`, installing the system extension, and validating the live image in Photo Booth remain pending because Xcode is not installed; the `xcodebuild` shim reports that the active developer directory is Command Line Tools.

### Stream Protocol / Phase 3 Preparation
- Chose Annex-B for H.264 access units and specified exact message/config byte layouts, limits, timestamps, and handshake behavior in `STREAM_PROTOCOL.md`.
- Added the Swift CLI tool `tools/inspect_stream.swift` to parse a forwarded v1 stream and print config/frame metadata. It has verified the Android stream over the restored ADB forward.
