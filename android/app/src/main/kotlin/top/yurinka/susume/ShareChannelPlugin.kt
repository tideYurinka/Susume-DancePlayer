package top.yurinka.susume

import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 平台分享通道：`susume/share_channel` 的原生一半。
 * 出站：Dart 经 `shareFile` 传来应用目录内的原文件路径；这里用自建
 * FileProvider（authority = `<package>.fileprovider`，路径覆盖见
 * `res/xml/file_paths.xml`）换成 content URI + 读权限，起 `ACTION_SEND`
 * chooser 交给系统分享面板。零复制：不复制文件，不引 share_plus。
 * 失败（文件不存在/无面板可接）经 result.error 回传，Dart 侧出声不静默。
 *
 * 入站：容量为 1 的留存槽。冷启动的 intent 由本侧
 * 留存、Dart 拉（`takePendingInbound`，取走即清）；热启动走 `onNewIntent`
 * 落同一槽并推给 Dart——Dart 通道未就绪时只留槽，就绪后由拉取兜底，
 * 两条路径都不丢。`materializeInbound` 把 content URI
 * 整份复制进应用目录后把路径交 Dart 侧——只读授权下 openInputStream
 * 可能是管道，随机寻址不可假设（zip 的中央目录在文件尾）。
 */
class ShareChannelPlugin(private val activity: Activity) {

    private var engine: FlutterEngine? = null
    private var pendingInboundUri: String? = null

    fun register(flutterEngine: FlutterEngine) {
        engine = flutterEngine
        channel(flutterEngine).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareFile" -> {
                    val path = call.arguments as? String
                    if (path.isNullOrEmpty()) {
                        result.error("badArgs", "shareFile 缺少文件路径", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri: Uri = fileUri(File(path))
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = "application/octet-stream"
                            // clipData 与 EXTRA_STREAM 同时携带并两处授权：
                            // 个别 OEM/旧版本的 chooser 只转发 clipData 上的授权。
                            clipData = ClipData.newRawUri(null, uri)
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        activity.startActivity(
                            Intent.createChooser(intent, "分享"),
                        )
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("shareFailed", e.message, null)
                    }
                }
                "takePendingInbound" -> {
                    result.success(pendingInboundUri)
                    pendingInboundUri = null
                }
                "materializeInbound" -> {
                    val uri = call.argument<String>("uri")
                    val destPath = call.argument<String>("destPath")
                    if (uri == null || destPath == null) {
                        result.error("badArgs", "uri 与 destPath 必填", null)
                    } else {
                        result.success(materializeInbound(uri, destPath))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun unregister(flutterEngine: FlutterEngine) {
        channel(flutterEngine).setMethodCallHandler(null)
        engine = null
    }

    fun onNewIntent(intent: Intent?) {
        val uri = inboundUriOf(intent) ?: return
        pendingInboundUri = uri
        engine?.let { channel(it).invokeMethod("onInboundShare", uri) }
    }

    private fun inboundUriOf(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        return intent.data?.toString()
    }

    private fun fileUri(file: File): Uri = FileProvider.getUriForFile(
        activity,
        activity.packageName + FILE_PROVIDER_AUTHORITY_SUFFIX,
        file,
    )

    private fun materializeInbound(uri: String, destPath: String): Boolean {
        return try {
            val input = activity.contentResolver.openInputStream(Uri.parse(uri))
            if (input == null) {
                false
            } else {
                input.use {
                    File(destPath).outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
                true
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun channel(flutterEngine: FlutterEngine): MethodChannel =
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        )

    companion object {
        private const val CHANNEL_NAME = "susume/share_channel"

        // 与 AndroidManifest 的 FileProvider authority（${applicationId}.fileprovider）
        // 保持一致；authority 规则单处在这里给后缀。
        private const val FILE_PROVIDER_AUTHORITY_SUFFIX = ".fileprovider"
    }
}
