# Android Phone as Mac Webcam

## Core Purpose
Plug in an Android phone with a USB cable, pick a phone camera (front or any rear lens), and see it as a camera in Photo Booth, QuickTime, WhatsApp (desktop and web) on the Mac.

## Architecture
Phone camera -> H.264 encoder -> TCP server on phone (port 5000)
   -> USB cable (adb forward) ->
Mac Camera Extension -> TCP client -> VideoToolbox decoder -> virtual camera -> apps

## Latency Target
Under 100 ms is a stretch goal. Realistic result is 100-200 ms.

## Post-MVP Architecture: Shared Rust Engine
Rust will be introduced *after* the MVP as an optional shared engine to handle logic that does not depend on the OS layer.

**What goes in Rust:**
1. Message format (packing/unpacking video frames)
2. Connection handling (USB/Wi-Fi)
3. Encryption and pairing (QR-code pairing)
4. Frame queue logic (dropping late frames)
5. Reconnect logic
6. Device discovery (Wi-Fi)

**What stays in Kotlin/Swift:**
- Camera capture / Virtual camera APIs
- H.264 encode/decode
- UI/Screens

**Why Rust:**
- Security at network boundaries.
- Write once, use twice (guarantees format agreement).
- Low latency.

*Note: For the MVP, this logic remains in Kotlin and Swift. We will build this "post office" when we add wireless support.*
