# Roadmap

## 🎯 Milestone 1: Improved MVP

### Phase 0: Setup
**Goal:** Install Xcode, Android Studio, adb, and setup phone debugging.
**Status:** Partial — Android Studio and adb are installed; the OnePlus CPH2569 is connected and was used for device checks. Xcode is absent (the active developer directory is Command Line Tools).

### Phase 0.5: Viability check
**Goal:** Verify if Camera Extension can be signed and deployed on Mac.
**Status:** Pending — no valid local code-signing identities were found; deployment cannot proceed without Xcode and a signing setup.

### Phase 1: Mac Camera Extension with test picture
**Goal:** Verify live phone frames through the Mac camera extension.
**Status:** Host app and extension compile/link with `swiftc`; the full extension source set type-checks. System extension deployment and Photo Booth/QuickTime verification are pending.

### Phase 2: Android camera app
**Goal:** Create an Android app that can select lenses and show preview.
**Status:** Implemented — native Camera2 preview and camera picker with focal-length labels when available; rear and front camera preview/options were verified on the connected OnePlus CPH2569.

### Phase 3: Encode and serve
**Goal:** Encode H.264 and serve over TCP socket on Android.
**Status:** Implemented and device-checked — the Swift inspector confirmed 720p30 H.264 config, key/delta frames, and reconnect after disconnect. Android's camera foreground service stayed active after Home and stopped when the user tapped Stop. A bounded two-frame sender drops dependent frames only until a requested IDR after backpressure.

### Phase 4: Mac receive, decode, display
**Goal:** Connect Mac extension to Android server, decode video, and output frames.
**Status:** Implemented in Swift — the extension connects on stream start, decodes with VideoToolbox, applies orientation/mirroring, and outputs phone frames as NV12. Runtime camera delivery is pending Xcode installation and device validation.

### Phase 5: Orientation, latency, WhatsApp
**Goal:** Apply rotation, tune latency, and test on WhatsApp.
**Status:** Partial — orientation/mirroring, low-latency decoder/encoder settings, and sampled stage timing logs are implemented. End-to-end latency measurement and Photo Booth, QuickTime, and WhatsApp checks are pending.

### Phase 6: Robustness
**Goal:** Handle disconnects, app restarts, screen locks gracefully.
**Status:** Partial — Android background capture, foreground service, client disconnect cleanup, and reconnect were checked on-device. Screen-lock behavior, process-death recovery, and Mac reconnect backoff runtime remain.

### Phase 7: Measure and polish
**Goal:** Measure latency precisely and write setup README.
**Status:** Partial — stage timing logs are in place, but no end-to-end latency measurement has been taken.
