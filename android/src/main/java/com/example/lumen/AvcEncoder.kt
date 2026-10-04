package com.example.lumen

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Surface
import java.io.DataOutputStream
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.concurrent.thread

internal class AvcEncoder(
    private val onFailure: (Exception) -> Unit
) {
    private val width = 1280
    private val height = 720
    private val frameRate = 30
    private val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
    val surface: Surface

    @Volatile private var stopped = false
    private var drainThread: Thread? = null

    init {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfoCodecs.COLOR_FORMAT_SURFACE)
            setInteger(MediaFormat.KEY_BIT_RATE, 4_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            if (Build.VERSION.SDK_INT >= 29) setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)
            if (Build.VERSION.SDK_INT >= 30) setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            setInteger(MediaFormat.KEY_PRIORITY, 0)
        }
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        surface = codec.createInputSurface()
        codec.start()
    }

    fun start(socket: Socket, rotation: Int, mirror: Boolean) {
        drainThread = thread(name = "LumenAvcOutput") {
            try {
                drain(socket, rotation, mirror)
            } catch (error: Exception) {
                Log.e("Lumen", "AVC output drain failed", error)
                if (!stopped) onFailure(error)
            }
        }
    }

    private fun drain(socket: Socket, rotation: Int, mirror: Boolean) {
        val output = DataOutputStream(socket.getOutputStream())
        val info = MediaCodec.BufferInfo()
        var sentConfig = false
        var sentKeyframe = false

        while (!stopped) {
            when (val index = codec.dequeueOutputBuffer(info, 100_000)) {
                MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    Log.i("Lumen", "AVC output format available")
                    val format = codec.outputFormat
                    val sps = format.getByteBuffer("csd-0")?.let { findNal(it, 7) }
                    val pps = format.getByteBuffer("csd-1")?.let { findNal(it, 8) }
                    if (sps == null || pps == null) throw IllegalStateException("Encoder did not provide H.264 SPS/PPS")
                    writeConfig(output, sps, pps, rotation, mirror)
                    Log.i("Lumen", "Sent stream config")
                    sentConfig = true
                    if (Build.VERSION.SDK_INT >= 19) {
                        codec.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) })
                    }
                }
                MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                else -> if (index >= 0) {
                    try {
                        val encoded = codec.getOutputBuffer(index)
                        if (sentConfig && encoded != null && info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                            encoded.position(info.offset)
                            encoded.limit(info.offset + info.size)
                            val bytes = ByteArray(info.size)
                            encoded.get(bytes)
                            val keyframe = info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0
                            if (keyframe) sentKeyframe = true
                            if (sentKeyframe) {
                                writeMessage(output, if (keyframe) 2 else 3, info.presentationTimeUs, normalizeAnnexB(bytes))
                            }
                        }
                    } finally {
                        codec.releaseOutputBuffer(index, false)
                    }
                }
            }
        }
    }

    private fun writeConfig(output: DataOutputStream, sps: ByteArray, pps: ByteArray, rotation: Int, mirror: Boolean) {
        require(sps.isNotEmpty() && pps.isNotEmpty() && sps.size <= 65535 && pps.size <= 65535)
        val payload = ByteBuffer.allocate(14 + sps.size + pps.size).order(ByteOrder.BIG_ENDIAN)
        payload.put(1)
            .putShort(width.toShort())
            .putShort(height.toShort())
            .putShort(frameRate.toShort())
            .putShort(rotation.toShort())
            .put(if (mirror) 1 else 0)
            .putShort(sps.size.toShort()).put(sps)
            .putShort(pps.size.toShort()).put(pps)
        writeMessage(output, 1, 0, payload.array())
    }

    private fun writeMessage(output: DataOutputStream, type: Int, timestampUs: Long, payload: ByteArray) {
        val header = ByteBuffer.allocate(16).order(ByteOrder.BIG_ENDIAN)
            .put(0x4c).put(0x55).put(1).putInt(payload.size).put(type.toByte()).putLong(timestampUs)
        output.write(header.array())
        output.write(payload)
        output.flush()
    }

    private fun findNal(buffer: ByteBuffer, type: Int): ByteArray? {
        val data = ByteArray(buffer.remaining())
        buffer.duplicate().get(data)
        return nalUnits(data).firstOrNull { it.isNotEmpty() && (it[0].toInt() and 0x1f) == type }
    }

    private fun normalizeAnnexB(data: ByteArray): ByteArray {
        val units = nalUnits(data)
        if (units.isEmpty()) throw IllegalStateException("Encoder emitted an invalid H.264 access unit")
        val size = units.sumOf { it.size + 4 }
        return ByteBuffer.allocate(size).apply {
            units.forEach { put(byteArrayOf(0, 0, 0, 1)); put(it) }
        }.array()
    }

    private fun nalUnits(data: ByteArray): List<ByteArray> {
        fun startCode(at: Int): Int = when {
            at + 3 < data.size && data[at] == 0.toByte() && data[at + 1] == 0.toByte() && data[at + 2] == 0.toByte() && data[at + 3] == 1.toByte() -> 4
            at + 2 < data.size && data[at] == 0.toByte() && data[at + 1] == 0.toByte() && data[at + 2] == 1.toByte() -> 3
            else -> 0
        }
        val starts = mutableListOf<Pair<Int, Int>>()
        var cursor = 0
        while (cursor < data.size) {
            val codeSize = startCode(cursor)
            if (codeSize > 0) {
                starts += cursor to codeSize
                cursor += codeSize
            } else cursor++
        }
        if (starts.isEmpty()) return if (data.isEmpty()) emptyList() else listOf(data)
        return starts.mapIndexedNotNull { index, (start, codeSize) ->
            val from = start + codeSize
            var to = if (index + 1 < starts.size) starts[index + 1].first else data.size
            while (to > from && data[to - 1] == 0.toByte()) to--
            if (to <= from) null else data.copyOfRange(from, to)
        }
    }

    fun stop() {
        if (stopped) return
        stopped = true
        try { codec.signalEndOfInputStream() } catch (_: Exception) { }
        try { codec.stop() } catch (_: Exception) { }
        try { codec.release() } catch (_: Exception) { }
        surface.release()
    }

    private object MediaCodecInfoCodecs {
        const val COLOR_FORMAT_SURFACE = 0x7F000789
    }
}
