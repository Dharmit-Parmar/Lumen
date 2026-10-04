package com.example.lumen

object LumenEngine {
    init {
        try {
            System.loadLibrary("lumen_core")
        } catch (e: UnsatisfiedLinkError) {
            // Native library not found. Will be ignored for now as NDK setup is pending.
        }
    }

    external fun startServer(port: Int): Boolean
    external fun stopServer()
    external fun sendConfig(width: Int, height: Int, fps: Int, rotation: Int, mirror: Boolean, sps: ByteArray, pps: ByteArray)
    external fun sendFrame(type: Int, timestampUs: Long, payload: ByteArray)
}
