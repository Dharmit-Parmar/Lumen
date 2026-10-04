# Roadmap

## 🎯 Milestone 1: Improved MVP

### Phase 0: Setup
**Goal:** Install Xcode, Android Studio, adb, and setup phone debugging.
**Status:** Partial — Android Studio and adb are installed; no phone is attached, and Xcode is absent

### Phase 0.5: Viability check
**Goal:** Verify if Camera Extension can be signed and deployed on Mac.
**Status:** Pending — Xcode absent and no local code-signing identities are available

### Phase 1: Mac Camera Extension with test picture
**Goal:** Prove the Mac side end-to-end with a placeholder frame.
**Status:** Host app and extension compile/link with the installed SDK; deployment verification pending

### Phase 2: Android camera app
**Goal:** Create an Android app that can select lenses and show preview.
**Status:** Not Started

### Phase 3: Encode and serve
**Goal:** Encode H.264 and serve over TCP socket on Android.
**Status:** Protocol specified and Mac stream inspector added; Android encoder/server not started

### Phase 4: Mac receive, decode, display
**Goal:** Connect Mac extension to Android server, decode video, and output frames.
**Status:** Not Started

### Phase 5: Orientation, latency, WhatsApp
**Goal:** Apply rotation, tune latency, and test on WhatsApp.
**Status:** Not Started

### Phase 6: Robustness
**Goal:** Handle disconnects, app restarts, screen locks gracefully.
**Status:** Not Started

### Phase 7: Measure and polish
**Goal:** Measure latency precisely and write setup README.
**Status:** Not Started
