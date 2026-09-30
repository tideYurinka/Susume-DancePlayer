package top.yurinka.susume

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/**
 * 系统媒体音量通道：Dart 侧经
 * `dance_learning_app/system_media_volume` 读写系统媒体音量
 * （`AudioManager STREAM_MUSIC`，与侧键/节拍声同流），经
 * `dance_learning_app/system_media_volume_events` 监听音量变化
 * （含侧键等应用外来源）。
 *
 * `set` 携带 `FLAG_SHOW_UI`：复用系统音量浮层呈现（以平台表现为准，
 * 真机看版）；归一化 0..1 ↔ 刻度 0..max 换算在 Dart/native 两侧同口径钳制。
 */
class SystemMediaVolumePlugin(private val context: Context) {
    private val audioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private var eventSink: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null

    private fun readVolume(): Map<String, Int> =
        mapOf(
            "volume" to audioManager.getStreamVolume(AudioManager.STREAM_MUSIC),
            "max" to audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
        )

    private fun volumeChanged() {
        eventSink?.success(readVolume())
    }

    fun register(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "get" -> result.success(readVolume())
                "set" -> {
                    val ratio = call.argument<Double>("volume") ?: 0.0
                    val max = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    val index = (ratio.coerceIn(0.0, 1.0) * max).roundToInt()
                    audioManager.setStreamVolume(
                        AudioManager.STREAM_MUSIC,
                        index,
                        AudioManager.FLAG_SHOW_UI,
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    val volumeReceiver = object : BroadcastReceiver() {
                        override fun onReceive(receiverContext: Context?, intent: Intent?) {
                            volumeChanged()
                        }
                    }
                    receiver = volumeReceiver
                    val filter = IntentFilter("android.media.VOLUME_CHANGED_ACTION")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        context.registerReceiver(volumeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        context.registerReceiver(volumeReceiver, filter)
                    }
                    volumeChanged()
                }

                override fun onCancel(arguments: Any?) {
                    receiver?.let { context.unregisterReceiver(it) }
                    receiver = null
                    eventSink = null
                }
            }
        )
    }

    fun unregister(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler(null)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).setStreamHandler(null)
    }

    companion object {
        const val METHOD_CHANNEL = "dance_learning_app/system_media_volume"
        const val EVENT_CHANNEL = "dance_learning_app/system_media_volume_events"
    }
}
