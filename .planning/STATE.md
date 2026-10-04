# Project State

## Accumulated Context
### Roadmap Evolution
- Project initialized from Improved MVP Plan markdown file.

### Phase 1 Progress
- The host app provides an explicit extension installation button and reports approval, success, and failure states.
- The host app carries the system-extension installation entitlement and shares an App Group with the sandboxed camera extension. The extension includes its required installation usage description and localhost client entitlement.
- The installer reports when macOS requires a restart to finish activating the extension.
- SDK type-checking against the installed macOS 12.3 SDK caught and fixed invalid CoreMediaIO source initialization, missing stream formats, and invalid device properties.
- Both the host app and camera extension previously compiled and linked with the installed SDK using `swiftc`; the current complete extension source set type-checks with the new receiver.
- Deployment in Photo Booth and QuickTime is not yet verified. macOS is 27.0.1; Android Studio and adb are installed; the OnePlus CPH2569 is connected and has been used for phone-side checks. The Xcode command-line shim is present, but Xcode itself is absent and `xcode-select` points to Command Line Tools. Apple signing eligibility remains unverified.
- Phase 0.5 checks found zero valid local code-signing identities. `systemextensionsctl developer` cannot report developer mode while SIP is enabled; no security settings were changed.

### Phase 2 Progress
- Added a minimal native Kotlin Android app using Camera2, with a live preview and picker for front, rear, external, and exposed physical lenses on API 28+; physical outputs are routed through their logical camera's session and show focal length when API 29+ exposes it. The app logs the available options.
- Fixed a real-device Camera2 disconnect crash and adjusted controls for Android 15 safe areas using dp sizing. Verified the live rear-camera preview and permission on a OnePlus CPH2569.
- The debug APK builds successfully with the repository Gradle wrapper, including the foreground service, bounded sender, and physical-camera selection code.

### Phase 3 Progress
- Added a 720p30 AVC MediaCodec encoder requesting Baseline profile, CBR, low-latency/no-B-frame settings, a loopback TCP server on port 5000, and a camera-type foreground service to keep the server available while the app is backgrounded. It emits protocol-v1 config and Annex-B key/delta messages and requests a keyframe after config.
- The encoder uses a two-frame send queue. If TCP cannot keep up, it drops the queued dependent frames, requests an IDR, and resumes only at that keyframe.
- Installed the current debug APK on OnePlus CPH2569, granted camera permission through the phone prompt, and confirmed the screen exposes tappable camera and Start/Stop controls. Camera options included rear camera 0 (5.6 mm) and front camera 1 (3.2 mm); live preview and capture timing logs worked.
- The Swift inspector received 1280×720 at 30 fps, valid SPS/PPS, keyframes, and monotonic delta-frame timestamps over USB forwarding. Closing the inspector and reconnecting verified Android accepts a new client. After Home, the camera timing logs continued and Android reported CameraStreamService as a foreground camera service. Tapping Stop ended the service.
- Closing an inspector during active streaming produced the expected socket Broken pipe log and stream cleanup; reconnect succeeded. The first reconnect attempt was blocked by the local sandbox, and succeeded when run with device/network access.

### Phase 4 Progress
- Added a Swift H.264 receiver using VideoToolbox and connected decoded phone frames to the CoreMediaIO stream output. The stream waits without emitting frames until a phone frame arrives.
- The complete camera-extension source set type-checks and links against the installed macOS SDK. The receiver enforces a one-second read timeout, applies config rotation/mirroring, asks VideoToolbox for NV12, and keeps only the latest output frame. Building the Xcode project, installing the system extension, and validating the live image in Photo Booth remain pending because Xcode is not installed; the `xcodebuild` shim reports that the active developer directory is Command Line Tools. The unconnected-phone placeholder image was removed after the phone became available for real stream checks.

### Phase 5 Progress
- Added sampled timing logs for Android camera sensor timestamps, encoder output PTS, TCP write duration, Mac frame receive, VideoToolbox output, and CoreMediaIO submission. Phone and Mac clock values are separate; end-to-end latency still needs the visual stopwatch method from the plan.

### Remaining Plan Gaps
- Android camera capture remains activity-owned; the foreground service keeps the app eligible for background capture, but screen-lock/background behavior has not been validated on-device.
- Camera2 open/session callbacks are guarded against stale results after lens changes, pauses, and shutdown; this lifecycle handling is compile-checked but not device-checked.
- Background streaming and protocol reconnect are device-checked. Full camera-service recovery after process death, format negotiation, and Mac virtual-camera delivery remain unchecked.
- Phase 7 end-to-end latency measurement and app compatibility checks have not been done.

### Stream Protocol / Phase 3 Preparation
- Chose Annex-B for H.264 access units and specified exact message/config byte layouts, limits, timestamps, and handshake behavior in `STREAM_PROTOCOL.md`.
- Added the Swift CLI tool `tools/inspect_stream.swift` to parse a forwarded v1 stream and print config/frame metadata. It has verified the Android stream over the restored ADB forward.
