package com.example.bingo

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject

class CompanionReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            CompanionReminderScheduler.restore(context)
            return
        }
        val id = intent.getStringExtra("id") ?: return
        CompanionReminderScheduler.forget(context, id)
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel("bingo_moments", "伙伴小约定", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val open = PendingIntent.getActivity(context, id.hashCode(),
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, "bingo_moments")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(intent.getStringExtra("title") ?: "伙伴小约定")
            .setContentText(intent.getStringExtra("body") ?: "约定的时间到了")
            .setStyle(NotificationCompat.BigTextStyle().bigText(intent.getStringExtra("body")))
            .setContentIntent(open).setAutoCancel(true).build()
        manager.notify("bingo_moments", id.hashCode(), notification)
    }
}

object CompanionReminderScheduler {
    private fun preferences(context: Context) = context.getSharedPreferences("bingo_moment_reminders", Context.MODE_PRIVATE)
    private fun pending(context: Context, id: String, title: String = "", body: String = "") = PendingIntent.getBroadcast(
        context, 0, Intent(context, CompanionReminderReceiver::class.java)
            .setData(android.net.Uri.parse("bingo://moment/${android.net.Uri.encode(id)}"))
            .putExtra("id", id).putExtra("title", title).putExtra("body", body),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun schedule(context: Context, id: String, title: String, body: String, time: Long) {
        check(NotificationManagerCompat.from(context).areNotificationsEnabled()) { "请先在系统设置中允许 Bingo 通知" }
        require(time > System.currentTimeMillis()) { "请选择未来的提醒时间" }
        val manager = context.getSystemService(AlarmManager::class.java)
        manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time, pending(context, id, title, body))
        preferences(context).edit().putString(id, JSONObject().put("time", time).put("title", title).put("body", body).toString()).apply()
    }

    fun forget(context: Context, id: String) { preferences(context).edit().remove(id).apply() }

    fun cancel(context: Context, id: String) {
        context.getSystemService(AlarmManager::class.java).cancel(pending(context, id))
        context.getSystemService(NotificationManager::class.java).cancel("bingo_moments", id.hashCode())
        forget(context, id)
    }

    fun cancelAll(context: Context) {
        preferences(context).all.keys.toList().forEach { cancel(context, it) }
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.activeNotifications.filter { it.tag == "bingo_moments" }
            .forEach { manager.cancel(it.tag, it.id) }
    }

    fun restore(context: Context) {
        preferences(context).all.forEach { (id, raw) -> runCatching {
            val data = JSONObject(raw as String)
            val time = data.getLong("time")
            if (time > System.currentTimeMillis()) schedule(context, id, data.getString("title"), data.getString("body"), time)
            else forget(context, id)
        } }
    }
}
