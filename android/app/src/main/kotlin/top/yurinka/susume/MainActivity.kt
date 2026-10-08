package top.yurinka.susume

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var systemMediaVolumePlugin: SystemMediaVolumePlugin? = null
    private var audioOutputDevicePlugin: AudioOutputDevicePlugin? = null
    private var shareChannelPlugin: ShareChannelPlugin? = null
    private var nativeHapticPlugin: NativeHapticPlugin? = null
    private var installRequestPlugin: InstallRequestPlugin? = null
    private var systemMirrorSettingsPlugin: SystemMirrorSettingsPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        systemMediaVolumePlugin = SystemMediaVolumePlugin(this).also {
            it.register(flutterEngine)
        }
        audioOutputDevicePlugin = AudioOutputDevicePlugin(this).also {
            it.register(flutterEngine)
        }
        shareChannelPlugin = ShareChannelPlugin(this).also {
            it.register(flutterEngine)
        }
        nativeHapticPlugin = NativeHapticPlugin(this).also {
            it.register(flutterEngine)
        }
        installRequestPlugin = InstallRequestPlugin(this).also {
            it.register(flutterEngine)
        }
        systemMirrorSettingsPlugin = SystemMirrorSettingsPlugin(this).also {
            it.register(flutterEngine)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        shareChannelPlugin?.onNewIntent(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        shareChannelPlugin?.unregister(flutterEngine)
        shareChannelPlugin = null
        systemMediaVolumePlugin?.unregister(flutterEngine)
        systemMediaVolumePlugin = null
        audioOutputDevicePlugin?.unregister(flutterEngine)
        audioOutputDevicePlugin = null
        nativeHapticPlugin?.unregister(flutterEngine)
        nativeHapticPlugin = null
        installRequestPlugin?.unregister(flutterEngine)
        installRequestPlugin = null
        systemMirrorSettingsPlugin?.unregister(flutterEngine)
        systemMirrorSettingsPlugin = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
