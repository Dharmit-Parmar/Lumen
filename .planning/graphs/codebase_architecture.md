# 🧩 Lumen Codebase Architecture Graph

This document serves as a high-level map of the Lumen codebase. It visually maps how the different components in the repository communicate and interact with one another, designed to help new contributors understand the flow of data from the Android camera all the way to the macOS virtual camera.

## 🏗️ System Component Graph

```mermaid
flowchart TD
    %% Define Styles
    classDef android fill:#3DDC84,stroke:#000,stroke-width:1px,color:black
    classDef macos fill:#000000,stroke:#666,stroke-width:1px,color:white
    classDef protocol fill:#E34F26,stroke:#000,stroke-width:1px,color:white
    classDef tools fill:#F2C94C,stroke:#000,stroke-width:1px,color:black

    subgraph Android App ["📱 Android App (Kotlin)"]
        A1[MainActivity.kt<br/>UI & Camera2 Setup]:::android
        A2[AvcEncoder.kt<br/>Hardware H.264 Encoder]:::android
        A3[TCP Socket Server<br/>Port 5000]:::android
        
        A1 -- "Raw Frames" --> A2
        A2 -- "Encoded NAL Units" --> A3
    end

    subgraph Transport ["🔌 Transport Layer"]
        T1((USB Cable<br/>adb forward tcp:5000)):::protocol
        T2[STREAM_PROTOCOL.md<br/>Custom 12-byte Header + Annex-B]:::protocol
    end

    subgraph MacApp ["💻 macOS Host App (Swift)"]
        M1[AppDelegate.swift<br/>System Extension Installer]:::macos
    end

    subgraph CameraExtension ["🎥 CoreMediaIO Camera Extension (Swift)"]
        E1[main.swift<br/>Extension Entry Point]:::macos
        E2[ExtensionProviderSource.swift<br/>Device Manager]:::macos
        E3[ExtensionDeviceSource.swift<br/>Virtual Camera Device]:::macos
        E4[ExtensionStreamSource.swift<br/>Frame Delivery]:::macos
        E5[H264StreamReceiver.swift<br/>TCP Client & Decoder]:::macos
        
        E1 --> E2
        E2 --> E3
        E3 --> E4
        E4 -- "Starts Receiver" --> E5
        E5 -- "Decodes via VideoToolbox" --> E4
    end

    subgraph Tooling ["🛠️ Developer Tools"]
        D1[inspect_stream.swift<br/>CLI Protocol Inspector]:::tools
    end

    %% Connections
    A3 -.->|Sends Stream| T1
    T1 -.->|Receives Stream| E5
    T2 -.->|Defines| A3
    T2 -.->|Defines| E5
    T1 -.->|Inspects| D1
    
    E4 == "CVPixelBuffer" ==> System[macOS Apps<br/>Photo Booth, Zoom, etc.]
    M1 -.->|Requests Install| E1
```

## 📁 Directory Breakdown

### `android/`
Contains the standard Gradle-based Android project.
- **`MainActivity.kt`**: Handles permissions, camera preview, and starts the capture session using Android's Camera2 API.
- **`AvcEncoder.kt`**: Takes the raw camera frames and hardware-encodes them into H.264 Annex-B format using `MediaCodec`, then serves them over a raw TCP socket.

### `CameraExtension/`
The CoreMediaIO System Extension that acts as the virtual camera driver on macOS.
- **`H264StreamReceiver.swift`**: The TCP client. It connects to the Android phone (via `adb forward`), parses the `STREAM_PROTOCOL.md` headers, extracts the H.264 NAL units, and decodes them natively using `VTDecompressionSession`.
- **`ExtensionStreamSource.swift`**: Receives decoded `CVPixelBuffer` frames from the receiver and pushes them to macOS when available.

### `MacApp/`
The standard macOS `.app` bundle used to install the extension.
- **`AppDelegate.swift`**: Provides the UI and uses `OSSystemExtensionRequest` to ask macOS to install the Camera Extension.

### `STREAM_PROTOCOL.md`
The source of truth for the raw TCP stream format. Defines the 12-byte configuration header and the framing structure for the H.264 video payload.

### `tools/`
- **`inspect_stream.swift`**: A standalone Swift script used to connect to the phone's TCP socket and dump the stream configuration and frame metadata to the terminal, useful for debugging the Android encoder without needing to load the full macOS extension.
