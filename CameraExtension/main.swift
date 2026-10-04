import Foundation
import CoreMediaIO
import os.log

let log = OSLog(subsystem: "com.example.Lumen.CameraExtension", category: "main")
os_log(.debug, log: log, "Starting Lumen Camera Extension")

let providerSource = ExtensionProviderSource()
CMIOExtensionProvider.startService(provider: providerSource.provider)
CFRunLoopRun()
