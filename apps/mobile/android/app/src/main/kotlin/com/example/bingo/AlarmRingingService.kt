package com.example.bingo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

class AlarmRingingService : Service() {
    private var toneGenerator: ToneGenerator? = null
    private val stopHandler = Handler(Looper.getMainLooper())
    private val stopTask = Runnable { stopSelf() }
    private val toneTask = object : Runnable {
        override fun run() {
            toneGenerator?.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, TONE_MS)
            stopHandler.postDelayed(this, TONE_REPEAT_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        val label = intent?.getStringExtra(InAppAlarmScheduler.EXTRA_LABEL) ?: "Bingo 闹钟"
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, AlarmRingingService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(label)
            .setContentText("闹钟正在响铃")
            .setContentIntent(contentIntent)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_media_pause, "停止", stopIntent)
            .build()
        startForeground(NOTIFICATION_ID, notification)
        startAlarmSound()
        stopHandler.removeCallbacks(stopTask)
        stopHandler.postDelayed(stopTask, MAX_RING_DURATION_MS)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopHandler.removeCallbacks(stopTask)
        stopHandler.removeCallbacks(toneTask)
        toneGenerator?.stopTone()
        toneGenerator?.release()
        toneGenerator = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startAlarmSound() {
        if (toneGenerator != null) return
        toneGenerator = ToneGenerator(AudioManager.STREAM_ALARM, 100)
        toneTask.run()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Bingo 闹钟",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Bingo 创建的本地闹钟"
            setSound(null, null)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private companion object {
        const val CHANNEL_ID = "bingo_alarms"
        const val ACTION_STOP = "com.example.bingo.action.STOP_ALARM"
        const val NOTIFICATION_ID = 7001
        const val MAX_RING_DURATION_MS = 10 * 60 * 1000L
        const val TONE_MS = 1_000
        const val TONE_REPEAT_MS = 1_400L
    }
}
