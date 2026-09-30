package top.yurinka.susume

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 原生震动通道：Dart 侧经 `dance_learning_app/native_haptic`
 * 的 `impact` 发一次短震。直走 `Vibrator` / `VibratorManager`，不依赖系统
 * 「触摸反馈」开关（HapticFeedback.mediumImpact 在 Android 映射为很轻的
 * CONTEXT_CLICK 且受该开关约束）。需清单声明 `android.permission.VIBRATE`
 * （普通权限，无运行时弹窗）。
 */
class NativeHapticPlugin(private val context: Context) {
    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "impact" -> {
                    vibrateOnce()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun vibrateOnce() {
        val vibrator =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager =
                    context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                manager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
        if (!vibrator.hasVibrator()) return
        vibrator.vibrate(
            VibrationEffect.createOneShot(
                VIBRATION_MILLIS,
                VibrationEffect.DEFAULT_AMPLITUDE,
            ),
        )
    }

    fun unregister(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler(null)
    }

    companion object {
        const val METHOD_CHANNEL = "dance_learning_app/native_haptic"
        const val VIBRATION_MILLIS = 40L
    }
}
