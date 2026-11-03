package com.example.bingo

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import org.json.JSONObject

/** Account-scoped preferences and private, persistent wallpaper files. */
class ChatAppearanceStorage(private val context: Context) {
    private val preferences = context.getSharedPreferences("bingo_appearance", Context.MODE_PRIVATE)
    private fun accountKey(userId: String): String = MessageDigest.getInstance("SHA-256")
        .digest(userId.toByteArray()).joinToString("") { "%02x".format(it) }
    private fun directory(userId: String) = File(File(context.filesDir, "wallpapers"), accountKey(userId))

    fun deleteAccount(userId: String) {
        preferences.edit().remove(accountKey(userId)).commit()
        directory(userId).deleteRecursively()
    }

    fun register(messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, "bingo/appearance", io.flutter.plugin.common.StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue())
        channel.setMethodCallHandler { call, result ->
            runCatching {
                val userId = requireNotNull(call.argument<String>("user_id"))
                require(userId.isNotBlank())
                when (call.method) {
                    "load" -> result.success(preferences.getString(accountKey(userId), null))
                    "save" -> {
                        val data = requireNotNull(call.argument<String>("data"))
                        val json = JSONObject(data)
                        check(preferences.edit().putString(accountKey(userId), data).commit())
                        val referenced = json.keys().asSequence().mapNotNull { json.optJSONObject(it)?.optString("photo") }.toSet()
                        directory(userId).listFiles()?.filter { it.absolutePath !in referenced }?.forEach { it.delete() }
                        result.success(null)
                    }
                    "importPhoto" -> {
                        val bytes = requireNotNull(call.argument<ByteArray>("bytes"))
                        require(bytes.isNotEmpty() && bytes.size <= 20 * 1024 * 1024)
                        val folder = directory(userId).apply { mkdirs() }
                        val name = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
                        val file = File(folder, "$name.jpg")
                        if (!file.exists()) file.writeBytes(bytes)
                        result.success(file.absolutePath)
                    }
                    else -> result.notImplemented()
                }
            }.onFailure { result.error("appearance_storage", "无法保存聊天外观，请重试", null) }
        }
    }
}
