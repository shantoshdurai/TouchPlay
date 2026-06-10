package com.touchplay.app

import android.Manifest
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val deviceChannel = "touchplay/device"
    private val filesChannel = "touchplay/files"
    private val castChannel = "touchplay/cast"
    private val castFramesChannel = "touchplay/cast_frames"

    private val reqCamera = 7101
    private val reqProjection = 7102
    private val reqPickFile = 7103

    private var wifiLock: WifiManager.WifiLock? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private var frameSink: EventChannel.EventSink? = null
    private var camera: CameraStreamer? = null
    private var pendingCamResult: MethodChannel.Result? = null
    private var pendingCamFront = false
    private var pendingProjResult: MethodChannel.Result? = null
    private var pendingPickResult: MethodChannel.Result? = null

    // Hold a high-performance / low-latency Wi-Fi lock for the app's lifetime so
    // Android's Wi-Fi power saver can't quietly drop our LAN socket mid-game —
    // the usual cause of the controller "keeps disconnecting and reconnecting".
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            else
                @Suppress("DEPRECATION") WifiManager.WIFI_MODE_FULL_HIGH_PERF
            wifiLock = wifi.createWifiLock(mode, "touchplay:wifi").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        try { if (wifiLock?.isHeld == true) wifiLock?.release() } catch (_: Exception) {}
        camera?.stop()
        stopProjection()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "stats") {
                    result.success(readStats())
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, filesChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "save_to_downloads" -> {
                        val path = call.argument<String>("path")
                        val name = call.argument<String>("name")
                        if (path == null || name == null) {
                            result.error("args", "path and name required", null)
                        } else {
                            try {
                                result.success(saveToDownloads(path, name))
                            } catch (e: Exception) {
                                result.error("save", e.message, null)
                            }
                        }
                    }
                    "pick_file" -> pickFile(result)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, castChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start_camera" -> startCamera(call.argument<Boolean>("front") ?: false, result)
                    "stop_camera" -> {
                        camera?.stop()
                        result.success(true)
                    }
                    "start_projection" -> startProjection(result)
                    "stop_projection" -> {
                        stopProjection()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, castFramesChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    frameSink = sink
                }
                override fun onCancel(args: Any?) {
                    frameSink = null
                }
            })
    }

    // ── Frame routing (camera + projector → Dart) ────────────────────────────

    private fun postFrame(bytes: ByteArray) {
        mainHandler.post { frameSink?.success(bytes) }
    }

    // ── Virtual Cam ──────────────────────────────────────────────────────────

    private fun startCamera(front: Boolean, result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED) {
            pendingCamResult = result
            pendingCamFront = front
            ActivityCompat.requestPermissions(
                this, arrayOf(Manifest.permission.CAMERA), reqCamera)
            return
        }
        doStartCamera(front, result)
    }

    private fun doStartCamera(front: Boolean, result: MethodChannel.Result) {
        if (camera == null) camera = CameraStreamer(this) { postFrame(it) }
        var replied = false
        camera!!.start(front) { ok ->
            mainHandler.post {
                if (!replied) {
                    replied = true
                    result.success(ok)
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == reqCamera) {
            val result = pendingCamResult ?: return
            pendingCamResult = null
            if (grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                doStartCamera(pendingCamFront, result)
            } else {
                result.success(false)
            }
        }
    }

    // ── Projector (MediaProjection) ──────────────────────────────────────────

    private fun startProjection(result: MethodChannel.Result) {
        if (ScreenCastService.running) {
            ScreenCastService.onFrame = { postFrame(it) }
            result.success(true)
            return
        }
        pendingProjResult = result
        val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        @Suppress("DEPRECATION")
        startActivityForResult(mpm.createScreenCaptureIntent(), reqProjection)
    }

    // ── File picker (system document UI — no storage permission needed) ──────

    private fun pickFile(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.success(null)
            return
        }
        pendingPickResult = result
        try {
            val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
            }
            @Suppress("DEPRECATION")
            startActivityForResult(
                Intent.createChooser(intent, "Send to PC"), reqPickFile)
        } catch (e: Exception) {
            pendingPickResult = null
            result.error("pick", e.message, null)
        }
    }

    private fun handlePickedFile(resultCode: Int, data: Intent?) {
        val result = pendingPickResult ?: return
        pendingPickResult = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        // Copy the content URI into the app cache off the UI thread — content
        // providers can be slow and the file may be large.
        Thread {
            try {
                var name = "file"
                var size = -1L
                contentResolver.query(uri, null, null, null, null)?.use { c ->
                    if (c.moveToFirst()) {
                        val ni = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                        val si = c.getColumnIndex(android.provider.OpenableColumns.SIZE)
                        if (ni >= 0) name = c.getString(ni) ?: name
                        if (si >= 0) size = c.getLong(si)
                    }
                }
                val dest = File(cacheDir, "upload-${System.currentTimeMillis()}-$name")
                contentResolver.openInputStream(uri).use { input ->
                    dest.outputStream().use { input!!.copyTo(it) }
                }
                mainHandler.post {
                    result.success(mapOf(
                        "path" to dest.absolutePath,
                        "name" to name,
                        "size" to (if (size >= 0) size else dest.length()),
                    ))
                }
            } catch (e: Exception) {
                mainHandler.post { result.error("pick", e.message, null) }
            }
        }.start()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == reqPickFile) {
            handlePickedFile(resultCode, data)
            return
        }
        if (requestCode == reqProjection) {
            val result = pendingProjResult ?: return
            pendingProjResult = null
            if (resultCode == RESULT_OK && data != null) {
                ScreenCastService.onFrame = { postFrame(it) }
                val svc = Intent(this, ScreenCastService::class.java).apply {
                    putExtra("code", resultCode)
                    putExtra("data", data)
                }
                if (Build.VERSION.SDK_INT >= 26) startForegroundService(svc)
                else startService(svc)
                result.success(true)
            } else {
                result.success(false)
            }
        }
    }

    private fun stopProjection() {
        ScreenCastService.onFrame = null
        try {
            stopService(Intent(this, ScreenCastService::class.java))
        } catch (_: Exception) {}
    }

    // ── Save a downloaded file into the phone's Downloads (MediaStore) ───────

    private fun saveToDownloads(path: String, name: String): String {
        val src = File(path)
        if (Build.VERSION.SDK_INT >= 29) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS + "/TouchPlay")
            }
            val uri = contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("MediaStore rejected the file")
            contentResolver.openOutputStream(uri).use { out ->
                src.inputStream().use { it.copyTo(out!!) }
            }
            return "Downloads/TouchPlay/$name"
        }

        // Pre-Android-10: write straight into public Downloads; fall back to the
        // app folder if storage permission is missing on this old device.
        return try {
            @Suppress("DEPRECATION")
            val dir = File(Environment
                .getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "TouchPlay")
            dir.mkdirs()
            var dest = File(dir, name)
            var i = 2
            while (dest.exists()) {
                val dot = name.lastIndexOf('.')
                dest = if (dot > 0)
                    File(dir, "${name.substring(0, dot)} ($i)${name.substring(dot)}")
                else File(dir, "$name ($i)")
                i++
            }
            src.copyTo(dest)
            "Downloads/TouchPlay/${dest.name}"
        } catch (_: Exception) {
            val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)!!
            val dest = File(dir, name)
            src.copyTo(dest, overwrite = true)
            dest.absolutePath
        }
    }

    // Returns {tempC: Double, battery: Int} from the sticky battery broadcast.
    private fun readStats(): Map<String, Any> {
        val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))

        val tempTenths = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1
        val tempC = if (tempTenths > 0) tempTenths / 10.0 else -1.0

        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val battery = if (level >= 0 && scale > 0) (level * 100 / scale) else -1

        return mapOf("tempC" to tempC, "battery" to battery)
    }
}
