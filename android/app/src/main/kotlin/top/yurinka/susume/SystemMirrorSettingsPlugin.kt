package top.yurinka.susume

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 系统镜像入口：`susume/system_mirror` 的原生一半。
 *
 * 本项目**不做**屏幕镜像（ADR-0004，本平台对第三方 App 封死了这条路）；本
 * 通道只负责把用户**送到**系统自带的设置页。两页各一条方法：
 * `openCastSettings` = 系统的「投屏 / 无线显示」设置
 * （`Settings.ACTION_CAST_SETTINGS`，public API since 21，minSdk 24 恒可用），
 * `openDisplaySettings` = 显示设置（`Settings.ACTION_DISPLAY_SETTINGS`）。
 *
 * **降级顺序不在这里**：先问投屏设置、它接不住再退显示设置、两级都不行由
 * Dart 侧给一句短暂提示——那条链住在 `lib/cast/platform_system_mirror.dart`
 * （可直测）。本侧只老实回答"这一页打不打得开"（true / false），不替 Dart
 * 决定次序，也不认识投屏会话；断开投屏发生在 Dart 侧跳转之前。
 *
 * 不用 `resolveActivity` 预判：Android 11+ 的包可见性会把对系统设置页的查询
 * 过滤掉，判不准；直接 `startActivity` 并接 `ActivityNotFoundException` 才
 * 可靠。因此本功能也**不需要**任何 `<queries>` 声明（所有 `Intent` 都是公开
 * 的 settings action，两条跳转都不申请权限）。
 */
class SystemMirrorSettingsPlugin(private val activity: Activity) {

    fun register(flutterEngine: FlutterEngine) {
        channel(flutterEngine).setMethodCallHandler { call, result ->
            when (call.method) {
                "openCastSettings" ->
                    result.success(open(Settings.ACTION_CAST_SETTINGS))
                "openDisplaySettings" ->
                    result.success(open(Settings.ACTION_DISPLAY_SETTINGS))
                else -> result.notImplemented()
            }
        }
    }

    fun unregister(flutterEngine: FlutterEngine) {
        channel(flutterEngine).setMethodCallHandler(null)
    }

    /** true = 系统接住了这一页；false = 这台设备没有这一页（降级链据此往下一级退）。 */
    private fun open(action: String): Boolean = try {
        activity.startActivity(Intent(action))
        true
    } catch (e: ActivityNotFoundException) {
        false
    } catch (e: Exception) {
        // 其它失败（安全策略拦下等）与"没有这一页"同一口径：交 Dart 侧降级。
        false
    }

    private fun channel(flutterEngine: FlutterEngine): MethodChannel =
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        )

    companion object {
        private const val CHANNEL_NAME = "susume/system_mirror"
    }
}
