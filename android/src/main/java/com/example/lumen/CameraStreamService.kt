package com.example.lumen

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

class CameraStreamService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Lumen:CameraWakeLock")
        wakeLock?.acquire()

        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(CHANNEL_ID, "Lumen camera", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        startForeground(NOTIFICATION_ID, notification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        wakeLock?.release()
    }

    private fun notification(): Notification = if (Build.VERSION.SDK_INT >= 26) {
        Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setContentTitle("Lumen is ready")
            .setContentText("Waiting for a Mac camera connection")
            .setOngoing(true)
            .build()
    } else {
        @Suppress("DEPRECATION")
        Notification.Builder(this)
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setContentTitle("Lumen is ready")
            .setContentText("Waiting for a Mac camera connection")
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "lumen-camera"
        private const val NOTIFICATION_ID = 1
    }
}
