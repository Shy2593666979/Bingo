package com.example.bingo

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioFormat
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.AlarmClock
import android.provider.MediaStore
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.igexin.sdk.PushManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.text.SimpleDateFormat
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Calendar
import java.util.Locale
import java.util.UUID
import java.util.concurrent.LinkedBlockingQueue

class MainActivity : FlutterActivity() {
    private lateinit var localChatDatabase: LocalChatDatabase
    private var audioEventSink: EventChannel.EventSink? = null
    private var pendingAudioStartResult: MethodChannel.Result? = null
    private var pendingImageResult: MethodChannel.Result? = null
    private var pendingCameraFile: File? = null
    @Volatile private var recording = false
    private var audioThread: Thread? = null
    private var callAudio = false
    private var callAudioTrack: AudioTrack? = null
    private var callPlaybackThread: Thread? = null
    private val callPlaybackQueue = LinkedBlockingQueue<ByteArray>(80)
    @Volatile private var callPlaybackRunning = false
    private var previousCallAudioMode: Int? = null
    private var previousCallSpeakerphoneOn: Boolean? = null
    private var statusBarOverlay: View? = null
    private var incomingCallPlayer: MediaPlayer? = null
    private var incomingCallRingtone: Ringtone? = null
    private var incomingCallVibrator: Vibrator? = null
    private var incomingCallAudioFocusRequest: AudioFocusRequest? = null
    private var hasLegacyIncomingCallAudioFocus = false
    private var incomingCallRingingRequested = false
    private val incomingCallHandler = Handler(Looper.getMainLooper())
    private var incomingCallAudioAttributes: AudioAttributes? = null
    private val delayedIncomingCallPlayback = Runnable { startIncomingCallPlayback() }
    private val retryIncomingCallAudioFocus = Runnable {
        val attributes = incomingCallAudioAttributes ?: return@Runnable
        if (!incomingCallRingingRequested) return@Runnable
        when (requestIncomingCallAudioFocus(attributes)) {
            AudioManager.AUDIOFOCUS_REQUEST_GRANTED ->
                incomingCallHandler.postDelayed(delayedIncomingCallPlayback, 120)
            AudioManager.AUDIOFOCUS_REQUEST_FAILED -> startIncomingCallPlayback()
        }
    }
    private val incomingCallAudioFocusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                if (incomingCallRingingRequested) {
                    incomingCallHandler.removeCallbacks(delayedIncomingCallPlayback)
                    incomingCallHandler.postDelayed(delayedIncomingCallPlayback, 120)
                }
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                incomingCallPlayer?.let { player ->
                    runCatching { if (player.isPlaying) player.pause() }
                }
            }
            AudioManager.AUDIOFOCUS_LOSS -> stopIncomingCallRinging()
        }
    }
    private val systemBarCorrection = Runnable { applySystemBarAppearance() }

    override fun onCreate(savedInstanceState: Bundle?) {
        prepareLaunchSystemBar()
        val splashScreen = installSplashScreen()
        super.onCreate(savedInstanceState)
        applySystemBarAppearance()
        createCompanionNotificationChannel()
        splashScreen.setOnExitAnimationListener { provider ->
            provider.remove()
            scheduleSystemBarCorrection()
        }
    }

    private fun prepareLaunchSystemBar() {
        // Run before the splash-screen hand-off so vendor ROMs never get a
        // frame in which they can paint the status bar with their black default.
        window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        window.statusBarColor = Color.rgb(249, 252, 251)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility =
                window.decorView.systemUiVisibility or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
        }
    }

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        // Flutter configures its window again when the first frame is shown.
        // Reapply the app's light system bars after that final hand-off.
        scheduleSystemBarCorrection()
    }

    override fun onPostResume() {
        super.onPostResume()
        // ColorOS can restore its own launch-window status bar after Flutter's
        // first frame. Reapply after resume as well as after the first frame.
        scheduleSystemBarCorrection()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            scheduleSystemBarCorrection()
        }
    }

    private fun scheduleSystemBarCorrection() {
        val decor = window.decorView
        decor.removeCallbacks(systemBarCorrection)
        decor.post(systemBarCorrection)
        // Vendor ROMs may update the launch window asynchronously. These
        // bounded retries cover that hand-off without running a permanent job.
        decor.postDelayed(systemBarCorrection, 250L)
        decor.postDelayed(systemBarCorrection, 900L)
    }

    private fun applySystemBarAppearance() {
        WindowCompat.setDecorFitsSystemWindows(window, true)
        window.clearFlags(WindowManager.LayoutParams.FLAG_TRANSLUCENT_STATUS)
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        window.statusBarColor = Color.rgb(249, 252, 251)
        window.navigationBarColor = Color.TRANSPARENT
        WindowCompat.getInsetsController(window, window.decorView).apply {
            show(WindowInsetsCompat.Type.statusBars())
            show(WindowInsetsCompat.Type.navigationBars())
            isAppearanceLightStatusBars = true
            isAppearanceLightNavigationBars = true
        }
        val statusBarBackgroundId = resources.getIdentifier(
            "statusBarBackground",
            "id",
            "android",
        )
        if (statusBarBackgroundId != 0) {
            window.decorView.findViewById<View>(statusBarBackgroundId)
                ?.setBackgroundColor(Color.rgb(249, 252, 251))
        }
        ensureStatusBarOverlay()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
    }

    private fun ensureStatusBarOverlay() {
        val decor = window.decorView as? ViewGroup ?: return
        val heightResource = resources.getIdentifier("status_bar_height", "dimen", "android")
        val height = if (heightResource != 0) {
            resources.getDimensionPixelSize(heightResource)
        } else {
            (24 * resources.displayMetrics.density).toInt()
        }
        val overlay = statusBarOverlay ?: View(this).apply {
            isClickable = false
            isFocusable = false
            importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            statusBarOverlay = this
            decor.addView(
                this,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    height,
                    Gravity.TOP,
                ),
            )
        }
        overlay.setBackgroundColor(Color.rgb(249, 252, 251))
        overlay.bringToFront()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        localChatDatabase = LocalChatDatabase(this)

        val masterKey = MasterKey.Builder(this)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        val preferences = EncryptedSharedPreferences.create(
            this,
            "bingo_secure_storage",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "readToken" -> result.success(preferences.getString(TOKEN_KEY, null))
                "writeToken" -> {
                    val token = call.arguments as? String
                    if (token == null) {
                        result.error("invalid_token", "Token must be a string", null)
                    } else {
                        preferences.edit().putString(TOKEN_KEY, token).apply()
                        result.success(null)
                    }
                }
                "clearToken" -> {
                    preferences.edit().remove(TOKEN_KEY).apply()
                    result.success(null)
                }
                "readCallCaptionsEnabled" -> result.success(
                    preferences.getBoolean(CALL_CAPTIONS_ENABLED_KEY, false),
                )
                "writeCallCaptionsEnabled" -> {
                    val enabled = call.arguments as? Boolean
                    if (enabled == null) {
                        result.error("invalid_preference", "Value must be a boolean", null)
                    } else {
                        preferences.edit().putBoolean(CALL_CAPTIONS_ENABLED_KEY, enabled).apply()
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "createAlarm" -> createAlarm(call.arguments, result)
                    "pickImage" -> pickImage(result)
                    "takePhoto" -> takePhoto(result)
                    "startAudioCapture" -> requestAudioCapture(result)
                    "stopAudioCapture" -> {
                        stopAudioCapture()
                        result.success(null)
                    }
                    "startCallAudio" -> startCallAudio(call.arguments, result)
                    "playCallAudio" -> {
                        val audio = call.arguments as? ByteArray
                        if (audio == null) {
                            result.error("invalid_audio", "Audio must be bytes", null)
                        } else {
                            if (!callPlaybackQueue.offer(audio)) {
                                callPlaybackQueue.poll()
                                callPlaybackQueue.offer(audio)
                            }
                            result.success(null)
                        }
                    }
                    "clearCallAudio" -> {
                        clearCallAudio()
                        result.success(null)
                    }
                    "setCallSpeaker" -> {
                        setCallSpeaker(call.arguments as? Boolean ?: true)
                        result.success(null)
                    }
                    "stopCallAudio" -> {
                        stopCallAudio()
                        result.success(null)
                    }
                    "startIncomingCallRinging" -> {
                        startIncomingCallRinging()
                        result.success(null)
                    }
                    "stopIncomingCallRinging" -> {
                        stopIncomingCallRinging()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    audioEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    audioEventSink = null
                    stopAudioCapture()
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PUSH_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isConfigured" -> result.success(BuildConfig.GETUI_CONFIGURED)
                    "getDeviceInfo" -> {
                        var installationId = preferences.getString(INSTALLATION_KEY, null)
                        if (installationId == null) {
                            installationId = UUID.randomUUID().toString()
                            preferences.edit().putString(INSTALLATION_KEY, installationId).apply()
                        }
                        val packageInfo = packageManager.getPackageInfo(packageName, 0)
                        result.success(
                            mapOf(
                                "installation_id" to installationId,
                                "manufacturer" to Build.MANUFACTURER,
                                "model" to Build.MODEL,
                                "app_version" to packageInfo.versionName,
                            ),
                        )
                    }
                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                NOTIFICATION_REQUEST,
                            )
                        }
                        result.success(null)
                    }
                    "initialize" -> {
                        if (!BuildConfig.GETUI_CONFIGURED) {
                            result.success(false)
                        } else {
                            PushManager.getInstance().registerPushIntentService(
                                this,
                                BingoPushIntentService::class.java,
                            )
                            PushManager.getInstance().initialize(
                                this,
                                BingoPushService::class.java,
                            )
                            result.success(true)
                        }
                    }
                    "getClientId" -> {
                        val cached = getSharedPreferences(
                            BingoPushIntentService.PREFERENCES,
                            MODE_PRIVATE,
                        ).getString(BingoPushIntentService.CLIENT_ID, null)
                        result.success(cached ?: PushManager.getInstance().getClientid(this))
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCAL_CHAT_CHANNEL)
            .setMethodCallHandler { call, result ->
                runCatching {
                    val values = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                    val userId = values["user_id"] as? String
                    when (call.method) {
                        "loadActive" -> result.success(
                            localChatDatabase.loadActive(requireNotNull(userId)),
                        )
                        "listConversations" -> result.success(
                            localChatDatabase.listConversations(requireNotNull(userId)),
                        )
                        "loadConversation" -> result.success(
                            localChatDatabase.loadConversation(
                                requireNotNull(userId),
                                requireNotNull(values["conversation_id"] as? String),
                            ),
                        )
                        "saveConversation" -> {
                            @Suppress("UNCHECKED_CAST")
                            val messages = values["messages"] as? List<Map<*, *>> ?: emptyList()
                            localChatDatabase.saveConversation(
                                requireNotNull(userId),
                                requireNotNull(values["conversation_id"] as? String),
                                requireNotNull(values["title"] as? String),
                                messages,
                                values["updated_at"] as? Long ?: System.currentTimeMillis(),
                                requireNotNull(values["timeline_json"] as? String),
                            )
                            result.success(null)
                        }
                        "setActive" -> {
                            localChatDatabase.setActive(
                                requireNotNull(userId),
                                values["conversation_id"] as? String,
                            )
                            result.success(null)
                        }
                        "close" -> {
                            localChatDatabase.close()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }.onFailure { error ->
                    result.error("local_chat_error", error.message, null)
                }
            }
    }

    private fun pickImage(result: MethodChannel.Result) {
        if (!beginImageRequest(result)) return
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Intent(MediaStore.ACTION_PICK_IMAGES)
        } else {
            Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
        }.apply {
            type = "image/*"
        }
        try {
            startActivityForResult(intent, IMAGE_PICK_REQUEST)
        } catch (error: ActivityNotFoundException) {
            pendingImageResult = null
            result.error("image_picker_unavailable", "未找到可用的相册应用", null)
        }
    }

    private fun takePhoto(result: MethodChannel.Result) {
        if (!beginImageRequest(result)) return
        val cameraDirectory = File(cacheDir, "camera").apply { mkdirs() }
        val outputFile = File(cameraDirectory, "photo-${System.currentTimeMillis()}.jpg")
        val outputUri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            outputFile,
        )
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
            putExtra(MediaStore.EXTRA_OUTPUT, outputUri)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        pendingCameraFile = outputFile
        try {
            startActivityForResult(intent, IMAGE_CAPTURE_REQUEST)
        } catch (error: ActivityNotFoundException) {
            pendingImageResult = null
            pendingCameraFile = null
            outputFile.delete()
            result.error("camera_unavailable", "未找到可用的相机应用", null)
        }
    }

    private fun beginImageRequest(result: MethodChannel.Result): Boolean {
        if (pendingImageResult != null) {
            result.error("image_request_busy", "已有图片选择操作正在进行", null)
            return false
        }
        pendingImageResult = result
        return true
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != IMAGE_PICK_REQUEST && requestCode != IMAGE_CAPTURE_REQUEST) return
        val result = pendingImageResult ?: return
        pendingImageResult = null
        if (resultCode != Activity.RESULT_OK) {
            pendingCameraFile?.delete()
            pendingCameraFile = null
            result.success(null)
            return
        }
        try {
            val source = if (requestCode == IMAGE_CAPTURE_REQUEST) {
                pendingCameraFile?.readBytes()
                    ?: throw IllegalStateException("相机未返回照片")
            } else {
                val uri = data?.data ?: throw IllegalStateException("相册未返回图片")
                contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: throw IllegalStateException("无法读取所选图片")
            }
            val bitmap = decodeScaledBitmap(source, 1600)
                ?: throw IllegalArgumentException("无法解析图片")
            val output = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 85, output)
            if (!bitmap.isRecycled) bitmap.recycle()
            result.success(
                mapOf(
                    "bytes" to output.toByteArray(),
                    "mime_type" to "image/jpeg",
                ),
            )
        } catch (error: Exception) {
            result.error("image_read_failed", error.message ?: "图片读取失败", null)
        } finally {
            pendingCameraFile?.delete()
            pendingCameraFile = null
        }
    }

    private fun decodeScaledBitmap(bytes: ByteArray, maximumDimension: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sampleSize = 1
        while (bounds.outWidth / sampleSize > maximumDimension * 2 ||
            bounds.outHeight / sampleSize > maximumDimension * 2
        ) {
            sampleSize *= 2
        }
        val decoded = BitmapFactory.decodeByteArray(
            bytes,
            0,
            bytes.size,
            BitmapFactory.Options().apply { inSampleSize = sampleSize },
        ) ?: return null
        val largest = maxOf(decoded.width, decoded.height)
        if (largest <= maximumDimension) return decoded
        val scale = maximumDimension.toFloat() / largest
        val resized = Bitmap.createScaledBitmap(
            decoded,
            (decoded.width * scale).toInt().coerceAtLeast(1),
            (decoded.height * scale).toInt().coerceAtLeast(1),
            true,
        )
        if (resized !== decoded) decoded.recycle()
        return resized
    }

    private fun createCompanionNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            COMPANION_NOTIFICATION_CHANNEL,
            "Bingo 陪伴消息",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "提醒、问候和助手主动消息"
            enableVibration(true)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun createAlarm(arguments: Any?, result: MethodChannel.Result) {
        val values = arguments as? Map<*, *>
        val scheduledAt = values?.get("scheduled_at") as? String
        val label = values?.get("label") as? String
        val recurrence = values?.get("recurrence") as? String ?: "none"
        val scheduledTime = scheduledAt?.let(::parseIsoTime)
        if (scheduledTime == null || label.isNullOrBlank()) {
            result.error("invalid_alarm", "scheduled_at and label are required", null)
            return
        }

        val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
            val localTime = Calendar.getInstance().apply { timeInMillis = scheduledTime }
            putExtra(AlarmClock.EXTRA_HOUR, localTime.get(Calendar.HOUR_OF_DAY))
            putExtra(AlarmClock.EXTRA_MINUTES, localTime.get(Calendar.MINUTE))
            putExtra(AlarmClock.EXTRA_MESSAGE, label)
            when (recurrence) {
                "daily" -> putIntegerArrayListExtra(
                    AlarmClock.EXTRA_DAYS,
                    arrayListOf(1, 2, 3, 4, 5, 6, 7),
                )
                "weekdays" -> putIntegerArrayListExtra(
                    AlarmClock.EXTRA_DAYS,
                    arrayListOf(2, 3, 4, 5, 6),
                )
            }
        }

        try {
            // Let the system clock app show its confirmation screen. In
            // particular, ColorOS can reject silent alarm creation requests.
            startActivity(intent)
            result.success("system_alarm")
            return
        } catch (_: ActivityNotFoundException) {
            // Fall back to Bingo's alarm when no clock app accepts the intent.
        } catch (_: SecurityException) {
            // Some vendor clock apps reject external alarm requests.
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
        }

        // Keep Bingo's local alarm as a fallback for devices without a clock app
        // that accepts Android's standard ACTION_SET_ALARM intent.
        if (InAppAlarmScheduler.schedule(this, scheduledTime, label, recurrence)) {
            result.success("in_app")
        } else {
            result.error("alarm_schedule_failed", "Unable to schedule the local alarm", null)
        }
    }

    private fun requestAudioCapture(result: MethodChannel.Result) {
        if (recording || pendingAudioStartResult != null) {
            result.error("audio_busy", "Audio capture is already running", null)
            return
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            pendingAudioStartResult = result
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), AUDIO_PERMISSION_REQUEST)
            return
        }
        startAudioCapture(result)
    }

    private fun startAudioCapture(result: MethodChannel.Result) {
        val minBuffer = AudioRecord.getMinBufferSize(
            AUDIO_SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) {
            if (callAudio) stopCallAudio()
            result.error("audio_unavailable", "无法初始化手机麦克风", null)
            return
        }
        val bufferSize = maxOf(minBuffer, AUDIO_CHUNK_BYTES * 2)
        val recorder = try {
            AudioRecord(
                if (callAudio) {
                    MediaRecorder.AudioSource.VOICE_COMMUNICATION
                } else {
                    MediaRecorder.AudioSource.VOICE_RECOGNITION
                },
                AUDIO_SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
            )
        } catch (error: Exception) {
            if (callAudio) stopCallAudio()
            result.error("audio_unavailable", error.message ?: "无法打开手机麦克风", null)
            return
        }
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            if (callAudio) stopCallAudio()
            result.error("audio_unavailable", "手机麦克风初始化失败", null)
            return
        }
        recording = true
        val echoCanceler = if (callAudio && AcousticEchoCanceler.isAvailable()) {
            AcousticEchoCanceler.create(recorder.audioSessionId)?.apply { enabled = true }
        } else {
            null
        }
        val noiseSuppressor = if (callAudio && NoiseSuppressor.isAvailable()) {
            NoiseSuppressor.create(recorder.audioSessionId)?.apply { enabled = true }
        } else {
            null
        }
        recorder.startRecording()
        audioThread = Thread {
            val buffer = ByteArray(AUDIO_CHUNK_BYTES)
            try {
                while (recording) {
                    val count = recorder.read(buffer, 0, buffer.size)
                    if (count > 0) {
                        val chunk = buffer.copyOf(count)
                        runOnUiThread { audioEventSink?.success(chunk) }
                    }
                }
            } finally {
                runCatching { recorder.stop() }
                echoCanceler?.release()
                noiseSuppressor?.release()
                recorder.release()
            }
        }.apply {
            name = "bingo-audio-capture"
            isDaemon = true
            start()
        }
        result.success(null)
    }

    private fun stopAudioCapture() {
        recording = false
        audioThread = null
    }

    private fun startCallAudio(arguments: Any?, result: MethodChannel.Result) {
        if (recording || callPlaybackRunning) {
            result.error("audio_busy", "Audio is already in use", null)
            return
        }
        val values = arguments as? Map<*, *>
        callAudio = true
        setCallSpeaker(values?.get("speaker") as? Boolean ?: true)
        val minBuffer = AudioTrack.getMinBufferSize(
            CALL_OUTPUT_SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuffer <= 0) {
            callAudio = false
            restoreCallAudioRouting()
            result.error("audio_unavailable", "无法初始化通话扬声器", null)
            return
        }
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(CALL_OUTPUT_SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setBufferSizeInBytes(maxOf(minBuffer, CALL_OUTPUT_CHUNK_BYTES * 4))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        if (track.state != AudioTrack.STATE_INITIALIZED) {
            track.release()
            callAudio = false
            restoreCallAudioRouting()
            result.error("audio_unavailable", "通话扬声器初始化失败", null)
            return
        }
        callAudioTrack = track
        callPlaybackRunning = true
        callPlaybackQueue.clear()
        track.play()
        callPlaybackThread = Thread {
            while (callPlaybackRunning) {
                val audio = try {
                    callPlaybackQueue.take()
                } catch (_: InterruptedException) {
                    break
                }
                if (audio.isNotEmpty() && callPlaybackRunning) {
                    track.write(audio, 0, audio.size, AudioTrack.WRITE_BLOCKING)
                }
            }
        }.apply {
            name = "bingo-call-playback"
            isDaemon = true
            start()
        }
        requestAudioCapture(result)
    }

    private fun clearCallAudio() {
        callPlaybackQueue.clear()
        callAudioTrack?.let { track ->
            runCatching {
                track.pause()
                track.flush()
                track.play()
            }
        }
    }

    private fun setCallSpeaker(enabled: Boolean) {
        val manager = getSystemService(AudioManager::class.java)
        if (previousCallAudioMode == null) {
            previousCallAudioMode = manager.mode
            @Suppress("DEPRECATION")
            run { previousCallSpeakerphoneOn = manager.isSpeakerphoneOn }
        }
        manager.mode = AudioManager.MODE_IN_COMMUNICATION
        @Suppress("DEPRECATION")
        run { manager.isSpeakerphoneOn = enabled }
    }

    private fun stopCallAudio() {
        stopAudioCapture()
        callAudio = false
        callPlaybackRunning = false
        callPlaybackQueue.clear()
        callPlaybackThread?.interrupt()
        callPlaybackThread = null
        callAudioTrack?.let { track ->
            runCatching { track.pause() }
            runCatching { track.flush() }
            runCatching { track.stop() }
            track.release()
        }
        callAudioTrack = null
        restoreCallAudioRouting()
    }

    private fun restoreCallAudioRouting() {
        val manager = getSystemService(AudioManager::class.java)
        previousCallSpeakerphoneOn?.let { enabled ->
            @Suppress("DEPRECATION")
            run { manager.isSpeakerphoneOn = enabled }
        }
        previousCallAudioMode?.let { manager.mode = it }
        previousCallSpeakerphoneOn = null
        previousCallAudioMode = null
    }

    private fun startIncomingCallRinging() {
        stopIncomingCallRinging()
        incomingCallRingingRequested = true
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        incomingCallAudioAttributes = audioAttributes
        when (requestIncomingCallAudioFocus(audioAttributes)) {
            AudioManager.AUDIOFOCUS_REQUEST_GRANTED ->
                incomingCallHandler.postDelayed(delayedIncomingCallPlayback, 120)
            AudioManager.AUDIOFOCUS_REQUEST_FAILED ->
                incomingCallHandler.postDelayed(retryIncomingCallAudioFocus, 300)
        }
        incomingCallVibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        val pattern = longArrayOf(0L, 700L, 500L)
        incomingCallVibrator?.let { vibrator ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(pattern, 0)
            }
        }
    }

    private fun startIncomingCallPlayback() {
        if (!incomingCallRingingRequested) return
        incomingCallPlayer?.let { player ->
            runCatching {
                player.setVolume(1f, 1f)
                if (!player.isPlaying) player.start()
            }
            return
        }
        val audioAttributes = incomingCallAudioAttributes ?: return
        incomingCallPlayer = runCatching {
            MediaPlayer.create(
                this,
                R.raw.bingo_incoming_call,
                audioAttributes,
                AudioManager.AUDIO_SESSION_ID_GENERATE,
            )?.apply {
                isLooping = true
                setVolume(1f, 1f)
                start()
            }
        }.getOrNull()
        if (incomingCallPlayer == null) {
            val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            incomingCallRingtone = RingtoneManager.getRingtone(this, ringtoneUri)?.apply {
                this.audioAttributes = audioAttributes
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) isLooping = true
                play()
            }
        }
    }

    private fun stopIncomingCallRinging() {
        incomingCallRingingRequested = false
        incomingCallHandler.removeCallbacks(delayedIncomingCallPlayback)
        incomingCallHandler.removeCallbacks(retryIncomingCallAudioFocus)
        incomingCallPlayer?.let { player ->
            runCatching {
                if (player.isPlaying) player.stop()
            }
            player.release()
        }
        incomingCallPlayer = null
        incomingCallRingtone?.stop()
        incomingCallRingtone = null
        incomingCallVibrator?.cancel()
        incomingCallVibrator = null
        incomingCallAudioAttributes = null
        abandonIncomingCallAudioFocus()
    }

    private fun requestIncomingCallAudioFocus(attributes: AudioAttributes): Int {
        val manager = getSystemService(AudioManager::class.java)
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener(incomingCallAudioFocusListener)
                .setAcceptsDelayedFocusGain(true)
                .build()
            incomingCallAudioFocusRequest = request
            manager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            manager.requestAudioFocus(
                incomingCallAudioFocusListener,
                AudioManager.STREAM_ALARM,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT,
            )
        }
        hasLegacyIncomingCallAudioFocus =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.O &&
                result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return result
    }

    private fun abandonIncomingCallAudioFocus() {
        val manager = getSystemService(AudioManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            incomingCallAudioFocusRequest?.let(manager::abandonAudioFocusRequest)
            incomingCallAudioFocusRequest = null
        } else if (hasLegacyIncomingCallAudioFocus) {
            @Suppress("DEPRECATION")
            manager.abandonAudioFocus(incomingCallAudioFocusListener)
            hasLegacyIncomingCallAudioFocus = false
        }
    }

    override fun onDestroy() {
        stopIncomingCallRinging()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == AUDIO_PERMISSION_REQUEST) {
            val callback = pendingAudioStartResult ?: return
            pendingAudioStartResult = null
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                startAudioCapture(callback)
            } else {
                if (callAudio) stopCallAudio()
                callback.error("microphone_denied", "需要麦克风权限才能使用语音输入", null)
            }
        }
    }

    private fun parseIsoTime(value: String): Long? {
        val patterns = listOf("yyyy-MM-dd'T'HH:mm:ssXXX", "yyyy-MM-dd'T'HH:mmXXX")
        return patterns.firstNotNullOfOrNull { pattern ->
            runCatching {
                SimpleDateFormat(pattern, Locale.US).apply { isLenient = false }.parse(value)?.time
            }.getOrNull()
        }
    }

    private companion object {
        const val CHANNEL = "bingo/secure_storage"
        const val DEVICE_CHANNEL = "bingo/device_tools"
        const val IMAGE_PICK_REQUEST = 4101
        const val IMAGE_CAPTURE_REQUEST = 4102
        const val AUDIO_EVENT_CHANNEL = "bingo/audio_stream"
        const val LOCAL_CHAT_CHANNEL = "bingo/local_chat"
        const val PUSH_CHANNEL = "bingo/push"
        const val TOKEN_KEY = "access_token"
        const val CALL_CAPTIONS_ENABLED_KEY = "call_captions_enabled"
        const val INSTALLATION_KEY = "push_installation_id"
        const val NOTIFICATION_REQUEST = 9022
        const val AUDIO_PERMISSION_REQUEST = 9023
        const val AUDIO_SAMPLE_RATE = 16000
        const val AUDIO_CHUNK_BYTES = 3200
        const val CALL_OUTPUT_SAMPLE_RATE = 24000
        const val CALL_OUTPUT_CHUNK_BYTES = 4800
        const val COMPANION_NOTIFICATION_CHANNEL = "bingo_companion"
    }
}
