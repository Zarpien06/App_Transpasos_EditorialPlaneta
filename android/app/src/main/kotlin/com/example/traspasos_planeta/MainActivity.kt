// android/app/src/main/kotlin/com/example/traspasos_planeta/MainActivity.kt

package com.example.traspasos_planeta

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.traspasos_planeta/kiosk"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startKiosk" -> {
                        try {
                            startLockTask() // 🔒 PIN DE PANTALLA REAL
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "stopKiosk" -> {
                        try {
                            stopLockTask() // 🔓 LIBERA
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", e.message, null)
                        }
                    }
                    "isKioskActive" -> {
                        try {
                            val am = getSystemService(Context.ACTIVITY_SERVICE) 
                                as ActivityManager
                            val locked = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
                            } else {
                                am.isInLockTaskMode
                            }
                            result.success(locked)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}