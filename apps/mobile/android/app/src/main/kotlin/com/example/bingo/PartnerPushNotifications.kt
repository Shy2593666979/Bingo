package com.example.bingo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.net.Uri
import android.os.Build
import android.util.Base64
import android.util.Log
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

object PartnerPushNotifications {
    private const val PREFERENCES = "bingo_partner_notifications"
    private const val TAG = "bingo_partner"
    private val worker = Executors.newSingleThreadExecutor()
    private val assets = setOf("girlfriend.png", "boyfriend.png", "colleague.png",
        "teacher.png", "parent.png", "child.png", "bingo_logo.png")

    @Synchronized
    fun setAccount(context: Context, userId: String?) {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        if (preferences.getString("user_id", null) == userId) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val seen = JSONArray(preferences.getString("seen", "[]"))
        for (index in 0 until seen.length()) manager.cancel(TAG, seen.getString(index).hashCode())
        preferences.edit().clear().putString("user_id", userId).commit()
    }

    fun cacheAvatars(context: Context, userId: String, avatars: Map<*, *>) {
        worker.execute {
            val cached = JSONObject()
            avatars.entries.take(100).forEach { entry ->
                val roleId = entry.key as? String ?: return@forEach
                val data = entry.value as? String ?: return@forEach
                if (roleId.length > 128 || data.length > 2_000_000) return@forEach
                runCatching {
                    val bitmap = decode(Base64.decode(data.substringAfter(','), Base64.DEFAULT))
                        ?: return@runCatching
                    val output = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                    cached.put(roleId, Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP))
                }
            }
            synchronized(this) {
                val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                if (preferences.getString("user_id", null) == userId) {
                    preferences.edit().putString("avatars", cached.toString()).commit()
                }
            }
        }
    }

    fun receive(context: Context, bytes: ByteArray) {
        if (bytes.size > 12_288) return
        worker.execute {
            runCatching { show(context, JSONObject(String(bytes, Charsets.UTF_8))) }
                .onFailure { Log.w("BingoPush", "Partner notification failed (${it.javaClass.simpleName})") }
        }
    }

    @Synchronized
    private fun show(context: Context, payload: JSONObject) {
        if (payload.optString("type") != "proactive_message") return
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val userId = preferences.getString("user_id", null) ?: return
        if (userId != payload.optString("user_id")) return
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
        val messageId = payload.optString("message_id").take(128)
        val title = payload.optString("title").take(50)
        val body = payload.optString("body").take(500)
        if (messageId.isBlank() || title.isBlank() || body.isBlank()) return
        val seen = JSONArray(preferences.getString("seen", "[]"))
        if ((0 until seen.length()).any { seen.getString(it) == messageId }) return
        val roleId = payload.optString("role_id").take(128)
        val conversationId = payload.optString("conversation_id").take(128)
        val channelId = payload.optString("channel_id", "bingo_companion").take(64)
        val channelName = payload.optString("channel_name", "Bingo 陪伴消息").take(64)
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(channelId, channelName,
                NotificationManager.IMPORTANCE_HIGH))
        }
        val avatar = runCatching {
            val custom = JSONObject(preferences.getString("avatars", "{}"))
                .optString(roleId)
            if (custom.isNotBlank()) decode(Base64.decode(custom, Base64.DEFAULT)) else null
        }.getOrNull() ?: loadAsset(context, payload.optString("avatar"))
            ?: loadAsset(context, "bingo_logo.png") ?: return
        val intent = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse("bingo://conversation/${Uri.encode(conversationId)}"))
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = PendingIntent.getActivity(context, messageId.hashCode(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun content(maxLines: Int) = RemoteViews(context.packageName,
            R.layout.partner_push_notification).apply {
            setImageViewBitmap(R.id.partner_avatar, avatar)
            setContentDescription(R.id.partner_avatar, "$title 头像")
            setTextViewText(R.id.partner_title, title)
            setTextViewText(R.id.partner_body, body)
            setInt(R.id.partner_body, "setMaxLines", maxLines)
        }
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_companion_notification)
            .setContentTitle(title).setContentText(body)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(content(2)).setCustomBigContentView(content(6))
            .setCustomHeadsUpContentView(content(2))
            .setContentIntent(pending).setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH).setOnlyAlertOnce(true)
        manager.notify(TAG, messageId.hashCode(), builder.build())
        val updated = JSONArray()
        for (index in maxOf(0, seen.length() - 255) until seen.length()) updated.put(seen.getString(index))
        updated.put(messageId)
        preferences.edit().putString("seen", updated.toString()).commit()
    }

    private fun loadAsset(context: Context, filename: String): Bitmap? {
        val name = filename.takeIf { it in assets } ?: "bingo_logo.png"
        return runCatching {
            context.assets.open("flutter_assets/assets/images/$name").use { decode(it.readBytes()) }
        }.getOrNull()
    }

    private fun decode(bytes: ByteArray): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        val options = BitmapFactory.Options().apply { inSampleSize = 1 }
        while (maxOf(bounds.outWidth, bounds.outHeight) / options.inSampleSize > 256) {
            options.inSampleSize *= 2
        }
        val source = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options) ?: return null
        val edge = minOf(source.width, source.height)
        val left = (source.width - edge) / 2
        val top = (source.height - edge) / 2
        val result = Bitmap.createBitmap(128, 128, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(result)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        canvas.drawCircle(64f, 64f, 64f, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(source, Rect(left, top, left + edge, top + edge),
            RectF(0f, 0f, 128f, 128f), paint)
        return result
    }
}
