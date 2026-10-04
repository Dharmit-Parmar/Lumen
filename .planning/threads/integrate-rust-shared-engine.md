---
slug: integrate-rust-shared-engine
title: Integrate Rust shared engine
status: open
created: 2026-10-04T18:05:32Z
updated: 2026-10-04T18:05:32Z
---

# Thread: Integrate Rust shared engine

## Goal

Integrate Rust as a shared core engine between the Android app and the macOS app, replacing the TCP connection logic and frame packing.

## Context

*Created 2026-10-04.*
The user explicitly asked to start using Rust as the engine "in between" now, rather than waiting for post-MVP. The engine will handle packing/unpacking the 12-byte configuration header and raw NAL unit video messages, as well as socket communication.

## References

- `.planning/PROJECT.md`
- `STREAM_PROTOCOL.md`

## Next Steps

- Create a `Cargo.toml` at the root or in a `core/` directory.
- Define FFI boundaries for Android (JNI) and macOS (C-API).
- Re-implement TCP Server and Client logic in Rust.
- Connect Android `MainActivity`/`CameraStreamService` to Rust via JNI.
- Connect Swift `H264StreamReceiver` to Rust via bridging header.
