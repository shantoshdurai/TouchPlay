package com.touchplay.app

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import java.io.ByteArrayOutputStream

/**
 * Streams the phone camera as JPEG frames for the Virtual Cam feature.
 *
 * Camera2 → YUV_420_888 ImageReader → NV21 → YuvImage JPEG at ~15 fps, 640×480.
 * Frames go to [onFrame]; MainActivity forwards them to the PC over WebSocket.
 */
class CameraStreamer(
    private val context: Context,
    private val onFrame: (ByteArray) -> Unit,
) {
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null
    private var thread: HandlerThread? = null
    private var lastFrame = 0L

    val running get() = device != null

    @SuppressLint("MissingPermission")  // caller checks CAMERA permission
    fun start(useFront: Boolean, onResult: (Boolean) -> Unit) {
        stop()
        try {
            val cm = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val wanted = if (useFront) CameraCharacteristics.LENS_FACING_FRONT
                         else CameraCharacteristics.LENS_FACING_BACK
            val id = cm.cameraIdList.firstOrNull {
                cm.getCameraCharacteristics(it)
                    .get(CameraCharacteristics.LENS_FACING) == wanted
            } ?: cm.cameraIdList.firstOrNull()
            if (id == null) {
                onResult(false)
                return
            }

            thread = HandlerThread("touchplay-cam").also { it.start() }
            val handler = Handler(thread!!.looper)

            reader = ImageReader.newInstance(640, 480, ImageFormat.YUV_420_888, 3)
            reader!!.setOnImageAvailableListener({ r ->
                val img = r.acquireLatestImage() ?: return@setOnImageAvailableListener
                try {
                    val now = SystemClock.elapsedRealtime()
                    if (now - lastFrame < 66) return@setOnImageAvailableListener  // ~15 fps
                    lastFrame = now
                    onFrame(toJpeg(img))
                } catch (_: Exception) {
                } finally {
                    img.close()
                }
            }, handler)

            cm.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(cam: CameraDevice) {
                    device = cam
                    try {
                        val req = cam.createCaptureRequest(CameraDevice.TEMPLATE_RECORD)
                        req.addTarget(reader!!.surface)
                        @Suppress("DEPRECATION")
                        cam.createCaptureSession(listOf(reader!!.surface),
                            object : CameraCaptureSession.StateCallback() {
                                override fun onConfigured(s: CameraCaptureSession) {
                                    session = s
                                    try {
                                        s.setRepeatingRequest(req.build(), null, handler)
                                        onResult(true)
                                    } catch (_: Exception) {
                                        onResult(false)
                                        stop()
                                    }
                                }
                                override fun onConfigureFailed(s: CameraCaptureSession) {
                                    onResult(false)
                                    stop()
                                }
                            }, handler)
                    } catch (_: Exception) {
                        onResult(false)
                        stop()
                    }
                }
                override fun onDisconnected(cam: CameraDevice) { stop() }
                override fun onError(cam: CameraDevice, error: Int) {
                    onResult(false)
                    stop()
                }
            }, handler)
        } catch (_: Exception) {
            onResult(false)
            stop()
        }
    }

    fun stop() {
        try { session?.close() } catch (_: Exception) {}
        try { device?.close() } catch (_: Exception) {}
        try { reader?.close() } catch (_: Exception) {}
        session = null
        device = null
        reader = null
        thread?.quitSafely()
        thread = null
    }

    private fun toJpeg(image: Image): ByteArray {
        val w = image.width
        val h = image.height
        val nv21 = ByteArray(w * h * 3 / 2)

        // Y plane (respect rowStride)
        val yPlane = image.planes[0]
        val yBuf = yPlane.buffer
        var pos = 0
        if (yPlane.rowStride == w) {
            yBuf.get(nv21, 0, w * h)
            pos = w * h
        } else {
            for (row in 0 until h) {
                yBuf.position(row * yPlane.rowStride)
                yBuf.get(nv21, pos, w)
                pos += w
            }
        }

        // Interleave V/U → NV21
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val uBuf = uPlane.buffer
        val vBuf = vPlane.buffer
        val rowStride = uPlane.rowStride
        val pixStride = uPlane.pixelStride
        for (row in 0 until h / 2) {
            for (col in 0 until w / 2) {
                val p = row * rowStride + col * pixStride
                nv21[pos++] = vBuf.get(p)
                nv21[pos++] = uBuf.get(p)
            }
        }

        val out = ByteArrayOutputStream(32 * 1024)
        YuvImage(nv21, ImageFormat.NV21, w, h, null)
            .compressToJpeg(Rect(0, 0, w, h), 68, out)
        return out.toByteArray()
    }
}
