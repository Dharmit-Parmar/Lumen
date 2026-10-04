# Android Phone as Mac Webcam: Improved MVP Plan

USB, offline, Android to Mac. Revised after review.

## 1. Goal

Plug in an Android phone with a USB cable, pick a phone camera (front or any rear lens), and see it as a camera in Photo Booth, QuickTime, WhatsApp (desktop and web) on the Mac.

**Latency target:** under 100 ms is a stretch goal. Realistic result is 100-200 ms. Build a measurement method early (see Phase 7) and judge by that.

## 2. Architecture

```
Phone camera -> H.264 encoder -> TCP server on phone (port 5000)
   -> USB cable (adb forward) ->
Mac Camera Extension -> TCP client -> VideoToolbox decoder -> virtual camera -> apps
```

- **Android app (Kotlin):** Camera2 capture, MediaCodec H.264 encoder, foreground service (camera type), TCP server.
- **Mac host app (Swift):** installs the Camera Extension, lives in /Applications.
- **Mac Camera Extension (Swift):** connects to localhost:5000 only while an app is using the camera, decodes, outputs frames.
- **Cable link:** `adb forward tcp:5000 tcp:5000` from Terminal for now.
- **Fallback design:** if the sandboxed extension cannot reach the socket, the host app owns the connection and decoding and passes frames to the extension through a sink stream.

## 3. Stream format (v1, independent of USB)

Every message:

| Field | Size | Notes |
| --- | --- | --- |
| Magic | 2 bytes | fixed value, detects desync |
| Version | 1 byte | start at 1 |
| Length | 4 bytes | payload length only (header excluded), big-endian |
| Type | 1 byte | 1 = config, 2 = keyframe, 3 = delta frame |
| Timestamp | 8 bytes | capture time in microseconds |
| Payload | variable | see below |

**Config payload:** codec id, width, height, fps, rotation (0/90/180/270), mirror flag, then SPS/PPS bytes.

Use Annex-B or AVCC consistently on both sides and write down which one in the spec. Decide this before Phase 3.

## 4. Behavior rules

1. **New connection handshake:** on every new client, the phone sends config first, then forces a keyframe (`PARAMETER_KEY_REQUEST_SYNC_FRAME`). Never send config only once per app run.
2. **Connect on demand:** the extension opens the connection in `startStream` and closes it in `stopStream`. The phone starts its camera only when a Mac is connected, and stops when the client leaves.
3. **adb forward quirk:** the Mac side can connect even when the phone is not listening. Treat "connected but no config within about 1 second" as a failed attempt, close, and retry with backoff.
4. **Frame dropping, done safely:**
   - Mac: decode every frame, but only display the newest decoded frame.
   - Phone: if the socket is backed up, drop frames until the next keyframe and request one early. Never drop a single P-frame.
5. **No-signal placeholder:** when there is no video, output a "No phone connected" frame so apps never see a frozen or black camera.
6. **Orientation:** rotation and mirror come from the config message. MediaCodec's input surface does not rotate for you. Rotate on the Mac, or lock the phone to landscape for the MVP.

## 5. Latency settings (from day one)

**Encoder (Android):**

- Baseline profile, no B-frames (`KEY_MAX_B_FRAMES = 0`, API 29+)
- `KEY_LOW_LATENCY = 1` (API 30+), `KEY_PRIORITY = 0`
- Constant bitrate, keyframe interval 1-2 seconds

**Socket:** `TCP_NODELAY` on, small send and receive buffers.

**Decoder (Mac):** real-time mode, no frame reordering, output NV12 and match that pixel format in the extension stream to avoid a color conversion.

**Queues:** keep queue depth at 1-2 frames. Always present the newest.

**Start at:** 1280x720, 30 fps, 4-6 Mbps.

## 6. Risks to check early

1. **Code signing (biggest risk):** a free Apple ID probably cannot use the System Extension capability. Check this before writing any Android code. A paid developer account solves it. `systemextensionsctl developer on` helps local development but has its own requirements.
2. **Sandbox:** the extension needs `com.apple.security.network.client` to reach localhost. It cannot launch `adb`.
3. **WhatsApp:** apps differ in how they treat virtual cameras. Test the desktop app and WhatsApp Web in Chrome or Safari.
4. **Rear lens choice:** only some phones expose ultrawide or telephoto lenses to apps. Test on your own phone in Phase 2.
5. **Android 14+:** the service needs `foregroundServiceType="camera"` and the `FOREGROUND_SERVICE_CAMERA` permission. Camera access cannot start from the background, so start from a visible app.
6. **Install location:** the Mac app must be in /Applications to install the extension.

## 7. Not in the MVP

- Wireless connection
- Phone camera plus MacBook camera together (picture-in-picture)
- Audio, filters, effects
- Zoom, focus, exposure controls
- Auto-start when the phone is plugged in
- Shared Rust or C++ core

