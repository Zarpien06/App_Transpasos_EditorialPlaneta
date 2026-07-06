package com.planeta.traspasos

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.ejemplo.traspasos_planeta/kiosk"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "startKiosk" -> {
                        try {
                            window.addFlags(
                                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                            )
                            startLockTask()
                            hideSystemUI()
                            result.success(true)
                        } catch (e: Exception) {
                            // Si startLockTask falla igual aplicamos UI flags
                            hideSystemUI()
                            result.success(false)
                        }
                    }

                    "stopKiosk" -> {
                        try {
                            stopLockTask()
                            window.clearFlags(
                                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                            )
                            showSystemUI()
                            result.success(true)
                        } catch (e: Exception) {
                            showSystemUI()
                            result.success(false)
                        }
                    }

                    "getLockTaskMode" -> {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            am.lockTaskModeState
                        } else {
                            @Suppress("DEPRECATION")
                            if (am.isInLockTaskMode) 1 else 0
                        }
                        result.success(mode)
                    }

                    "hideSystemUI" -> { hideSystemUI(); result.success(true) }
                    "showSystemUI" -> { showSystemUI(); result.success(true) }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Oculta SOLO la barra de navegación inferior (atrás/inicio/recientes).
     * La status bar SUPERIOR (batería, señal, hora, nombre dispositivo)
     * queda VISIBLE intencionalmente.
     */
    private fun hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let { ctrl ->
                // ✅ Solo ocultar navegación inferior
                ctrl.hide(WindowInsets.Type.navigationBars())
                // ✅ Asegurar que la status bar superior esté visible
                ctrl.show(WindowInsets.Type.statusBars())
                // Al deslizar desde el borde inferior aparece nav bar brevemente
                ctrl.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                // ✅ SIN FULLSCREEN ni LAYOUT_FULLSCREEN — esos ocultaban la status bar
            )
        }
    }

    /**
     * Muestra ambas barras (status bar + navegación).
     * Se usa al desactivar el modo kiosco.
     */
    private fun showSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.show(
                WindowInsets.Type.navigationBars() or WindowInsets.Type.statusBars()
            )
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_VISIBLE
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val enKiosco = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            @Suppress("DEPRECATION")
            am.isInLockTaskMode
        }
        // Al recuperar foco en modo kiosco, reaplicar UI flags correctos
        if (hasFocus && enKiosco) hideSystemUI()
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        // Bloqueado intencionalmente en modo kiosco
    }
}