import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_min/statistics.dart';

import 'cast_render_executor.dart';

/// [CastRenderExecutor] 的生产实现：走已链接的 ffmpeg 包，**异步**执行
/// （`executeWithArgumentsAsync` + 统计回调）——同步执行拿不到进度，也没法在
/// 中途取消。
///
/// 进程真跑、取消走 [FFmpegKit.cancel]（按会话 id），所以本实现只在设备上被
/// 走到；测试经 [castRenderExecutorProvider] 注入脚本化替身，不跑进程。
class FfmpegCastRenderExecutor implements CastRenderExecutor {
  FfmpegCastRenderExecutor();

  /// 正在跑的那条会话（取消按它的 id 走；跑完即清）。
  FFmpegSession? _session;

  @override
  Future<CastRenderVerdict> run(
    CastRenderJob job, {
    void Function(CastRenderProgress progress)? onProgress,
  }) async {
    FFmpegSession? session;
    try {
      session = await FFmpegKit.executeWithArgumentsAsync(
        job.arguments,
        null,
        null,
        onProgress == null
            ? null
            : (Statistics statistics) => onProgress(
                CastRenderProgress(
                  rendered: Duration(
                    milliseconds: statistics.getTime() < 0
                        ? 0
                        : statistics.getTime(),
                  ),
                  total: job.total,
                ),
              ),
      );
      _session = session;
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        return CastRenderVerdict.succeeded;
      }
      if (ReturnCode.isCancel(returnCode)) {
        return CastRenderVerdict.cancelled;
      }
      return CastRenderVerdict.failed;
    } on Object {
      // 执行器本身报错（原生层异常、包不可用）与返回码非成功同一口径：
      // 这次渲染没成，收尾归编排器。
      return CastRenderVerdict.failed;
    } finally {
      if (identical(_session, session)) _session = null;
    }
  }

  @override
  Future<void> cancel() async {
    final session = _session;
    if (session == null) return;
    await FFmpegKit.cancel(session.getSessionId());
  }
}
