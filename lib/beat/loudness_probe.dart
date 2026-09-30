import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';

import 'preprocess.dart' show kSampleRate;

/// PCM RMS（纯函数）：均方根，空输入返回 0。
double pcmRms(List<double> pcm) {
  if (pcm.isEmpty) return 0.0;
  var sum = 0.0;
  for (final sample in pcm) {
    sum += sample * sample;
  }
  return math.sqrt(sum / pcm.length);
}

/// 歌曲响度测量 seam：返回该视频音轨的 PCM RMS（生产为 ffmpeg 解码测量，
/// 见 [FfmpegSongLoudnessProbe]）；测试注入定值。
abstract interface class SongLoudnessProbe {
  Future<double> pcmRms(String videoPath);
}

/// ffmpeg 解码响度测量（「节拍分析解码顺带测量；无分析记录先按默认基准、
/// 后台补测后更新」的独立补测路径）：一次性解码单声道
/// f32le PCM 到临时文件，流式累加平方和得 RMS（分析完即删，不缓存 PCM）。
class FfmpegSongLoudnessProbe implements SongLoudnessProbe {
  const FfmpegSongLoudnessProbe();

  @override
  Future<double> pcmRms(String videoPath) async {
    final tempDir = await Directory.systemTemp.createTemp('loudness_pcm_');
    final tempPcm = File('${tempDir.path}/pcm_f32.raw');
    try {
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-loglevel',
        'error',
        '-i',
        videoPath,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '$kSampleRate',
        '-f',
        'f32le',
        tempPcm.path,
      ]);
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        throw StateError('ffmpeg 解码失败: ${await session.getAllLogsAsString()}');
      }
      var sumSquares = 0.0;
      var count = 0;
      List<int> carry = const [];
      await for (final chunk in tempPcm.openRead()) {
        final bytes = carry.isEmpty ? chunk : [...carry, ...chunk];
        final usable = bytes.length - (bytes.length % 4);
        carry = bytes.sublist(usable);
        final data = ByteData.sublistView(
          Uint8List.fromList(bytes.sublist(0, usable)),
        );
        for (var i = 0; i + 4 <= usable; i += 4) {
          final s = data.getFloat32(i, Endian.little);
          sumSquares += s * s;
          count++;
        }
      }
      if (count == 0) {
        throw StateError('无有效音轨（解码输出为空）');
      }
      return math.sqrt(sumSquares / count);
    } finally {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } on Object {
        // 临时文件清理失败不影响测量结果。
      }
    }
  }
}
