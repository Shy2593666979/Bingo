package com.example.bingo

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent

object InAppAlarmScheduler {
    const val EXTRA_LABEL = "alarm_label"

    fun schedule(
        context: Context,
        triggerAtMillis: Long,
        label: String,
        recurrence: String,
    ): Boolean {
        if (triggerAtMillis <= System.currentTimeMillis()) return false
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val alarmIntent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra(EXTRA_LABEL, label)
            putExtra("alarm_recurrence", recurrence)
        }
        val operation = PendingIntent.getBroadcast(
            context,
            (triggerAtMillis xor label.hashCode().toLong()).toInt(),
            alarmIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val showIntent = PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return runCatching {
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(triggerAtMillis, showIntent),
                operation,
            )
            true
        }.getOrElse {
            runCatching {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    operation,
                )
                true
            }.getOrElse {
                // Exact alarms can be restricted by some ColorOS versions. An
                // inexact alarm is still preferable to silently failing.
                runCatching {
                    alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, operation)
                    true
                }.getOrDefault(false)
            }
        }
    }
}
