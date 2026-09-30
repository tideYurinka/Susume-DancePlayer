import 'package:dance_learning_app/core/cover_frame.dart';
import 'package:flutter_test/flutter_test.dart';

/// 封面取帧的命令装配纯件直测：输入视频路径、时刻与
/// 输出路径，输出 ffmpeg 参数表。裁切比例与输出尺寸由滤镜按**解码帧宽高**
/// 决定——ffmpeg 已按旋转元数据把画面转正，滤镜所见即用户所见。不触 ffmpeg、
/// 不依赖真实解码。
void main() {
  const videoPath = '/videos/a.mp4';
  const outputPath = '/covers/a.jpg';

  List<String> command({required int positionMs}) => buildCoverFrameArguments(
    videoPath: videoPath,
    position: Duration(milliseconds: positionMs),
    outputPath: outputPath,
  );

  String filterOf(List<String> args) => args[args.indexOf('-vf') + 1];

  /// 裁切窗口（`crop=<w>:<h>:…` 的前两段）。
  String cropWindowOf(List<String> args) =>
      RegExp(r'crop=([^:]+:[^:]+):').firstMatch(filterOf(args))!.group(1)!;

  /// 输出尺寸两个分支：横着（宽 ≥ 高）取 (宽, 高)，否则取后两者。
  (String, String, String, String) outputBranchesOf(List<String> args) {
    final match = RegExp(
      r'scale=if\(gte\(iw\\,ih\)\\,(\d+)\\,(\d+)\):'
      r'if\(gte\(iw\\,ih\)\\,(\d+)\\,(\d+)\)$',
    ).firstMatch(filterOf(args));
    return (match![1]!, match[2]!, match[3]!, match[4]!);
  }

  /// 输入后的第二个 seek（精确定位段）。
  int preciseSeekIndex(List<String> args) => args.lastIndexOf('-ss');

  group('比例决策：画面竖着裁 3:4 出 540×720、横着裁 4:3 出 720×540', () {
    test('裁切比例按解码帧朝向选：竖着 3:4，横着（含正方形）4:3', () {
      expect(
        cropWindowOf(command(positionMs: 5000)),
        r'min(iw\,ih*if(gt(ih\,iw)\,3/4\,4/3)):'
        r'min(ih\,iw/if(gt(ih\,iw)\,3/4\,4/3))',
      );
    });

    test('输出尺寸：横着 720×540、竖着 540×720（长边 720 恒为长的那边）', () {
      final (wideWidth, wideHeight, tallWidth, tallHeight) = outputBranchesOf(
        command(positionMs: 5000),
      );

      expect((wideWidth, wideHeight), ('720', '540'));
      expect((tallWidth, tallHeight), ('540', '720'));
    });

    test('取景窗口只从画面里裁、不放大，且居中', () {
      final vf = filterOf(command(positionMs: 5000));

      // 窗口宽 ≤ 画面宽、窗口高 ≤ 画面高：min(iw, …) / min(ih, …)。
      expect(vf, contains(r'min(iw\,ih*'));
      expect(vf, contains(r'min(ih\,iw/'));
      // 居中裁：窗口偏移取 (iw-ow)/2、(ih-oh)/2。
      expect(vf, contains('(iw-ow)/2:(ih-oh)/2'));
    });
  });

  group('命令装配：双 seek + 输出约束', () {
    test('输入前快进到目标前 2 秒，输入后精确定位到该帧', () {
      final args = command(positionMs: 5000);

      expect(args.first, '-y');
      // 输入前快进：目标 5s − 2s = 3s。
      expect(args[args.indexOf('-i') - 2], '-ss');
      expect(args[args.indexOf('-i') - 1], '3.000');
      expect(args[args.indexOf('-i') + 1], videoPath);
      // 输入后精确定位：剩下的 2s。
      expect(args[args.indexOf('-i') + 2], '-ss');
      expect(args[args.indexOf('-i') + 3], '2.000');
    });

    test('输出路径与 JPEG：单帧、质量档、「约 82」、显式 mjpeg、非影像流不取', () {
      final args = command(positionMs: 5000);

      expect(args[args.indexOf('-frames:v') + 1], '1');
      // mjpeg 的 -q:v 是 qscale 1–31（小 = 好）：4 ≈ libjpeg quality 82；
      // 传 82 会被钳到最差档。纯件断言常量，宿主 ffmpeg 实测不在此断言。
      expect(args[args.indexOf('-q:v') + 1], '$kCoverJpegQuality');
      expect(kCoverJpegQuality, 4);
      // 输出目标是 `…jpg.tmp`：不给格式 ffmpeg 猜不出封装会直接失败。
      expect(args[args.indexOf('-f') + 1], 'mjpeg');
      expect(args[args.indexOf('-an') + 1], '-sn');
      expect(args.last, outputPath);
    });
  });

  group('时刻越界：钳到片头（非负）', () {
    test('负时刻：钳到 0，不产出负数 seek', () {
      final args = command(positionMs: -1500);

      // 输入前没有快进段（-i 前紧邻 loglevel 值）；精确定位为 0。
      expect(args[args.indexOf('-i') + 1], videoPath);
      expect(args[args.indexOf('-i') - 1], 'error');
      expect(args[preciseSeekIndex(args) + 1], '0.000');
    });

    test('时刻 0：没有输入前快进（省掉零秒 seek）', () {
      final args = command(positionMs: 0);

      expect(args.indexOf('-ss'), preciseSeekIndex(args));
      expect(args[args.indexOf('-i') + 1], videoPath);
      expect(args[preciseSeekIndex(args) + 1], '0.000');
    });

    test('目标不足 2 秒：输入前快进 0、精确定位吃掉全部时刻', () {
      final args = command(positionMs: 1200);

      expect(args.indexOf('-ss'), preciseSeekIndex(args));
      expect(args[preciseSeekIndex(args) + 1], '1.200');
    });
  });
}
