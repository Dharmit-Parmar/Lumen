package com.example.lumen

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Surface
import java.io.DataOutputStream
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean
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
    private var writerThread: Thread? = null
    private var output: DataOutputStream? = null
    private val sendQueue = ArrayBlockingQueue<EncodedFrame>(2)
    private var waitingForKeyframe = true
    private val failureReported = AtomicBoolean(false)

    private data class EncodedFrame(val type: Int, val timestampUs: Long, val payload: ByteArray)

    init {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
            setInteger(MediaFormat.KEY_BITRATE_MODE, MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR)
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
        output = DataOutputStream(socket.getOutputStream())
        drainThread = thread(name = "LumenAvcOutput") {
            try {
                drain(socket, rotation, mirror)
            } catch (error: Exception) {
                Log.e("Lumen", "AVC output drain failed", error)
                reportFailure(error)
            }
        }
    }

    private fun drain(socket: Socket, rotation: Int, mirror: Boolean) {
        val output = output ?: throw IllegalStateException("Encoder output is unavailable")
        val info = MediaCodec.BufferInfo()
        var sentConfig = false
        var frameCount = 0

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
                    writerThread = thread(name = "LumenTcpWriter") { writeQueuedFrames(output) }
                    requestKeyframe()
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
                            if (++frameCount % 30 == 0) {
                                Log.i("LumenTiming", "encode output PTS=${info.presentationTimeUs}us")
                            }
                            val keyframe = info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0
                            if (keyframe) {
                                sendQueue.clear()
                                waitingForKeyframe = false
                                sendQueue.offer(EncodedFrame(2, info.presentationTimeUs, convertToAvcc(bytes)))
                            } else if (!waitingForKeyframe) {
                                val frame = EncodedFrame(3, info.presentationTimeUs, convertToAvcc(bytes))
                                if (!sendQueue.offer(frame)) {
                                    sendQueue.clear()
                                    waitingForKeyframe = true
                                    requestKeyframe()
                                    Log.w("Lumen", "Socket fell behind; dropping until the next keyframe")
                                }
                            }
                        }
                    } finally {
                        codec.releaseOutputBuffer(index, false)
                    }
                }
            }
        }
    }

    private fun writeQueuedFrames(output: DataOutputStream) {
        var frameCount = 0
        try {
            while (!stopped) {
                val frame = sendQueue.take()
                val writeStarted = System.nanoTime()
                writeMessage(output, frame.type, frame.timestampUs, frame.payload)
                if (++frameCount % 30 == 0) {
                    Log.i("LumenTiming", "TCP write took ${(System.nanoTime() - writeStarted) / 1_000}us; queue=${sendQueue.size}")
                }
            }
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        } catch (error: Exception) {
            Log.e("Lumen", "TCP frame writer failed", error)
            reportFailure(error)
        }
    }

    private fun requestKeyframe() {
        if (Build.VERSION.SDK_INT >= 19) {
            try {
                codec.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) })
            } catch (error: Exception) {
                Log.w("Lumen", "Could not request an IDR frame", error)
            }
        }
    }

    private fun reportFailure(error: Exception) {
        if (!stopped && failureReported.compareAndSet(false, true)) onFailure(error)
    }

    private fun writeConfig(output: DataOutputStream, sps: ByteArray, pps: ByteArray, rotation: Int, mirror: Boolean) {
        require(sps.isNotEmpty() && pps.isNotEmpty() && 14 + sps.size + pps.size <= MAX_CONFIG_SIZE)
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
        require(type in 1..3 && payload.isNotEmpty() && payload.size <= MAX_PAYLOAD_SIZE)
        val header = ByteBuffer.allocate(16).order(ByteOrder.BIG_ENDIAN)
            .put(0x4c).put(0x55).put(1).putInt(payload.size).put(type.toByte()).putLong(timestampUs)
        output.write(header.array())
        output.write(payload)
        output.flush()
    }

    private fun findNal(buffer: ByteBuffer, type: Int): ByteArray? {
        val data = ByteArray(buffer.remaining())
        buffer.duplicate().get(data)
        var start = 0
        if (data.size >= 4 && data[0] == 0.toByte() && data[1] == 0.toByte() && data[2] == 0.toByte() && data[3] == 1.toByte()) start = 4
        else if (data.size >= 3 && data[0] == 0.toByte() && data[1] == 0.toByte() && data[2] == 1.toByte()) start = 3
        return if (start < data.size && (data[start].toInt() and 0x1f) == type) data.copyOfRange(start, data.size) else null
    }

    private fun convertToAvcc(data: ByteArray): ByteArray {
        val starts = mutableListOf<Pair<Int, Int>>()
        var cursor = 0
        while (cursor < data.size) {
            val codeSize = when {
                cursor + 3 < data.size && data[cursor] == 0.toByte() && data[cursor + 1] == 0.toByte() && data[cursor + 2] == 0.toByte() && data[cursor + 3] == 1.toByte() -> 4
                cursor + 2 < data.size && data[cursor] == 0.toByte() && data[cursor + 1] == 0.toByte() && data[cursor + 2] == 1.toByte() -> 3
                else -> 0
            }
            if (codeSize > 0) {
                starts += cursor to codeSize
                cursor += codeSize
            } else cursor++
        }
        
        if (starts.isEmpty()) {
            val buf = ByteBuffer.allocate(data.size + 4).order(ByteOrder.BIG_ENDIAN)
            buf.putInt(data.size)
            buf.put(data)
            return buf.array()
        }
        
        val totalSize = data.size - starts.sumOf { it.second } + (starts.size * 4)
        val buf = ByteBuffer.allocate(totalSize).order(ByteOrder.BIG_ENDIAN)
        for (i in starts.indices) {
            val start = starts[i].first + starts[i].second
            var to = if (i + 1 < starts.size) starts[i + 1].first else data.size
            while (to > start && data[to - 1] == 0.toByte()) to--
            val len = to - start
            if (len > 0) {
                buf.putInt(len)
                buf.put(data, start, len)
            }
        }
        return buf.array().copyOfRange(0, buf.position())
    }

    fun stop() {
        if (stopped) return
        stopped = true
        sendQueue.clear()
        writerThread?.interrupt()
        try { codec.signalEndOfInputStream() } catch (_: Exception) { }
        try { codec.stop() } catch (_: Exception) { }
        try { codec.release() } catch (_: Exception) { }
        surface.release()
    }

    private companion object {
        const val MAX_PAYLOAD_SIZE = 8_388_608
        const val MAX_CONFIG_SIZE = 65_536
    }
}
