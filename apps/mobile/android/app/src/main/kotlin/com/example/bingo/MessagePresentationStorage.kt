package com.example.bingo

import android.content.Context
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.security.MessageDigest
import org.json.JSONObject

/** Private, account-scoped voice recordings and local-only display decisions. */
class MessagePresentationStorage(private val context: Context) {
    private fun hash(value: String) = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray()).joinToString("") { "%02x".format(it) }
    private fun directory(account: String) = File(File(context.filesDir, "message_presentation"), hash(account))
    fun deleteAccount(account: String) { directory(account).deleteRecursively() }
    private fun write(file: File, bytes: ByteArray) {
        val atomic = AtomicFile(file)
        val stream = atomic.startWrite()
        try { stream.write(bytes); atomic.finishWrite(stream) }
        catch (error: Exception) { atomic.failWrite(stream); throw error }
    }
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "bingo/message_presentation", StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue()).setMethodCallHandler { call, result ->
            runCatching {
                val account = requireNotNull(call.argument<String>("account"))
                require(account.isNotBlank())
                val folder = directory(account).apply { check(exists() || mkdirs()) }
                val metadata = File(folder, "messages.json")
                when (call.method) {
                    "load" -> result.success(if (metadata.exists()) AtomicFile(metadata).readFully().toString(Charsets.UTF_8) else null)
                    "save" -> {
                        val data = requireNotNull(call.argument<String>("data"))
                        val json = JSONObject(data)
                        write(metadata, data.toByteArray())
                        // Locally deleted audio is no longer needed for playback.
                        json.keys().forEach { key -> if (json.getJSONObject(key).optBoolean("hidden")) File(folder, hash(key) + ".wav").delete() }
                        result.success(null)
                    }
                    "writeVoice" -> {
                        val bytes = requireNotNull(call.argument<ByteArray>("bytes"))
                        require(bytes.size in 44..(10 * 1024 * 1024))
                        write(File(folder, hash(requireNotNull(call.argument<String>("key"))) + ".wav"), bytes)
                        result.success(null)
                    }
                    "readVoice" -> {
                        val file = File(folder, hash(requireNotNull(call.argument<String>("key"))) + ".wav")
                        result.success(if (file.exists()) AtomicFile(file).readFully() else null)
                    }
                    else -> result.notImplemented()
                }
            }.onFailure { result.error("message_storage", "无法保存本机消息设置，请重试", null) }
        }
    }
}
