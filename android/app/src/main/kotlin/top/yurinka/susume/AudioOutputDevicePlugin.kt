package top.yurinka.susume

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * 音频输出设备通道：Dart 侧经
 * `dance_learning_app/audio_output_device` 取当前输出设备快照
 * （`AudioManager.getDevices`），经
 * `dance_learning_app/audio_output_device_events` 监听路由变化
 * （`AudioDeviceCallback`）。枚举与路由监听均无需权限；产品名缺失/
 * 不可辨识时回退类型标签并归「其它设备」（设备键由 Dart 侧组装）。
 *
 * 当前设备选取：优先「外接」输出（蓝牙 A2DP → USB 耳机/设备 → 有线
 * 耳机/耳麦），无外接时回退机内扬声器/听筒；无任何输出设备时回 null。
 */
class AudioOutputDevicePlugin(private val context: Context) {
    private val audioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private var callback: AudioDeviceCallback? = null

    private fun typeLabel(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "蓝牙"
        AudioDeviceInfo.TYPE_USB_HEADSET -> "USB耳机"
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_ACCESSORY -> "USB音频"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "有线耳机"
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "扬声器"
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "听筒"
        AudioDeviceInfo.TYPE_HDMI,
        AudioDeviceInfo.TYPE_HDMI_ARC,
        AudioDeviceInfo.TYPE_HDMI_EARC -> "HDMI"
        else -> "音频设备"
    }

    // 外接优先序（值越小越优先；机内设备兜底）。
    private fun priority(type: Int): Int = when (type) {
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> 0
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_ACCESSORY -> 1
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> 2
        AudioDeviceInfo.TYPE_HDMI,
        AudioDeviceInfo.TYPE_HDMI_ARC,
        AudioDeviceInfo.TYPE_HDMI_EARC -> 3
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> 4
        else -> 5
    }

    private fun currentDevice(): Map<String, String>? {
        // getDevices / AudioDeviceCallback 均为 API 23+；更低版本无设备
        // 键控（Dart 侧兜底「其它设备」）。
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val device = outputs.minByOrNull { priority(it.type) } ?: return null
        val product = device.productName?.toString()?.trim()
        return mapOf(
            "type" to typeLabel(device.type),
            "product" to (if (product.isNullOrEmpty()) "" else product),
        )
    }

    fun register(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "get" -> result.success(currentDevice())
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
                    val deviceCallback = object : AudioDeviceCallback() {
                        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
                            events?.success(currentDevice())
                        }

                        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
                            events?.success(currentDevice())
                        }
                    }
                    callback = deviceCallback
                    // handler 空则回调缺 Looper 会抛；用主线程 Looper。
                    audioManager.registerAudioDeviceCallback(
                        deviceCallback,
                        Handler(Looper.getMainLooper()),
                    )
                    // 监听即发快照（Dart 侧以流首事件对齐当前设备）。
                    events?.success(currentDevice())
                }

                override fun onCancel(arguments: Any?) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        callback?.let { audioManager.unregisterAudioDeviceCallback(it) }
                    }
                    callback = null
                }
            },
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            callback?.let { audioManager.unregisterAudioDeviceCallback(it) }
        }
        callback = null
    }

    companion object {
        const val METHOD_CHANNEL = "dance_learning_app/audio_output_device"
        const val EVENT_CHANNEL = "dance_learning_app/audio_output_device_events"
    }
}
