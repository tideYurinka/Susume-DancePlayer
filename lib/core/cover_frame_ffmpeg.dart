import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';

import 'cover_frame.dart';

/// [CoverFrameExecutor] 的生产实现：沿用工程既有的 ffmpeg 调用写法
/// （先例：`FFmpegKit.executeWithArguments` 同步执行 + 返回码判定，
/// 见 `beat/loudness_probe.dart`）——一次性取帧写 [outputPath]，质量与
/// 裁切由 [buildCoverFrameArguments] 装配。
///
/// 不与节拍分析共用解码实例（是
/// 对取帧路径的要求：这里只发一条只读取帧命令，不接管任何播放内核）。
class FfmpegCoverFrameExecutor implements CoverFrameExecutor {
  const FfmpegCoverFrameExecutor();

  @override
  Future<bool> execute(List<String> arguments) async {
    final session = await FFmpegKit.executeWithArguments(arguments);
    final returnCode = await session.getReturnCode();
    return ReturnCode.isSuccess(returnCode);
  }
}
