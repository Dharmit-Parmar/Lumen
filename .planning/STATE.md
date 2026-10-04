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
- Both the host app and camera extension compile and link with the installed SDK using `swiftc`.
- Deployment in Photo Booth and QuickTime is not yet verified. macOS is 27.0.1; Android Studio and adb are installed; `adb devices -l` lists no attached phone. Xcode is absent and `xcode-select` points to Command Line Tools. Apple signing eligibility remains unverified.
- Phase 0.5 checks found zero valid local code-signing identities. `systemextensionsctl developer` cannot report developer mode while SIP is enabled; no security settings were changed.

### Stream Protocol / Phase 3 Preparation
- Chose Annex-B for H.264 access units and specified exact message/config byte layouts, limits, timestamps, and handshake behavior in `STREAM_PROTOCOL.md`.
- Added `tools/inspect_stream.py` to parse a forwarded v1 stream and print config/frame metadata. It is ready for use after Android serving and `adb forward` are available.
