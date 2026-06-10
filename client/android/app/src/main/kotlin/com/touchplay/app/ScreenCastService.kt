package com.touchplay.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.SystemClock
import java.io.ByteArrayOutputStream

/**
 * Foreground service that mirrors the phone screen ("Projector").
 *
 * Android 10+ requires MediaProjection to live inside a foreground service of
 * type mediaProjection. Frames are captured at half resolution ~12 fps,
 * JPEG-compressed, and handed to MainActivity via [onFrame] which forwards
 * them over the WebSocket to the PC.
 */
class ScreenCastService : Service() {

    companion object {
        @Volatile var onFrame: ((ByteArray) -> Unit)? = null
        @Volatile var running = false
        const val CHANNEL_ID = "touchplay_projector"
        const val ACTION_STOP = "com.touchplay.app.STOP_CAST"
    }

    private var projection: MediaProjection? = null
    private var vDisplay: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private var thread: HandlerThread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null || intent.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        startInForeground()

        val code = intent.getIntExtra("code", 0)
        @Suppress("DEPRECATION")
        val data: Intent? = if (Build.VERSION.SDK_INT >= 33)
            intent.getParcelableExtra("data", Intent::class.java)
        else
            intent.getParcelableExtra("data")
        if (data == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        try {
            val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            projection = mpm.getMediaProjection(code, data)

            thread = HandlerThread("touchplay-cast").also { it.start() }
            val handler = Handler(thread!!.looper)

            // Android 14+ requires a registered callback before createVirtualDisplay.
            projection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    stopSelf()
                }
            }, handler)

            val metrics = resources.displayMetrics
            var w = metrics.widthPixels / 2
            var h = metrics.heightPixels / 2
            w -= w % 2
            h -= h % 2

            reader = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
            var last = 0L
            reader!!.setOnImageAvailableListener({ r ->
                val img = r.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
                    val now = SystemClock.elapsedRealtime()
                    if (now - last < 80) return@setOnImageAvailableListener  // ~12 fps cap
                    last = now

                    val plane = img.planes[0]
                    val rowPadding = plane.rowStride - plane.pixelStride * w
                    val bmpW = w + rowPadding / plane.pixelStride
                    val bmp = Bitmap.createBitmap(bmpW, h, Bitmap.Config.ARGB_8888)
                    bmp.copyPixelsFromBuffer(plane.buffer)
                    val cropped = if (rowPadding == 0) bmp
                                  else Bitmap.createBitmap(bmp, 0, 0, w, h)

                    val out = ByteArrayOutputStream(64 * 1024)
                    cropped.compress(Bitmap.CompressFormat.JPEG, 60, out)
                    if (cropped !== bmp) bmp.recycle()
                    cropped.recycle()
                    onFrame?.invoke(out.toByteArray())
                } catch (_: Exception) {
                } finally {
                    img.close()
                }
            }, handler)

            vDisplay = projection?.createVirtualDisplay(
                "TouchPlayCast", w, h, metrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader!!.surface, null, handler
            )
            running = true
        } catch (_: Exception) {
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun startInForeground() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Projector",
                    NotificationManager.IMPORTANCE_LOW)
            )
        }
        val notif: Notification = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("TouchPlay Projector")
                .setContentText("Casting your screen to the PC")
                .setSmallIcon(android.R.drawable.ic_menu_share)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("TouchPlay Projector")
                .setContentText("Casting your screen to the PC")
                .setSmallIcon(android.R.drawable.ic_menu_share)
                .build()
        }
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(1001, notif,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(1001, notif)
        }
    }

    override fun onDestroy() {
        running = false
        try { vDisplay?.release() } catch (_: Exception) {}
        try { projection?.stop() } catch (_: Exception) {}
        try { reader?.close() } catch (_: Exception) {}
        thread?.quitSafely()
        super.onDestroy()
    }
}
