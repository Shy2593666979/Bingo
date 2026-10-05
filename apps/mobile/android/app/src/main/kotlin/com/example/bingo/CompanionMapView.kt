package com.example.bingo

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject

class CompanionMapFactory(private val activity: Activity, private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val parameters = args as? Map<*, *> ?: emptyMap<Any, Any>()
        require(parameters["privacy_agreed"] == true && available())
        consent(activity, true)
        return CompanionMapView(activity, messenger, viewId, parameters)
    }

    companion object {
        private var cached: JsMapSession? = null
        fun available(): Boolean = BuildConfig.AMAP_JS_KEY.isNotBlank() &&
            (BuildConfig.AMAP_JS_PROXY.startsWith("https://") ||
                (BuildConfig.DEBUG && BuildConfig.AMAP_JS_SECURITY_CODE.isNotBlank()))

        private fun consent(activity: Activity, agreed: Boolean) {
            activity.getSharedPreferences("map_privacy", Context.MODE_PRIVATE)
                .edit().putBoolean("agreed", agreed).apply()
        }

        private fun session(activity: Activity): JsMapSession {
            val existing = cached
            if (existing != null && existing.activity == activity && !existing.destroyed && !existing.failed) return existing
            existing?.destroy()
            return JsMapSession(activity).also { cached = it }
        }

        fun acquire(activity: Activity): JsMapSession = session(activity)

        fun release(session: JsMapSession) {
            if (cached == session) cached = null
        }

        fun register(activity: Activity, messenger: BinaryMessenger) {
            MethodChannel(messenger, "bingo/map_capability").setMethodCallHandler { call, result ->
                when (call.method) {
                    "available" -> result.success(available())
                    "consentStatus" -> result.success(activity.getSharedPreferences("map_privacy", Context.MODE_PRIVATE)
                        .getBoolean("agreed", false))
                    "consent" -> {
                        val agreed = call.argument<Boolean>("agreed") == true
                        consent(activity, agreed)
                        if (!agreed) { cached?.destroy(); cached = null }
                        result.success(null)
                    }
                    "prewarm" -> {
                        if (available() && activity.getSharedPreferences("map_privacy", Context.MODE_PRIVATE)
                                .getBoolean("agreed", false)) session(activity).warm()
                        result.success(null)
                    }
                    "pickerOverlay" -> {
                        (activity as? MainActivity)?.setLocationMapChrome(call.argument<Boolean>("enabled") == true)
                        result.success(null)
                    }
                    "privacyPolicy" -> {
                        runCatching { activity.startActivity(Intent(Intent.ACTION_VIEW,
                            Uri.parse("https://lbs.amap.com/pages/privacy/"))) }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}

class JsMapSession(val activity: Activity) : Application.ActivityLifecycleCallbacks {
    val web = WebView(activity)
    var destroyed = false
        private set
    private val handler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    var ready = false
        private set
    var failed = false
        private set
    private var pendingCenter: JSONObject? = null
    private val expire = Runnable { if (channel == null) destroy() }

    init {
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.settings.allowFileAccess = false
        web.settings.allowContentAccess = false
        web.settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        web.webChromeClient = WebChromeClient()
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = true
        }
        web.addJavascriptInterface(object {
            @JavascriptInterface
            fun event(payload: String) {
                if (payload.length > 1024) return
                val value = runCatching { JSONObject(payload) }.getOrNull() ?: return
                handler.post {
                    if (destroyed) return@post
                    when (value.optString("type")) {
                        "loaded" -> {
                            ready = true
                            pendingCenter?.let { center(it) }
                            channel?.invokeMethod("loaded", null)
                        }
                        "moving" -> channel?.invokeMethod("moving", null)
                        "idle" -> {
                            val longitude = value.optDouble("longitude")
                            val latitude = value.optDouble("latitude")
                            if (longitude.isFinite() && latitude.isFinite() && longitude in -180.0..180.0 && latitude in -85.0..85.0) {
                                channel?.invokeMethod("idle", mapOf("longitude" to longitude, "latitude" to latitude))
                            }
                        }
                        "unavailable" -> { failed = true; channel?.invokeMethod("unavailable", null) }
                    }
                }
            }
        }, "BingoMap")
        val security = if (BuildConfig.AMAP_JS_PROXY.isNotBlank())
            JSONObject().put("serviceHost", BuildConfig.AMAP_JS_PROXY)
        else JSONObject().put("securityJsCode", BuildConfig.AMAP_JS_SECURITY_CODE)
        val html = activity.assets.open("companion-map.html").bufferedReader().use { it.readText() }
            .replace("__SECURITY_CONFIG__", security.toString())
            .replace("__JS_KEY__", Uri.encode(BuildConfig.AMAP_JS_KEY))
        web.loadDataWithBaseURL("https://appassets.androidplatform.net/", html, "text/html", "UTF-8", null)
        activity.application.registerActivityLifecycleCallbacks(this)
        warm()
    }

    fun warm() {
        handler.removeCallbacks(expire)
        web.onResume()
        if (channel == null) handler.postDelayed(expire, 120000)
    }

    fun attach(target: MethodChannel) {
        warm()
        channel = target
        (web.parent as? ViewGroup)?.removeView(web)
        web.post {
            if (!destroyed && channel == target) {
                web.evaluateJavascript("window.bingoResize && window.bingoResize()", null)
                if (ready) target.invokeMethod("loaded", null)
            }
        }
    }

    fun center(value: JSONObject) {
        pendingCenter = value
        if (ready && !destroyed) web.evaluateJavascript("window.bingoCenter($value)", null)
    }

    fun detach(target: MethodChannel) {
        if (channel != target) return
        channel = null
        pendingCenter = null
        (web.parent as? ViewGroup)?.removeView(web)
        web.onPause()
        handler.postDelayed(expire, 120000)
    }

    fun destroy() {
        if (destroyed) return
        destroyed = true
        CompanionMapFactory.release(this)
        channel = null
        handler.removeCallbacksAndMessages(null)
        activity.application.unregisterActivityLifecycleCallbacks(this)
        (web.parent as? ViewGroup)?.removeView(web)
        web.stopLoading()
        web.removeJavascriptInterface("BingoMap")
        web.destroy()
    }

    override fun onActivityResumed(target: Activity) { if (target == activity && !destroyed) web.onResume() }
    override fun onActivityPaused(target: Activity) { if (target == activity && !destroyed) web.onPause() }
    override fun onActivityDestroyed(target: Activity) { if (target == activity) destroy() }
    override fun onActivityCreated(target: Activity, state: Bundle?) {}
    override fun onActivityStarted(target: Activity) {}
    override fun onActivityStopped(target: Activity) {}
    override fun onActivitySaveInstanceState(target: Activity, state: Bundle) {}
}

private class CompanionMapView(activity: Activity, messenger: BinaryMessenger, viewId: Int, parameters: Map<*, *>) : PlatformView {
    private val channel = MethodChannel(messenger, "bingo/map/$viewId")
    private val session = CompanionMapFactory.acquire(activity)
    init {
        session.attach(channel)
        session.center(JSONObject().put("longitude", (parameters["longitude"] as? Number)?.toDouble() ?: 116.397)
            .put("latitude", (parameters["latitude"] as? Number)?.toDouble() ?: 39.909))
        channel.setMethodCallHandler { call, result ->
            if (call.method == "ready") result.success(session.ready)
            else if (call.method != "center") result.notImplemented()
            else {
                val longitude = call.argument<Double>("longitude")
                val latitude = call.argument<Double>("latitude")
                if (longitude == null || latitude == null || !longitude.isFinite() || !latitude.isFinite() ||
                    longitude !in -180.0..180.0 || latitude !in -85.0..85.0) result.error("invalid_position", "Invalid map position", null)
                else {
                    session.center(JSONObject().put("longitude", longitude).put("latitude", latitude))
                    result.success(null)
                }
            }
        }
    }
    override fun getView(): View = session.web
    override fun dispose() { channel.setMethodCallHandler(null); session.detach(channel) }
}
