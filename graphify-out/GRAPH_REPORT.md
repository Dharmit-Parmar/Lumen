# Graph Report - Lumen  (2026-10-04)

## Corpus Check
- Corpus is ~11,762 words - fits in a single context window. You may not need a graph.

## Summary
- 208 nodes · 365 edges · 15 communities (13 shown, 2 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 7 edges (avg confidence: 0.88)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Android MainActivity
- Extension Streaming
- Planning & Phases
- Dev Tools & Inspect
- Video Messages
- AvcEncoder / Socket
- macOS Host App
- CoreMediaIO Drivers
- Architecture Docs
- Gradle Wrapper
- Android UI Selectors
- Protocol Config

## God Nodes (most connected - your core abstractions)
1. `MainActivity` - 34 edges
2. `ExtensionStreamSource` - 26 edges
3. `H264StreamReceiver` - 24 edges
4. `ExtensionDeviceSource` - 13 edges
5. `ExtensionProviderSource` - 13 edges
6. `AvcEncoder` - 13 edges
7. `CameraDevice` - 10 edges
8. `InspectorError` - 10 edges
9. `AppDelegate` - 9 edges
10. `CameraCaptureSession` - 7 edges

## Surprising Connections (you probably didn't know these)
- `CoreMediaIO Extension` --semantically_similar_to--> `LumenCameraExtension`  [INFERRED] [semantically similar]
  README.md → project.yml
- `LumenApp` --semantically_similar_to--> `macOS Host App`  [INFERRED] [semantically similar]
  project.yml → .planning/graphs/codebase_architecture.md
- `LumenCameraExtension` --semantically_similar_to--> `Camera Extension`  [INFERRED] [semantically similar]
  project.yml → .planning/graphs/codebase_architecture.md
- `ExtensionStreamSource` --calls--> `H264StreamReceiver`  [INFERRED]
  CameraExtension/ExtensionStreamSource.swift → CameraExtension/H264StreamReceiver.swift
- `ExtensionDeviceSource` --references--> `ExtensionStreamSource`  [EXTRACTED]
  CameraExtension/ExtensionDeviceSource.swift → CameraExtension/ExtensionStreamSource.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Lumen Architecture Flow** — _planning_graphs_codebase_architecture_android_app, _planning_graphs_codebase_architecture_transport_layer, _planning_graphs_codebase_architecture_camera_extension [EXTRACTED 1.00]
- **Lumen Core Components** — readme_h264_encoder, readme_tcp_server, readme_tcp_client, readme_coremediaio_extension [EXTRACTED 1.00]

## Communities (15 total, 2 thin omitted)

### Community 0 - "Android MainActivity"
Cohesion: 0.11
Nodes (16): Activity, Socket, Surface, MainActivity, CameraCaptureSession, CameraDevice, Button, CameraManager (+8 more)

### Community 1 - "Extension Streaming"
Cohesion: 0.15
Nodes (13): H264StreamReceiver, .isRunning, Bool, CMVideoFormatDescription, CVPixelBuffer, Int, Int32, String (+5 more)

### Community 2 - "Planning & Phases"
Cohesion: 0.11
Nodes (16): ExtensionStreamSource, .availableProperties, Bool, CMIOExtensionClient, CMIOExtensionProperty, CMVideoFormatDescription, CVPixelBuffer, Set (+8 more)

### Community 3 - "Dev Tools & Inspect"
Cohesion: 0.11
Nodes (17): ExtensionDeviceSource, .availableProperties, CMIOExtensionProperty, Set, String, ExtensionProviderSource, .availableProperties, CMIOExtensionClient (+9 more)

### Community 4 - "Video Messages"
Cohesion: 0.20
Nodes (17): ArraySlice, CustomStringConvertible, Darwin, Error, annexBNALTypes(), bigEndian(), connect(), inspect() (+9 more)

### Community 5 - "AvcEncoder / Socket"
Cohesion: 0.26
Nodes (8): AvcEncoder, Socket, Surface, MediaCodecInfoCodecs, Bundle, ByteArray, ByteBuffer, DataOutputStream

### Community 6 - "macOS Host App"
Cohesion: 0.14
Nodes (11): Cocoa, AppDelegate, Error, Notification, NSApplicationDelegate, NSObject, NSWindow, OSSystemExtensionProperties (+3 more)

### Community 7 - "CoreMediaIO Drivers"
Cohesion: 0.23
Nodes (7): CoreMedia, CoreMediaIO, CoreText, CoreVideo, Foundation, os.log, VideoToolbox

### Community 8 - "Architecture Docs"
Cohesion: 0.22
Nodes (11): Android App, Camera Extension, macOS Host App, Transport Layer, LumenApp, LumenCameraExtension, CoreMediaIO Extension, H.264 Encoder (+3 more)

### Community 9 - "Gradle Wrapper"
Cohesion: 0.83
Nodes (3): gradlew script, die(), warn()

## Knowledge Gaps
- **15 isolated node(s):** `.availableProperties`, `.availableProperties`, `CoreText`, `.availableProperties`, `CoreMedia` (+10 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ExtensionStreamSource` connect `Planning & Phases` to `Extension Streaming`, `Dev Tools & Inspect`, `macOS Host App`, `CoreMediaIO Drivers`?**
  _High betweenness centrality (0.207) - this node is a cross-community bridge._
- **Why does `H264StreamReceiver` connect `Extension Streaming` to `Planning & Phases`, `CoreMediaIO Drivers`?**
  _High betweenness centrality (0.140) - this node is a cross-community bridge._
- **Why does `Foundation` connect `CoreMediaIO Drivers` to `Video Messages`?**
  _High betweenness centrality (0.108) - this node is a cross-community bridge._
- **What connects `.availableProperties`, `.availableProperties`, `CoreText` to the rest of the system?**
  _15 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Android MainActivity` be split into smaller, more focused modules?**
  _Cohesion score 0.10975609756097561 - nodes in this community are weakly interconnected._
- **Should `Extension Streaming` be split into smaller, more focused modules?**
  _Cohesion score 0.14814814814814814 - nodes in this community are weakly interconnected._
- **Should `Planning & Phases` be split into smaller, more focused modules?**
  _Cohesion score 0.1111111111111111 - nodes in this community are weakly interconnected._