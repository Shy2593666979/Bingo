package com.example.bingo

import android.content.Context
import com.igexin.sdk.GTIntentService
import com.igexin.sdk.message.GTCmdMessage
import com.igexin.sdk.message.GTNotificationMessage
import com.igexin.sdk.message.GTTransmitMessage

class BingoPushIntentService : GTIntentService() {
    override fun onReceiveServicePid(context: Context, pid: Int) = Unit

    override fun onReceiveClientId(context: Context, clientId: String) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(CLIENT_ID, clientId)
            .apply()
    }

    override fun onReceiveMessageData(context: Context, message: GTTransmitMessage) = Unit

    override fun onReceiveOnlineState(context: Context, online: Boolean) = Unit

    override fun onReceiveCommandResult(context: Context, message: GTCmdMessage) = Unit

    override fun onNotificationMessageArrived(
        context: Context,
        message: GTNotificationMessage,
    ) = Unit

    override fun onNotificationMessageClicked(
        context: Context,
        message: GTNotificationMessage,
    ) = Unit

    companion object {
        const val PREFERENCES = "bingo_push"
        const val CLIENT_ID = "getui_client_id"
    }
}