## 8. Ready for wireless later

- Transport stays a separate layer, so Wi-Fi swaps in without touching video code.
- Wi-Fi will likely need UDP or QUIC instead of TCP.
- Add encrypted pairing (QR code between phone and Mac) at that point.
- Use Bonjour/mDNS to discover the phone.

## 9. Optional shortcut: scrcpy

scrcpy 2.2+ can already stream an Android camera over adb with H.264, lens selection (`--list-cameras`, `--camera-id`) and low latency on Android 12+. If your goal is a working webcam fast, you can skip Phases 2-3 and write only the Mac side against scrcpy's framing. If your goal is learning Camera2 and MediaCodec, build the Android app yourself.

## 10. Build steps

### Phase 0: Setup

1. Install Xcode, Android Studio, and platform-tools (adb).
2. On the phone: enable Developer options, then USB debugging.
3. Plug in, accept the RSA prompt.
4. Check the Mac macOS version and your Apple Developer account status.

**Done when:** `adb devices` lists your phone as `device`.

### Phase 0.5: Viability check (do this before Android work)

1. Create a new Xcode macOS app project with a Camera Extension target (use Xcode's template).
2. Try to build and sign it with your Apple ID.
3. If System Extension signing fails, decide: join the paid developer program, or use the developer-mode route, or stop here.
4. Note the exact errors and your macOS version.

**Done when:** you know for certain whether the extension route works on your setup.

### Phase 1: Mac Camera Extension with test picture

1. Move the built host app to /Applications and run it.
2. Click install, approve in System Settings, Privacy and Security.
3. Open Photo Booth and pick your virtual camera.
4. Replace the template pattern with your own "No phone connected" frame.

**Done when:** the placeholder frame shows in Photo Booth and QuickTime.

### Phase 2: Android camera app

1. Create a Kotlin app, request the camera permission.
2. Enumerate cameras with `CameraManager`, including logical and physical IDs.
3. Show a preview with Camera2, add a camera picker (front, rear main, ultrawide, tele where exposed).
4. Log which lenses your phone exposes.

**Done when:** you can switch lenses on the phone preview.

### Phase 3: Encode and serve

1. Configure MediaCodec H.264 with the Section 5 settings, using an input Surface.
2. Add a camera foreground service with the camera type and notification.
3. Write the TCP server on port 5000 using the Section 3 framing.
4. Implement the handshake: config, then forced keyframe, on each new client.
5. Start the camera only when a client connects, stop when it leaves.
6. Write a small Python script on the Mac that connects via `adb forward`, parses messages, and prints type, size, timestamp. Optionally dump to a file and play with ffplay.

**Done when:** the Mac script receives config and a steady stream of frames, and reconnecting works.

### Phase 4: Mac receive, decode, display

1. In the extension, open the socket in `startStream`, close in `stopStream`.
2. Parse messages, build a `CMVideoFormatDescription` from SPS/PPS.
3. Decode with VideoToolbox in real-time mode, output NV12.
4. Keep only the newest decoded frame and send it to the stream with proper timing.
5. Show the placeholder when there is no connection or no config within about 1 second.
6. Add the network client entitlement. If localhost is blocked, switch to the host-app-owned connection design.

**Done when:** phone video appears in Photo Booth.

### Phase 5: Orientation, latency, WhatsApp

1. Apply rotation and mirror from the config message.
2. Add timing logs at each stage (capture, encode, receive, decode, display).
3. Tune bitrate, resolution, queue depth.
4. Test WhatsApp desktop and WhatsApp Web. Test QuickTime too.

**Done when:** a WhatsApp call works with the phone camera, upright and not unexpectedly mirrored.

### Phase 6: Robustness

1. Unplug and replug the cable while streaming. No crash, placeholder shown, auto reconnect.
2. Start and stop the camera in apps repeatedly.
3. Kill and restart the Android app. Restart adb. Both should recover.
4. Handle phone screen lock, camera taken by another app, and permission denied.
5. Add retry with backoff and clear logging on both sides.

**Done when:** you can reconnect without restarting the Mac app.

### Phase 7: Measure and polish

1. Measure end to end latency: show a stopwatch on a screen, film both the screen and the Mac preview with another phone, compare. Or embed a burned-in timestamp.
2. Record results per resolution and bitrate.
3. Write a short README: setup, adb command, known issues.
4. Pick the first post-MVP feature (auto-start, or a menu bar status item).

**Done when:** you have a measured latency number and a repeatable setup guide.

## 11. Suggested order of work

1. Phase 0 and 0.5 first, in one sitting. These decide whether the project is viable.
2. Phase 1 next, since it proves the Mac side end to end.
3. Phases 2-3 together (Android side), then test with the Python script.
4. Phase 4 to connect both sides.
5. Phases 5-7 for quality and reliability.
