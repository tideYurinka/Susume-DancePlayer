package top.yurinka.susume

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 编码器 1× 实时能力查询：`susume/encoder_realtime` 的原生一半，一条方法
 * `realtimeGuarantee`，回一句三态线值（`guaranteed` / `notGuaranteed` /
 * `unknown`）。
 *
 * ## 问的是「性能点」，问的尺寸由 Dart 侧给
 *
 * Android 10（API 29）给 `MediaCodecInfo.VideoCapabilities` 加了
 * `getSupportedPerformancePoints()`：系统逐台编码器地声明「这台编码器保证能
 * 同时做到多大尺寸、多少帧率」。本插件拿 h264 编码器（**硬编优先**——投屏
 * 渲染走 ffmpeg 的 `h264_mediacodec`，且性能点只有硬编会报）的性能点，问
 * 「覆盖得了这次要渲的尺寸吗」：
 *
 * - 尺寸是**入参**（`width` / `height` / `fps`，Dart 侧传过来）——原生不硬编
 *   任何一个数，于是 4K 源问的就是 4K，不会被一条更小的答案放行；
 * - 有性能点且有一条覆盖 ⇒ `guaranteed`（Dart 侧按那一档渲）；
 * - 有性能点但都不覆盖 ⇒ `notGuaranteed`（降到 720p）；
 * - **尺寸没给全 / 一条性能点都问不出来 / 一门 API 不在（API < 29，本仓
 *   minSdk 24）/ 读取出错** ⇒ `unknown`——Dart 侧把「问不到」与「不保证」
 *   同路处理（宁可降分辨率，也不给用户一个未知时长的进度条）。
 *
 * ## 边界
 *
 * 降不降级**不在这里**：本侧只老实回答三态，三态 → 分辨率档的决策住在 Dart
 * 侧的 `lib/cast/cast_encoder_realtime.dart`（可直测）。不申请任何权限、不用
 * `<queries>`（只读本机编解码器清单）。真机上读数的办法见
 * `lib/cast/docs/real-device-acceptance.md`（`adb logcat -s SusumeEncoderCapability`）。
 */
class EncoderRealtimeCapabilityPlugin {

    fun register(flutterEngine: FlutterEngine) {
        channel(flutterEngine).setMethodCallHandler { call, result ->
            when (call.method) {
                METHOD -> {
                    val arguments = call.arguments as? Map<*, *>
                    result.success(
                        query(
                            (arguments?.get(ARG_WIDTH) as? Number)?.toInt(),
                            (arguments?.get(ARG_HEIGHT) as? Number)?.toInt(),
                            (arguments?.get(ARG_FPS) as? Number)?.toInt(),
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    fun unregister(flutterEngine: FlutterEngine) {
        channel(flutterEngine).setMethodCallHandler(null)
    }

    /**
     * 三态线值。API < 29 上性能点这门 API 根本不存在——「问不到」在这条路上
     * 是**常态分支**，不是边角；尺寸没给全同样归到这一侧。
     */
    private fun query(width: Int?, height: Int?, frameRate: Int?): String {
        if (width == null || height == null || frameRate == null ||
            width <= 0 || height <= 0 || frameRate <= 0
        ) {
            Log.i(TAG, "目标尺寸没给全（$width x $height @ $frameRate）：按问不到处理")
            return UNKNOWN
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            Log.i(TAG, "性能点 API 不在（API ${Build.VERSION.SDK_INT} < 29）：按问不到处理")
            return UNKNOWN
        }
        return try {
            queryPerformancePoints(width, height, frameRate)
        } catch (e: Exception) {
            Log.i(TAG, "读编码器性能点失败：$e")
            UNKNOWN
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun queryPerformancePoints(width: Int, height: Int, frameRate: Int): String {
        val target = MediaFormat.createVideoFormat(MIME, width, height).apply {
            setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
        }
        val encoders = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            .filter { info ->
                info.isEncoder && info.supportedTypes.any { it.equals(MIME, true) }
            }
        // 硬编优先：性能点只有硬编报得出。
        val ordered = encoders.sortedByDescending { it.isHardwareAccelerated }
        for (codec in ordered) {
            val points = codec.getCapabilitiesForType(MIME)
                .videoCapabilities?.supportedPerformancePoints
            if (points.isNullOrEmpty()) {
                Log.i(TAG, "${codec.name}（硬编=${codec.isHardwareAccelerated}）不报性能点")
                continue
            }
            val covering = points.firstOrNull { it.covers(target) }
            Log.i(
                TAG,
                "${codec.name}（硬编=${codec.isHardwareAccelerated}）报了 ${points.size} 条性能点，" +
                    "覆盖 ${width}x${height}@$frameRate：${covering != null}",
            )
            return if (covering != null) GUARANTEED else NOT_GUARANTEED
        }
        Log.i(TAG, "没有任何 h264 编码器报得出性能点：按问不到处理")
        return UNKNOWN
    }

    private fun channel(flutterEngine: FlutterEngine): MethodChannel =
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        )

    companion object {
        private const val CHANNEL_NAME = "susume/encoder_realtime"
        private const val METHOD = "realtimeGuarantee"
        private const val ARG_WIDTH = "width"
        private const val ARG_HEIGHT = "height"
        private const val ARG_FPS = "fps"
        private const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC
        private const val GUARANTEED = "guaranteed"
        private const val NOT_GUARANTEED = "notGuaranteed"
        private const val UNKNOWN = "unknown"
        private const val TAG = "SusumeEncoderCapability"
    }
}
