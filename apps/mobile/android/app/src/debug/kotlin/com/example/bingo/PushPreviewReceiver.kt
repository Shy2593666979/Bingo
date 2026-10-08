package com.example.bingo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Base64

class PushPreviewReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val encoded = intent.getStringExtra("payload") ?: return
        if (encoded.length > 20_000) return
        runCatching {
            PartnerPushNotifications.receive(context,
                Base64.decode(encoded, Base64.URL_SAFE or Base64.NO_WRAP))
        }
    }
}
