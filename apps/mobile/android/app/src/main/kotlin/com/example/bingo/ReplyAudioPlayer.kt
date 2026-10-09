package com.example.bingo

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.atomic.AtomicInteger

class ReplyAudioPlayer(context: Context) {
    private var queue = LinkedBlockingQueue<ByteArray>(2048)
    private var pendingBytes = AtomicInteger(0)
    @Volatile private var generation = 0
    private var track: AudioTrack? = null
    private var worker: Thread? = null
    private var focus: AudioFocusRequest? = null
    private var completion: (() -> Unit)? = null
    private val manager = context.getSystemService(AudioManager::class.java)
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change -> if (change < 0) stop() }

    @Synchronized fun start() {
        stop()
        val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
        val granted = if (Build.VERSION.SDK_INT >= 26) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(attributes).setOnAudioFocusChangeListener(focusListener).build()
            focus = request
            manager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            manager.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        }
        check(granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { "音频正在被其他应用使用" }
        val buffer = AudioTrack.getMinBufferSize(24000, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val player = AudioTrack.Builder().setAudioAttributes(attributes)
            .setAudioFormat(AudioFormat.Builder().setSampleRate(24000)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).setEncoding(AudioFormat.ENCODING_PCM_16BIT).build())
            .setTransferMode(AudioTrack.MODE_STREAM).setBufferSizeInBytes(maxOf(buffer, 4800)).build()
        check(player.state == AudioTrack.STATE_INITIALIZED) { "无法初始化朗读播放器" }
        track = player
        val current = generation
        val pending = LinkedBlockingQueue<ByteArray>(2048)
        val bufferedBytes = AtomicInteger(0)
        queue = pending
        pendingBytes = bufferedBytes
        player.play()
        worker = Thread {
            var frames = 0L
            try {
                while (generation == current) {
                    val bytes = pending.take()
                    bufferedBytes.addAndGet(-bytes.size)
                    if (bytes.isEmpty()) {
                        val deadline = System.currentTimeMillis() + 5000
                        while (generation == current && player.playbackHeadPosition.toLong() < frames && System.currentTimeMillis() < deadline) Thread.sleep(20)
                        break
                    }
                    var offset = 0
                    while (generation == current && offset < bytes.size) {
                        val written = player.write(bytes, offset, bytes.size - offset, AudioTrack.WRITE_BLOCKING)
                        if (written <= 0) break
                        offset += written
                        frames += written / 2
                    }
                }
            } catch (_: Exception) {
            } finally {
                synchronized(this) { if (track === player) stop() }
            }
        }.apply { name = "bingo-reply-audio"; isDaemon = true; start() }
    }

    @Synchronized fun play(bytes: ByteArray) {
        check(track != null) { "朗读已停止" }
        require(bytes.size <= 16384 && bytes.size % 2 == 0) { "音频数据无效" }
        check(pendingBytes.get() + bytes.size <= 8 * 1024 * 1024) { "朗读缓冲已满" }
        pendingBytes.addAndGet(bytes.size)
        if (!queue.offer(bytes)) {
            pendingBytes.addAndGet(-bytes.size)
            error("朗读缓冲已满")
        }
    }

    @Synchronized fun finish(onComplete: () -> Unit) {
        if (track == null) {
            onComplete()
            return
        }
        check(completion == null) { "朗读正在结束" }
        check(queue.offer(ByteArray(0))) { "朗读缓冲已满" }
        completion = onComplete
    }

    @Synchronized fun stop() {
        generation++
        queue.clear()
        worker?.interrupt()
        worker = null
        track?.let { player ->
            runCatching { player.pause(); player.flush(); player.stop() }
            player.release()
        }
        track = null
        if (Build.VERSION.SDK_INT >= 26) focus?.let { manager.abandonAudioFocusRequest(it) }
        else {
            @Suppress("DEPRECATION")
            manager.abandonAudioFocus(focusListener)
        }
        focus = null
        val callback = completion
        completion = null
        callback?.invoke()
    }
}
