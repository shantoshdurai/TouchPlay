package com.touchplay.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
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
 * type mediaProjection. Frames are captured at half resolution ~22 fps,
 * JPEG-compressed, and handed to MainActivity via [onFrame] which forwards
 * them over the WebSocket to the PC.
 *
 * Rotation-aware: when the phone rotates, the virtual display is resized to
 * the new orientation so the PC window always matches the phone's real shape
 * (no baked-in black bars from a stale landscape canvas).
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
    private var handler: Handler? = null
    private var lastFrame = 0L
    private var curW = 0
    private var curH = 0

    override fun onBind(intent: Intent?): IBinder? = null

    /** Half-resolution capture size for the CURRENT orientation, even-aligned. */
    private fun captureSize(): Pair<Int, Int> {
        val metrics = resources.displayMetrics
        var w = metrics.widthPixels / 2
        var h = metrics.heightPixels / 2
        w -= w % 2
        h -= h % 2
        return Pair(w, h)
    }

    /** Build an ImageReader that JPEG-encodes frames at its OWN dimensions —
     *  safe to swap in after a rotation without touching the listener. */
    private fun buildReader(w: Int, h: Int): ImageReader {
        val r = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
        r.setOnImageAvailableListener({ rd ->
            val img = rd.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                val now = SystemClock.elapsedRealtime()
                if (now - lastFrame < 45) return@setOnImageAvailableListener  // ~22 fps cap
                lastFrame = now

                val iw = img.width
                val ih = img.height
                val plane = img.planes[0]
                val rowPadding = plane.rowStride - plane.pixelStride * iw
                val bmpW = iw + rowPadding / plane.pixelStride
                val bmp = Bitmap.createBitmap(bmpW, ih, Bitmap.Config.ARGB_8888)
                bmp.copyPixelsFromBuffer(plane.buffer)
                val cropped = if (rowPadding == 0) bmp
                              else Bitmap.createBitmap(bmp, 0, 0, iw, ih)

                val out = ByteArrayOutputStream(64 * 1024)
                cropped.compress(Bitmap.CompressFormat.JPEG, 70, out)
                if (cropped !== bmp) bmp.recycle()
                cropped.recycle()
                onFrame?.invoke(out.toByteArray())
            } catch (_: Exception) {
            } finally {
                img.close()
            }
        }, handler)
        return r
    }

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
            handler = Handler(thread!!.looper)

            // Android 14+ requires a registered callback before createVirtualDisplay.
            projection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    stopSelf()
                }
            }, handler)

            val (w, h) = captureSize()
            curW = w
            curH = h
            reader = buildReader(w, h)

            vDisplay = projection?.createVirtualDisplay(
                "TouchPlayCast", w, h, resources.displayMetrics.densityDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader!!.surface, null, handler
            )
            running = true
        } catch (_: Exception) {
            stopSelf()
        }
        return START_NOT_STICKY
    }

    /** Phone rotated → resize the virtual display so frames match the new
     *  orientation instead of letterboxing into the old canvas. */
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (!running) return
        try {
            val (w, h) = captureSize()
            if (w == curW && h == curH) return
            curW = w
            curH = h
            val newReader = buildReader(w, h)
            vDisplay?.resize(w, h, resources.displayMetrics.densityDpi)
            vDisplay?.surface = newReader.surface
            val old = reader
            reader = newReader
            try { old?.close() } catch (_: Exception) {}
        } catch (_: Exception) {
        }
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
        thread = null
        handler = null
        super.onDestroy()
    }
}
