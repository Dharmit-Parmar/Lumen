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
| **Phase 1** | Mac Camera Extension | Prove the Mac side end-to-end with a placeholder "No phone connected" frame. |
| **Phase 2** | Android camera app | Create the Android Kotlin app capable of showing a preview and selecting lenses. |
| **Phase 3** | Encode and serve | Encode H.264 stream and serve over a TCP socket. |
| **Phase 4** | Mac receive & decode | Connect the Mac extension to the Android server, decode the stream, and expose frames. |
| **Phase 5** | Polish (Latency & UI) | Apply rotation, tune latency down to 100-200ms, and verify in apps like WhatsApp. |
| **Phase 6** | Robustness | Handle disconnects, screen locks, and app restarts gracefully. |
| **Phase 7** | Measure | Benchmark end-to-end latency and finalize setup docs. |

## 🚀 Readiness Status
1. **`.planning/PROJECT.md`** - Created (Project architecture & context).
2. **`.planning/ROADMAP.md`** - Created (All 8 phases populated).
3. **`.planning/STATE.md`** - Created (Project initialized).
4. **`PLAN.md` files** - Created detailed action steps for Phase 0, Phase 0.5, and Phase 1.

The workspace is fully initialized for execution! We can begin with Phase 0 whenever you are ready.
