package com.example.bingo

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.Executors

class RegionLocationController(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val preferences = activity.getSharedPreferences("region_location", Context.MODE_PRIVATE)
    private val manager = activity.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var listener: LocationListener? = null
    private var permissionPending = false
    private var generation = 0
    private val timeout = Runnable { finish(mapOf("status" to "unavailable")) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val userId = call.argument<String>("user_id") ?: ""
        when (call.method) {
            "getEnabled" -> result.success(preferences.getBoolean("enabled:$userId", true))
            "setEnabled" -> {
                preferences.edit().putBoolean("enabled:$userId", call.argument<Boolean>("enabled") == true).apply()
                result.success(null)
            }
            "cancel" -> {
                if (!permissionPending) finish(mapOf("status" to "cancelled"))
                result.success(null)
            }
            "currentRegion" -> {
                if (pending != null) {
                    result.success(mapOf("status" to "busy"))
                    return
                }
                pending = result
                if (hasPermission()) {
                    locate()
                } else if (!preferences.getBoolean("permission_asked", false) || call.argument<Boolean>("retry") == true) {
                    preferences.edit().putBoolean("permission_asked", true).apply()
                    permissionPending = true
                    activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION), REQUEST_CODE)
                } else {
                    finish(mapOf("status" to "denied"))
                }
            }
            else -> result.notImplemented()
        }
    }

    fun onPermissionResult(requestCode: Int) {
        if (requestCode != REQUEST_CODE || !permissionPending || pending == null) return
        permissionPending = false
        if (hasPermission()) locate() else finish(mapOf("status" to "denied"))
    }

    private fun hasPermission(): Boolean = activity.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    @Suppress("DEPRECATION", "MissingPermission")
    private fun locate() {
        if (!Geocoder.isPresent()) {
            finish(mapOf("status" to "unavailable"))
            return
        }
        val currentGeneration = ++generation
        val fine = activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val providers = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER).filter {
            (fine || it != LocationManager.GPS_PROVIDER) && runCatching { manager.isProviderEnabled(it) }.getOrDefault(false)
        }
        if (providers.isEmpty()) {
            finish(mapOf("status" to "unavailable"))
            return
        }
        val callback = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (currentGeneration != generation || pending == null) return
                listener?.let { manager.removeUpdates(it) }
                listener = null
                executor.execute {
                    val region = runCatching {
                        val address = Geocoder(activity, Locale.SIMPLIFIED_CHINESE).getFromLocation(location.latitude, location.longitude, 1)?.firstOrNull()
                        val province = address?.adminArea.orEmpty()
                        val municipality = province in setOf("北京市", "天津市", "上海市", "重庆市")
                        val city = if (municipality) "" else address?.locality.orEmpty()
                        val district = address?.subLocality.orEmpty()
                        if (province.isBlank() || district.isBlank() || (!municipality && city.isBlank())) null
                        else mapOf("status" to "success", "province" to province, "city" to city, "district" to district)
                    }.getOrNull()
                    handler.post {
                        if (currentGeneration == generation) finish(region ?: mapOf("status" to "unavailable"))
                    }
                }
            }
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        }
        listener = callback
        handler.postDelayed(timeout, 20000)
        try {
            providers.forEach { manager.requestLocationUpdates(it, 0L, 0f, callback, Looper.getMainLooper()) }
        } catch (_: Exception) {
            finish(mapOf("status" to "unavailable"))
        }
    }

    private fun finish(value: Map<String, String>) {
        generation++
        handler.removeCallbacks(timeout)
        listener?.let { runCatching { manager.removeUpdates(it) } }
        listener = null
        val result = pending
        pending = null
        result?.success(value)
    }

    fun close() {
        permissionPending = false
        finish(mapOf("status" to "cancelled"))
        executor.shutdownNow()
    }

    fun cancelForBackground() {
        permissionPending = false
        finish(mapOf("status" to "cancelled"))
    }

    companion object {
        const val REQUEST_CODE = 9104
    }
}
