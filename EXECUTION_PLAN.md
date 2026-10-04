# Execution Plan: Android Phone as Mac Webcam

I have parsed the provided project idea and transformed it into a structured **GSD Roadmap**. The project architecture, phases, and specific goals have been formalized into the `.planning` workspace.

## 🏗️ Project Architecture
- **Phone:** Android app (Kotlin) captures video via Camera2, encodes H.264 (MediaCodec), and hosts a TCP server on port `5000`.
- **Bridge:** USB Cable via `adb forward tcp:5000 tcp:5000`.
- **Mac:** Swift Host App (installed in `/Applications`) bundles a System Camera Extension. The extension acts as a TCP client, decodes frames via `VideoToolbox`, and exposes the virtual camera to macOS.

## 🗺️ Roadmap & Phases

### 🚦 Milestone 1: Improved MVP

| Phase | Description | Goal |
|-------|-------------|------|
| **Phase 0** | Setup | Setup dev environment (Xcode, Android Studio, ADB) and verify phone debugging. |
| **Phase 0.5** | Viability check | Create a dummy Mac extension, check Apple ID signing constraints, and verify deployment via `systemextensionsctl`. |
| **Phase 1** | Mac Camera Extension | Verify live phone frames through the installed Mac camera extension. |
| **Phase 2** | Android camera app | Create the Android Kotlin app capable of showing a preview and selecting lenses. |
| **Phase 3** | Encode and serve | Encode H.264 stream and serve over a TCP socket. |
| **Phase 4** | Mac receive & decode | Connect the Mac extension to the Android server, decode the stream, and expose frames. |
| **Phase 5** | Polish (Latency & UI) | Apply rotation, tune latency down to 100-200ms, and verify in apps like WhatsApp. |
| **Phase 6** | Robustness | Handle disconnects, screen locks, and app restarts gracefully. |
| **Phase 7** | Measure | Benchmark end-to-end latency and finalize setup docs. |

## 🚀 Current Readiness

The project has progressed beyond setup. Phase status and outstanding work are tracked in [`.planning/ROADMAP.md`](.planning/ROADMAP.md) and [`.planning/STATE.md`](.planning/STATE.md). Android capture/encoding and the Mac receive/decode path are implemented. Xcode and a signing identity are still required to install the system extension; device checks are also pending while the phone is unavailable.
