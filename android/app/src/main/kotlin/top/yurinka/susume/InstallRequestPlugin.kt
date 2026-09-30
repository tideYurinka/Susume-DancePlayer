package top.yurinka.susume

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 安装请求通道：`susume/install_request` 的原生
 * 一半。三个方法同属"把应用私有目录里的安装包变成一次系统安装请求"这一件
 * 事——查询本应用是否已获「安装未知应用」授权、把用户送到该设置页、拉起系统
 * 安装器。安装器认的是 APK 自述的应用名（Susume）与版本号，本侧不传任何
 * 身份；覆盖安装会杀掉本应用进程，属正常行为。
 *
 * API < 26 没有"按应用授权"这一层：`canRequestInstall` 直接返回真，Dart 侧
 * 因此走直接请求安装的分支，与系统既有行为一致；`openInstallSettings` 在
 * 低版本是空操作（那个设置页不存在）。
 *
 * 请求安装用自建 FileProvider（authority = `<package>.fileprovider`，路径
 * 覆盖见 `res/xml/file_paths.xml` 的 `files-path`）换成 content URI + 读
 * 授权——不导出文件、不复制。
 */
class InstallRequestPlugin(private val activity: Activity) {

    fun register(flutterEngine: FlutterEngine) {
        channel(flutterEngine).setMethodCallHandler { call, result ->
            when (call.method) {
                "canRequestInstall" -> result.success(canRequestInstall())
                "openInstallSettings" -> {
                    try {
                        openInstallSettings()
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("settingsFailed", e.message, null)
                    }
                }
                "requestInstall" -> {
                    val path = call.arguments as? String
                    if (path.isNullOrEmpty()) {
                        result.error("badArgs", "requestInstall 缺少文件路径", null)
                        return@setMethodCallHandler
                    }
                    try {
                        requestInstall(File(path))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("installFailed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun unregister(flutterEngine: FlutterEngine) {
        channel(flutterEngine).setMethodCallHandler(null)
    }

    /** API 26 起才有按应用授权；更低的设备按系统既有行为直接请求安装。 */
    private fun canRequestInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            activity.packageManager.canRequestPackageInstalls()

    /** 本应用的「安装未知应用」设置页；API < 26 无此页，空操作。 */
    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        activity.startActivity(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:" + activity.packageName),
            ),
        )
    }

    private fun requestInstall(file: File) {
        val uri: Uri = FileProvider.getUriForFile(
            activity,
            activity.packageName + FILE_PROVIDER_AUTHORITY_SUFFIX,
            file,
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivity(intent)
    }

    private fun channel(flutterEngine: FlutterEngine): MethodChannel =
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        )

    companion object {
        private const val CHANNEL_NAME = "susume/install_request"

        // 与 AndroidManifest 的 FileProvider authority（${applicationId}.fileprovider）
        // 保持一致。
        private const val FILE_PROVIDER_AUTHORITY_SUFFIX = ".fileprovider"
    }
}
