package com.example.bingo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val serviceIntent = Intent(context, AlarmRingingService::class.java).apply {
            putExtra(
                InAppAlarmScheduler.EXTRA_LABEL,
                intent.getStringExtra(InAppAlarmScheduler.EXTRA_LABEL) ?: "Bingo 闹钟",
            )
        }
        ContextCompat.startForegroundService(context, serviceIntent)
    }
}
