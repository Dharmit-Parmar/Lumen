package com.example.lumen

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.StreamConfigurationMap
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import android.view.TextureView
import android.view.ViewGroup
import android.view.WindowInsets
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.LinearLayout
import android.widget.Spinner
import android.widget.TextView
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CountDownLatch
import kotlin.concurrent.thread

class MainActivity : Activity(), TextureView.SurfaceTextureListener {
    private lateinit var preview: TextureView
    private lateinit var picker: Spinner
    private lateinit var status: TextView
    private lateinit var streamButton: Button
    private lateinit var cameraManager: CameraManager
    private lateinit var cameraThread: HandlerThread
    private lateinit var cameraHandler: Handler
    private var camera: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var previewSurface: Surface? = null
    private var encoder: AvcEncoder? = null
    private var serverSocket: ServerSocket? = null
    private var serverThread: Thread? = null
    private var clientSocket: Socket? = null
    private var streamEnded: CountDownLatch? = null
    private var cameraIds = emptyList<String>()
    private var selectedId: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        cameraThread = HandlerThread("LumenCamera").apply { start() }
        cameraHandler = Handler(cameraThread.looper)

        preview = TextureView(this).apply { surfaceTextureListener = this@MainActivity }
        picker = Spinner(this)
        status = TextView(this).apply { text = "Choose a camera to preview"; textSize = 16f }
        streamButton = Button(this).apply {
            text = "Start USB stream"
            isAllCaps = false
            minHeight = dp(56)
            setOnClickListener { if (serverSocket == null) startServer() else stopServer() }
        }
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(16), dp(20), dp(16))
            addView(picker, LinearLayout.LayoutParams(-1, dp(56)))
            addView(streamButton, LinearLayout.LayoutParams(-1, dp(56)))
            addView(preview, LinearLayout.LayoutParams(-1, 0, 1f))
            addView(status, LinearLayout.LayoutParams(-1, dp(48)))
        }
        layout.setOnApplyWindowInsetsListener { view, insets ->
            val bars = if (Build.VERSION.SDK_INT >= 30) {
                insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
            } else null
            view.setPadding(
                dp(20) + (bars?.left ?: insets.systemWindowInsetLeft),
                dp(16) + (bars?.top ?: insets.systemWindowInsetTop),
                dp(20) + (bars?.right ?: insets.systemWindowInsetRight),
                dp(16) + (bars?.bottom ?: insets.systemWindowInsetBottom)
            )
            insets
        }
        setContentView(layout)
        layout.requestApplyInsets()
        loadCameras()

        picker.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
            override fun onNothingSelected(parent: android.widget.AdapterView<*>?) = Unit
            override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: android.view.View?, position: Int, id: Long) {
                val cameraId = cameraIds.getOrNull(position) ?: return
                if (cameraId != selectedId) {
                    selectedId = cameraId
                    if (preview.isAvailable) openCamera(cameraId)
                }
            }
        }
    }

    private fun loadCameras() {
        try {
            cameraIds = cameraManager.cameraIdList.toList()
            val labels = cameraIds.map { id ->
                val chars = cameraManager.getCameraCharacteristics(id)
                val facing = when (chars.get(CameraCharacteristics.LENS_FACING)) {
                    CameraCharacteristics.LENS_FACING_FRONT -> "Front"
                    CameraCharacteristics.LENS_FACING_BACK -> "Rear"
                    else -> "External"
                }
                val focal = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                "$facing camera $id" + (focal?.firstOrNull()?.let { " · ${"%.1f".format(it)} mm" } ?: "")
            }
            picker.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, labels)
            status.text = "${cameraIds.size} camera(s) available"
            if (cameraIds.isEmpty()) status.text = "No cameras found"
        } catch (error: Exception) {
            status.text = "Cannot list cameras: ${error.localizedMessage}"
        }
    }

    override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
        selectedId?.let(::openCamera)
    }

    private fun openCamera(id: String) {
        closeCamera()
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.CAMERA), 1)
            return
        }
        try {
            cameraManager.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(device: CameraDevice) {
                    if (isFinishing || isDestroyed || !preview.isAvailable || selectedId != id) {
                        device.close()
                        return
                    }
                    camera = device
                    createPreview(device)
                }
                override fun onDisconnected(device: CameraDevice) { device.close(); camera = null }
                override fun onError(device: CameraDevice, error: Int) {
                    device.close(); camera = null
                    runOnUiThread { status.text = "Camera error $error" }
                }
            }, cameraHandler)
        } catch (error: Exception) {
            status.text = "Cannot open camera: ${error.localizedMessage}"
        }
    }

    private fun createPreview(device: CameraDevice) {
        try {
            configurePreview(device)
        } catch (error: Exception) {
            if (camera === device) {
                device.close()
                camera = null
            }
            previewSurface?.release()
            previewSurface = null
            runOnUiThread { status.text = "Cannot start preview: ${error.localizedMessage}" }
        }
    }

    private fun configurePreview(device: CameraDevice) {
        val texture = preview.surfaceTexture ?: return
        val map: StreamConfigurationMap? = cameraManager.getCameraCharacteristics(device.id)
            .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val size = map?.getOutputSizes(SurfaceTexture::class.java)
            ?.filter { it.width <= 1280 && it.height <= 720 }
            ?.maxByOrNull { it.width.toLong() * it.height }
            ?: map?.getOutputSizes(SurfaceTexture::class.java)?.firstOrNull()
            ?: run { runOnUiThread { status.text = "Camera has no preview format" }; return }
        texture.setDefaultBufferSize(size.width, size.height)
        val surface = Surface(texture)
        session?.close()
        session = null
        previewSurface = surface
        val request = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
            addTarget(surface)
            encoder?.surface?.let(::addTarget)
            set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
            cameraManager.getCameraCharacteristics(device.id)
                .get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                ?.filter { it.upper <= 30 }
                ?.maxByOrNull { it.upper }
                ?.let { set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, it) }
        }
        val outputs = listOfNotNull(surface, encoder?.surface)
        device.createCaptureSession(outputs, object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(configured: CameraCaptureSession) {
                if (camera !== device) { configured.close(); surface.release(); return }
                session = configured
                try {
                    configured.setRepeatingRequest(request.build(), null, cameraHandler)
                    Log.i("Lumen", "Camera2 preview/encoder capture started")
                    runOnUiThread { status.text = "Previewing camera ${device.id}" }
                } catch (error: Exception) {
                    runOnUiThread { status.text = "Preview failed: ${error.localizedMessage}" }
                }
            }
            override fun onConfigureFailed(failed: CameraCaptureSession) {
                Log.e("Lumen", "Camera2 rejected preview/encoder surfaces")
                surface.release()
                if (previewSurface === surface) previewSurface = null
                runOnUiThread {
                    if (encoder != null) stopStreaming("Camera cannot stream this resolution")
                    status.text = "Camera preview configuration failed"
                }
            }
        }, cameraHandler)
    }

    private fun closeCamera() {
        session?.close(); session = null
        camera?.close(); camera = null
        previewSurface?.release(); previewSurface = null
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun startServer() {
        try {
            val listener = ServerSocket().apply {
                reuseAddress = true
                bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), 5000))
            }
            serverSocket = listener
            streamButton.text = "Stop USB stream"
            status.text = "Waiting for Mac on port 5000"
            serverThread = thread(name = "LumenTcpServer") {
                try {
                    while (serverSocket === listener && !listener.isClosed) {
                        val client = listener.accept().apply { tcpNoDelay = true }
                        Log.i("Lumen", "TCP client connected")
                        val ended = CountDownLatch(1)
                        runOnUiThread {
                            if (serverSocket === listener) startStreaming(client, ended)
                            else { client.close(); ended.countDown() }
                        }
                        ended.await()
                    }
                } catch (error: Exception) {
                    if (serverSocket === listener && !listener.isClosed) {
                        runOnUiThread { status.text = "USB server stopped: ${error.localizedMessage}" }
                    }
                }
            }
        } catch (error: Exception) {
            Log.e("Lumen", "Could not start loopback server", error)
            status.text = "Cannot start USB server: ${error.localizedMessage}"
        }
    }

    private fun startStreaming(socket: Socket, ended: CountDownLatch) {
        try {
            Log.i("Lumen", "Starting AVC stream")
            val cameraId = selectedId ?: throw IllegalStateException("Select a camera first")
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            val displayDegrees = when (display.rotation) {
                Surface.ROTATION_90 -> 90
                Surface.ROTATION_180 -> 180
                Surface.ROTATION_270 -> 270
                else -> 0
            }
            val isFront = characteristics.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT
            val rotation = if (isFront) (sensorOrientation + displayDegrees) % 360
                else (sensorOrientation - displayDegrees + 360) % 360
            val newEncoder = AvcEncoder { error ->
                Log.e("Lumen", "AVC stream failed", error)
                runOnUiThread { stopStreaming("Stream ended: ${error.localizedMessage}") }
            }
            encoder = newEncoder
            clientSocket = socket
            streamEnded = ended
            status.text = "Connected to Mac; sending 720p video"
            newEncoder.start(socket, rotation, isFront)
            Log.i("Lumen", "Encoder ready; configuring Camera2 outputs")
            val currentCamera = camera
            if (currentCamera != null) createPreview(currentCamera)
            else openCamera(cameraId)
        } catch (error: Exception) {
            Log.e("Lumen", "Could not start AVC stream", error)
            try { socket.close() } catch (_: Exception) { }
            status.text = "Cannot start video stream: ${error.localizedMessage}"
            ended.countDown()
        }
    }

    private fun stopStreaming(message: String) {
        val oldSocket = clientSocket
        clientSocket = null
        try { oldSocket?.close() } catch (_: Exception) { }
        encoder?.stop()
        encoder = null
        streamEnded?.countDown()
        streamEnded = null
        if (camera != null && preview.isAvailable) createPreview(camera!!)
        if (serverSocket != null) status.text = "$message · waiting for Mac"
    }

    private fun stopServer() {
        val listener = serverSocket
        serverSocket = null
        try { listener?.close() } catch (_: Exception) { }
        stopStreaming("USB stream stopped")
        streamButton.text = "Start USB stream"
        status.text = "USB stream stopped"
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1 && grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            selectedId?.let(::openCamera)
        } else status.text = "Camera permission is required"
    }

    override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) = Unit
    override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean { closeCamera(); return true }
    override fun onSurfaceTextureUpdated(texture: SurfaceTexture) = Unit
    override fun onResume() { super.onResume(); if (::preview.isInitialized && preview.isAvailable) selectedId?.let(::openCamera) }
    override fun onPause() { stopServer(); closeCamera(); super.onPause() }
    override fun onDestroy() { closeCamera(); cameraThread.quitSafely(); super.onDestroy() }
}
